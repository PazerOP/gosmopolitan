set shell := ["bash", "-euo", "pipefail", "-c"]

# Required tools
export READELF := require("readelf")
export OTOOL := require("otool")
HOST_GO := require("go")

# Environment
export PATH := justfile_directory() / "bin:" + env("PATH")
export GOOS := "cosmo"
export GOARCH := "amd64"
export FIZZBUZZ_BIN_PRISTINE := justfile_directory() / "fizzbuzz.com"
export FIZZBUZZ_BIN := justfile_directory() / "fizzbuzz-test.com"
# Build the Go toolchain
build:
    cd src && ./make.bash

# Build APE binary and run tests (rebuilds toolchain if not on CI)
test: _maybe-build build-fizzbuzz
    cd testdata/ape/apetest && GOOS= GOARCH= GOROOT= {{HOST_GO}} test -v ./...
    bats --timing --print-output-on-failure testdata/fizzbuzz/fizzbuzz.bats

[private]
_maybe-build:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${CI:-}" ]; then
        just build
    fi

build-fizzbuzz:
    rm -f {{FIZZBUZZ_BIN_PRISTINE}}
    go build -o {{FIZZBUZZ_BIN_PRISTINE}} testdata/fizzbuzz/fizzbuzz.go
    chmod -x {{FIZZBUZZ_BIN_PRISTINE}}
    cp {{FIZZBUZZ_BIN_PRISTINE}} {{FIZZBUZZ_BIN}}
    chmod +x {{FIZZBUZZ_BIN}}
