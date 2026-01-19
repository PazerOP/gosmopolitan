# Plan: ARM64 Darwin Syscall Routing Through Syslib

## Problem Statement

The `Syscall6` function in `src/internal/runtime/syscall/cosmo/asm_cosmo_arm64.s` always uses raw SVC instructions. On darwin ARM64, this crashes with SIGSYS because macOS doesn't allow raw syscalls - they must go through Apple's frameworks.

**Symptom**: Programs using `fmt.Println()` or `os.Stdout.Write()` crash silently on macOS ARM64 because they use the syscall package which calls `Syscall6`.

## Current Architecture

### What Works (runtime syscalls)
`src/runtime/sys_cosmo_arm64.s` already implements dual-path routing:
```asm
#define CHECK_DARWIN(label) \
    MOVW    runtime·__hostos(SB), R9; \
    CMPW    $HOSTXNU, R9; \
    BEQ     label

TEXT runtime·write(SB),NOSPLIT,$0
    CHECK_DARWIN(write_darwin)
    // Linux: SVC
    SVC
    RET
write_darwin:
    // Darwin: call syslib function
    MOVD    runtime·__syslib(SB), R9
    MOVD    256(R9), R12    // write at offset 256
    BL      (R12)
    RET
```

### What's Broken (syscall package)
`src/internal/runtime/syscall/cosmo/asm_cosmo_arm64.s`:
```asm
TEXT ·Syscall6(SB),NOSPLIT,$0-80
    MOVD    num+0(FP), R8
    // ...load args...
    SVC                     // <-- CRASHES ON DARWIN!
```

## Solution Design

### Approach: Syscall Number → Syslib Dispatch Table

Modify `Syscall6` to:
1. Check `runtime·__hostos` for darwin
2. On Linux: use raw SVC (current behavior)
3. On Darwin: look up syscall number in a dispatch table, call the corresponding syslib function

### Syscall Mapping Table

| Syscall | Linux ARM64 Number | Syslib Offset |
|---------|-------------------|---------------|
| write | 64 | 256 |
| read | 63 | 264 |
| openat | 56 | 248 |
| close | 57 | 232 |
| mmap | 222 | 40 |
| munmap | 215 | 240 |
| mprotect | 226 | 288 |
| exit | 93 | 224 |
| nanosleep | 101 | 32 |
| clock_gettime | 113 | 24 |
| sigaction | 134 | 272 |
| sigaltstack | 132 | 296 |
| pselect6 | 72 | 280 |

### Implementation Strategy

**Option A: Jump Table (Complex)**
- Create a lookup table mapping syscall numbers to syslib offsets
- Requires bounds checking and indirect jumps
- More complex but handles all syscalls

**Option B: Switch Statement (Simpler)**
- Handle known syscalls with direct comparisons
- Fall back to returning ENOSYS for unknown syscalls
- Simpler, easier to debug

**Recommended: Option B** - Start with explicit handling of the most critical syscalls (write, read, close, openat, mmap, munmap, mprotect, exit) and return ENOSYS for others. Can expand as needed.

## Files to Modify

1. **`src/internal/runtime/syscall/cosmo/asm_cosmo_arm64.s`**
   - Add darwin detection using `CHECK_DARWIN` pattern
   - Add switch/dispatch for known syscalls on darwin
   - Call syslib functions with proper C ABI (stack alignment)

2. **`src/internal/runtime/syscall/cosmo/defs_cosmo_arm64.go`** (may need to create)
   - Define syslib offset constants for clarity

## Implementation Steps

### Step 1: Add Darwin Detection
```asm
#define HOSTXNU $8

#define CHECK_DARWIN(label) \
    MOVW    runtime·__hostos(SB), R9; \
    CMPW    HOSTXNU, R9; \
    BEQ     label
```

### Step 2: Modify Syscall6 Entry
```asm
TEXT ·Syscall6(SB),NOSPLIT,$0-80
    CHECK_DARWIN(syscall6_darwin)
    // Linux path (existing code)
    MOVD    num+0(FP), R8
    MOVD    a1+8(FP), R0
    // ...
    SVC
    // ...
    RET

syscall6_darwin:
    // Darwin dispatch - see Step 3
```

### Step 3: Darwin Syscall Dispatch
```asm
syscall6_darwin:
    MOVD    num+0(FP), R8           // syscall number
    MOVD    runtime·__syslib(SB), R10

    // Load arguments for C call
    MOVD    a1+8(FP), R0
    MOVD    a2+16(FP), R1
    MOVD    a3+24(FP), R2
    MOVD    a4+32(FP), R3
    MOVD    a5+40(FP), R4
    MOVD    a6+48(FP), R5

    // Dispatch based on syscall number
    CMPW    $64, R8                 // SYS_write
    BEQ     darwin_write
    CMPW    $63, R8                 // SYS_read
    BEQ     darwin_read
    CMPW    $57, R8                 // SYS_close
    BEQ     darwin_close
    CMPW    $56, R8                 // SYS_openat
    BEQ     darwin_openat
    // ... more syscalls ...

    // Unknown syscall - return ENOSYS
    MOVD    $-38, R0                // -ENOSYS
    MOVD    R0, r1+56(FP)
    MOVD    $38, R0                 // ENOSYS
    MOVD    R0, errno+72(FP)
    RET

darwin_write:
    MOVD    256(R10), R12           // syslib.write offset
    B       darwin_call
darwin_read:
    MOVD    264(R10), R12           // syslib.read offset
    B       darwin_call
// ... etc ...

darwin_call:
    SUB     $16, RSP                // Align stack for C ABI
    BL      (R12)
    ADD     $16, RSP
    // Handle return value (R0 = result, negative = error)
    CMP     $0, R0
    BGE     darwin_success
    NEG     R0, R0                  // Make errno positive
    MOVD    $-1, R1
    MOVD    R1, r1+56(FP)
    MOVD    R0, errno+72(FP)
    RET
darwin_success:
    MOVD    R0, r1+56(FP)
    MOVD    $0, R1
    MOVD    R1, errno+72(FP)
    RET
```

## Verification

```bash
just build && just test
```

Push and verify CI passes on all platforms.

## Risk Assessment

- **Low Risk**: Linux path unchanged, just adds darwin branch
- **Medium Risk**: Need to ensure all critical syscalls are mapped
- **Mitigation**: Unknown syscalls return ENOSYS with clear error, not crash

## Future Enhancements

- Add more syscalls to the dispatch table as needed
- Consider generating the dispatch table from syslib struct definition
- Add fcntl, ioctl, and other complex syscalls
