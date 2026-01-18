# Plan: Fix APE Binary Execution on macOS and Windows

## Problem Summary

APE binaries built with `GOOS=cosmo GOARCH=amd64` work on Ubuntu but fail on macOS and Windows.

## CI Failure Analysis (from run 20958875671)

### Windows Failure
```
# expected : fizzbuzz
# actual   :
```
**Root cause**: Shell script's `case` statement doesn't handle `MINGW*` (Git Bash). Falls through to `exit 1` with no output.

### macOS Failure
```
# output : APE: Install APE loader: https://justine.lol/ape.html
```
**Root cause**: GitHub's `macos-latest` runner is ARM64 (macos-15-arm64). The shell script detects `uname -m` as `arm64` and requires APE loader. Per APE spec, ARM64 macOS has no shell-only fallback.

## Current State Analysis

### What Works
- **Linux**: Shell script extracts ELF via `tail -c +offset`, executes it
- **Ubuntu test runner**: Passes all 44 tests

### What's Broken

1. **Windows (Git Bash/MSYS)**: `uname -s` returns `MINGW64_NT-*` which isn't handled in the case statement. Shell falls through to `exit 1`.

2. **macOS ARM64**: The runner is ARM64 but binaries are AMD64. Per APE spec, ARM64 macOS requires APE loader - there's no shell-only fallback. This is a **CI configuration issue**, not an APE code issue.

3. **macOS x86-64**: Uses `dd` to transform APE into native Mach-O. Implementation looks correct per spec, but needs x86-64 runner to test.

## Proposed Fixes

### Fix 1: Windows Shell Support (ape.go)
**File**: `src/cmd/link/internal/ld/ape.go`

Add case for Windows shell environments. These can't execute ELF, but they CAN invoke cmd.exe which runs the APE as PE:

```sh
CYGWIN*|MINGW*|MSYS*)
  exec cmd //c "$o" "$@"
  ;;
```

The `//c` is Git Bash's way to pass `/c` to cmd.exe. This delegates to Windows' PE execution path.

### Fix 2: macOS ARM64 - Use Rosetta2 (ape.go)
**File**: `src/cmd/link/internal/ld/ape.go`

Goal: One binary runs everywhere without user prerequisites.

On ARM64 macOS, use the x86-64 Mach-O transformation path. Rosetta2 will automatically run the x86-64 code. Change the Darwin case:

```sh
Darwin*)
  # Use Mach-O transformation for both x86_64 and arm64
  # On arm64, Rosetta2 runs the x86_64 Mach-O
  dd if="$o" of="$o" bs=8 skip=512 count=36 conv=notrunc 2>/dev/null
  exec "$o" "$@"
  ;;
```

Remove the `uname -m` check entirely - just use Mach-O path for all Darwin.

### Fix 3: No CI changes needed
With the above fixes, existing CI should work:
- macOS ARM64 runner will use Rosetta2 to run x86-64 Mach-O
- No need to build ARM64 binaries or change runners

## Implementation Order

1. **Fix Windows** (ape.go) - Add CYGWIN/MINGW/MSYS case with `cmd //c`
2. **Fix macOS** (ape.go) - Simplify Darwin case to use Mach-O for all architectures
3. **Verify** - Push and check CI passes

## Files to Modify

1. `src/cmd/link/internal/ld/ape.go` - Lines 219-264 (shell script generation)
   - Add Windows shell case after FreeBSD case
   - Simplify Darwin case to remove uname -m check

## Verification

After pushing fixes:
1. CI should pass on all platforms
2. Windows: Tests should produce correct fizzbuzz output via PE path
3. macOS: Tests should work via Mach-O transformation + Rosetta2 on ARM64
