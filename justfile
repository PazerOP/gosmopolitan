# Build the Go toolchain
build:
    cd src && ./make.bash

# Build APE binary and run bats tests
test:
    #!/usr/bin/env bash
    set -euo pipefail
    git submodule update --init --recursive
    export PATH="$PWD/bin:$PATH"
    rm -f fizzbuzz.com
    GOOS=cosmo GOARCH=amd64 go build -o fizzbuzz.com testdata/fizzbuzz/fizzbuzz.go
    chmod +x fizzbuzz.com
    export FIZZBUZZ_BIN="$PWD/fizzbuzz.com"
    bats --print-output-on-failure testdata/fizzbuzz/fizzbuzz.bats
