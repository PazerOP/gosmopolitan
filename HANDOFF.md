# Handoff Documentation for Remote Claude

## Current State

The APE (Actually Portable Executable) implementation has been updated to match vim.com's proven approach. The code changes are complete, but a clean rebuild is needed.

## What Was Done

1. **APE shell script rewritten** (`src/cmd/link/internal/ld/ape.go`)
   - Now matches vim.com's approach: opens file r/w with `exec 7<> "$o"`, writes ELF header to file with `printf >&7`
   - macOS x86_64: uses dd to copy Mach-O header
   - ARM64: extracts ELF to temp and runs via Rosetta

2. **APE magic added to objectMagic** (`src/cmd/go/internal/work/exec.go`)
   - Added `{'M', 'Z', 'q', 'F', 'p', 'D'}` to the objectMagic array
   - This allows `go install` to recognize and overwrite APE files

3. **Test fix** (`testdata/ape/apetest/shell_test.go`)
   - Changed `assert.Contains` to `bytes.Contains` for byte slice comparison

## What Needs To Be Done

1. **Clean rebuild of toolchain**
   ```bash
   cd /Users/mhaynie/repos/gosmopolitan
   rm -rf bin pkg
   cd src && ./make.bash
   ```

2. **Build fizzbuzz test binary**
   ```bash
   make build-fizzbuzz
   ```

3. **Run tests**
   ```bash
   make test
   ```

4. **Expected outcome**: fizzbuzz.com should run on macOS (both x86_64 and ARM64 via Rosetta)

## Key Files

- `src/cmd/link/internal/ld/ape.go` - APE format generation (lines ~280-380 for shell script)
- `src/cmd/go/internal/work/exec.go` - objectMagic array (search for "APE")
- `testdata/ape/apetest/` - Test suite for APE validation
- `testdata/fizzbuzz/fizzbuzz.bats` - Integration tests

## Reference

vim.com at `/Users/mhaynie/Downloads/vim.com` is a working APE binary. You can examine its shell script with:
```bash
head -c 8192 /Users/mhaynie/Downloads/vim.com | strings
```

## Branch

Currently on `fix-ape-shell-fallback` branch.
