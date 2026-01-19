# Plan: AMD64 Darwin Syscall Routing + Multi-Arch CI

## Problem Statement

1. **AMD64 binaries crash on macOS**: `sys_cosmo_amd64.s` uses raw `SYSCALL` instructions which crash with SIGSYS on macOS (both x86_64 and ARM64 via Rosetta)
2. **CI only builds AMD64**: APE binaries should contain both AMD64 and ARM64 code to run natively on all platforms

## Part 1: AMD64 Darwin Syscall Routing

### Files to Modify

1. **`src/runtime/rt0_cosmo_amd64.s`** - Capture `__hostos` and `__syslib` from APE loader
2. **`src/runtime/os_cosmo_amd64.go`** - Add `__hostos`/`__syslib` variables
3. **`src/runtime/sys_cosmo_amd64.s`** - Add darwin branches to all syscalls
4. **`src/internal/runtime/syscall/cosmo/asm_cosmo_amd64.s`** - Add darwin dispatch to Syscall6

### x86_64 C ABI (differs from ARM64)

- Arguments: RDI, RSI, RDX, RCX, R8, R9 (first 6 args)
- Return value: RAX
- Caller-saved: RAX, RCX, RDX, RSI, RDI, R8-R11
- Stack must be 16-byte aligned before CALL

### AMD64 CHECK_DARWIN Macro

```asm
#define HOSTXNU $8

#define CHECK_DARWIN(label) \
    MOVL    runtime·__hostos(SB), AX; \
    CMPL    $HOSTXNU, AX; \
    JEQ     label
```

### Syscall Mapping (Linux x86_64 → Syslib Offset)

| Syscall | Linux Number | Syslib Offset |
|---------|-------------|---------------|
| read | 0 | 264 |
| write | 1 | 256 |
| close | 3 | 232 |
| mmap | 9 | 40 |
| munmap | 11 | 240 |
| nanosleep | 35 | 32 |
| clock_gettime | 228 | 24 |
| exit_group | 231 | 224 |
| openat | 257 | 248 |
| sigaltstack | 131 | 296 |
| rt_sigaction | 13 | 272 |
| mprotect | 10 | 288 |

### Implementation Steps

#### Step 1: Add __hostos/__syslib to os_cosmo_amd64.go

```go
var (
    __hostos uint32
    __syslib uintptr
)
```

#### Step 2: Update rt0_cosmo_amd64.s

**Current state**: AMD64 rt0 just does `JMP _rt0_amd64(SB)` - no capture at all!

**ARM64 reference**: APE loader (ape-m1.c) passes:
- X3 = host OS indicator (8 = XNU/macOS)
- X15 = Syslib pointer

**AMD64 needs**: Research x86_64 APE loader (ape.S or similar) to find:
- Which register contains hostos on x86_64
- Which register contains syslib pointer on x86_64

Then add:
```asm
DATA runtime·__hostos+0(SB)/4, $0
GLOBL runtime·__hostos(SB), NOPTR, $4

DATA runtime·__syslib+0(SB)/8, $0
GLOBL runtime·__syslib(SB), NOPTR, $8

TEXT _rt0_amd64_cosmo(SB),NOSPLIT,$-8
    // Capture APE loader values (registers TBD from Cosmopolitan source)
    MOVL    <hostos_reg>, runtime·__hostos(SB)
    MOVQ    <syslib_reg>, runtime·__syslib(SB)
    JMP     _rt0_amd64(SB)
```

#### Step 3: Update sys_cosmo_amd64.s

Add darwin branches to each syscall. Example for write:

```asm
TEXT runtime·write1(SB),NOSPLIT,$0-28
    CHECK_DARWIN(write1_darwin)
    // Linux path (existing)
    MOVQ    fd+0(FP), DI
    MOVQ    p+8(FP), SI
    MOVL    n+16(FP), DX
    MOVL    $SYS_write, AX
    SYSCALL
    MOVL    AX, ret+24(FP)
    RET

write1_darwin:
    MOVQ    runtime·__syslib(SB), R9
    MOVQ    256(R9), AX              // syslib.write
    MOVQ    fd+0(FP), DI
    MOVQ    p+8(FP), SI
    MOVL    n+16(FP), DX
    SUBQ    $8, SP                   // Align stack
    CALL    AX
    ADDQ    $8, SP
    MOVL    AX, ret+24(FP)
    RET
```

#### Step 4: Update asm_cosmo_amd64.s (Syscall6)

Add darwin dispatch similar to ARM64:

```asm
TEXT ·Syscall6(SB),NOSPLIT,$0-80
    CHECK_DARWIN(syscall6_darwin)
    // Linux path (existing SYSCALL)
    ...

syscall6_darwin:
    MOVQ    num+0(FP), R11          // syscall number
    MOVQ    runtime·__syslib(SB), R10

    // Load arguments for C call (x86_64 ABI)
    MOVQ    a1+8(FP), DI
    MOVQ    a2+16(FP), SI
    MOVQ    a3+24(FP), DX
    MOVQ    a4+32(FP), CX
    MOVQ    a5+40(FP), R8
    MOVQ    a6+48(FP), R9

    // Dispatch based on syscall number
    CMPL    $1, R11                 // SYS_write
    JEQ     darwin_write
    CMPL    $0, R11                 // SYS_read
    JEQ     darwin_read
    // ... more syscalls ...

    // Unknown - return ENOSYS
    MOVQ    $-1, r1+56(FP)
    MOVQ    $38, errno+72(FP)       // ENOSYS
    RET

darwin_write:
    MOVQ    256(R10), AX
    JMP     darwin_call
darwin_read:
    MOVQ    264(R10), AX
    JMP     darwin_call

darwin_call:
    SUBQ    $8, SP                  // Align stack
    CALL    AX
    ADDQ    $8, SP
    // Handle return
    CMPQ    AX, $-4095
    JCC     darwin_success
    NEGQ    AX
    MOVQ    $-1, r1+56(FP)
    MOVQ    AX, errno+72(FP)
    RET
darwin_success:
    MOVQ    AX, r1+56(FP)
    MOVQ    $0, errno+72(FP)
    RET
```

## Part 2: Multi-Architecture CI

### Current State
- CI builds `GOARCH=amd64` only
- Tests fail on macOS because AMD64 binaries use raw SYSCALL

### Target State
- Build both AMD64 and ARM64 binaries
- Test each binary on appropriate platforms
- Eventually: merge into fat APE binary with `apelink`

### CI Changes (`.github/workflows/cosmo-ci.yml`)

Update build matrix to include both architectures:

```yaml
build:
  strategy:
    matrix:
      build-os: [ubuntu-latest, macos-latest, windows-latest]
      goarch: [amd64, arm64]
```

Build step:
```yaml
- name: Build APE binary
  shell: bash
  run: |
    export PATH="$PWD/bin:$PATH"
    GOOS=cosmo GOARCH=${{ matrix.goarch }} go build -o fizzbuzz-${{ matrix.goarch }}.com testdata/fizzbuzz/fizzbuzz.go
```

Test step - run appropriate binary per test platform:
- Ubuntu (x86_64): test amd64 binary
- macOS (ARM64): test arm64 binary
- Windows (x86_64): test amd64 binary

## Verification

```bash
just build && just test
```

Push and verify CI passes:
- AMD64 binary works on Linux and Windows
- AMD64 binary works on macOS x86_64 (after darwin routing)
- ARM64 binary works on macOS ARM64 (already has darwin routing)

## Implementation Order

1. Add `__hostos`/`__syslib` variables to `os_cosmo_amd64.go`
2. Update `rt0_cosmo_amd64.s` to capture APE loader values
3. Add CHECK_DARWIN to `sys_cosmo_amd64.s` for core syscalls (write, read, exit, mmap, etc.)
4. Add darwin dispatch to `asm_cosmo_amd64.s` Syscall6
5. Test locally on macOS x86_64 if available
6. Update CI to build both architectures
7. Push and verify CI

## Risk Assessment

- **Medium Risk**: x86_64 APE loader register conventions need verification
- **Mitigation**: Reference ARM64 implementation and Cosmopolitan source (ape.S, ape-m1.c)
