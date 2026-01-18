# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Don't Ask Stupid Questions

When there's a specification, **follow the specification**. Never ask "should I follow the spec or do something different?" - the answer is always follow the spec. That's what specs are for. If the implementation doesn't match the spec, fix the implementation.

## Project Overview

This is a fork of the Go programming language toolchain that adds support for **Cosmopolitan Libc** (`GOOS=cosmo`). Cosmopolitan enables building "Actually Portable Executables" (APE) - single binaries that run natively on Linux, macOS, and Windows without modification.

## Build Commands

Build from the `src/` directory. Requires a Go 1.24+ bootstrap toolchain (set `GOROOT_BOOTSTRAP` or have `go` in PATH).

```bash
# Build the toolchain (Unix)
cd src && ./make.bash

# Build the toolchain (Windows)
cd src && make.bat

# Build and run all tests
cd src && ./all.bash

# Run tests only (after build)
cd src && ./run.bash
```

## Testing

```bash
# Run all tests in test/ directory
go test cmd/internal/testdir

# Run specific test files
go test cmd/internal/testdir -run='Test/(file1.go|file2.go)'

# Run compiler package tests
go test ./cmd/compile/...

# Run standard library tests
go test std
```

## Building Cosmopolitan Binaries

```bash
# Build an APE binary
GOOS=cosmo GOARCH=amd64 go build -o program.com main.go
```

The resulting `.com` file runs on Linux, macOS, and Windows.

## Architecture

### Compiler Pipeline (`src/cmd/compile/`)

The compiler has 7 phases:
1. **Parsing** (`internal/syntax`) - lexer, parser, syntax tree
2. **Type checking** (`internal/types2`) - type analysis
3. **IR construction** (`internal/ir`, `internal/noder`) - convert to compiler AST
4. **Middle end** (`internal/inline`, `internal/escape`) - inlining, escape analysis
5. **Walk** (`internal/walk`) - desugar high-level constructs
6. **SSA** (`internal/ssa`, `internal/ssagen`) - optimization passes
7. **Code generation** (`cmd/internal/obj`) - machine code output

### Cosmopolitan-Specific Code

Runtime support for `GOOS=cosmo` is in `src/runtime/`:
- `os_cosmo.go` - main OS interface (thread creation, signals)
- `mem_cosmo.go` - memory management
- `netpoll_cosmo.go` - network polling
- `signal_cosmo_amd64.go` - signal handling
- `defs_cosmo_amd64.go` - system constants

Syscall layer: `src/internal/runtime/syscall/cosmo/`

### Key Directories

- `src/cmd/` - toolchain commands (compile, link, go, etc.)
- `src/runtime/` - Go runtime implementation
- `src/` - standard library packages
- `test/` - compiler and runtime test suite

## Debugging Tips

```bash
# View optimization info (inlining, escape analysis)
go build -gcflags=-m=2

# Generate SSA visualization for a function
GOSSAFUNC=FunctionName go build

# Print assembly output
go build -gcflags=-S

# Compiler timing
go tool compile -bench=out.txt file.go
```

## CI

The GitHub Actions workflow (`.github/workflows/cosmo-ci.yml`) builds the toolchain and tests that APE binaries built on any platform (Linux/macOS/Windows) run correctly on all other platforms.
