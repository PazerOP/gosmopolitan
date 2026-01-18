# Default recipe to show available commands
default:
    @just --list

# Build the Go toolchain (Unix)
[unix]
build:
    cd src && ./make.bash

# Build the Go toolchain (Windows)
[windows]
build:
    cd src && cmd /c make.bat

# Build APE binary and run bats tests (Unix)
[unix]
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

# Build APE binary and run bats tests (Windows - requires Git Bash or WSL)
[windows]
test:
    git submodule update --init --recursive
    set PATH=%CD%\bin;%PATH% && set GOOS=cosmo && set GOARCH=amd64 && go build -o fizzbuzz.com testdata/fizzbuzz/fizzbuzz.go
    @echo Built fizzbuzz.com - run tests with: bash -c "FIZZBUZZ_BIN='%CD%/fizzbuzz.com' bats testdata/fizzbuzz/fizzbuzz.bats"

# Build and test in one step (Unix)
[unix]
all: build test

# Build and test in one step (Windows)
[windows]
all: build test

# Clean build artifacts
[unix]
clean:
    rm -f fizzbuzz.com
    rm -rf bin/

# Clean build artifacts (Windows)
[windows]
clean:
    if exist fizzbuzz.com del fizzbuzz.com
    if exist bin rmdir /s /q bin

# Build a specific Go program as APE binary (Unix)
[unix]
build-ape target output="output.com":
    #!/usr/bin/env bash
    set -euo pipefail
    export PATH="$PWD/bin:$PATH"
    GOOS=cosmo GOARCH=amd64 go build -o "{{output}}" "{{target}}"
    chmod +x "{{output}}"
    echo "Built {{output}}"

# Build a specific Go program as APE binary (Windows)
[windows]
build-ape target output="output.com":
    set PATH=%CD%\bin;%PATH% && set GOOS=cosmo && set GOARCH=amd64 && go build -o "{{output}}" "{{target}}"
    @echo Built {{output}}
