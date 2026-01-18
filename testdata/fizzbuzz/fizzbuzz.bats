#!/usr/bin/env bats

# Test suite for fizzbuzz APE binary
# The binary takes two numbers, adds them, and outputs:
#   "fizzbuzz" if sum is divisible by 15
#   "fizz" if sum is divisible by 3
#   "buzz" if sum is divisible by 5
#   the sum itself otherwise

# Load bats-assert for proper assertions with clear failure output
setup() {
    TESTDATA_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    load "$TESTDATA_DIR/test_helper/bats-support/load"
    load "$TESTDATA_DIR/test_helper/bats-assert/load"

    # Validate FIZZBUZZ_BIN is set
    if [[ -z "$FIZZBUZZ_BIN" ]]; then
        echo "ERROR: FIZZBUZZ_BIN environment variable must be set"
        return 1
    fi
    if [[ ! -x "$FIZZBUZZ_BIN" ]]; then
        echo "ERROR: $FIZZBUZZ_BIN is not executable"
        return 1
    fi

    # Detect OS and set the native shell for running the binary
    case "$(uname -s)" in
        Linux*)  NATIVE_SHELL="bash" ;;
        Darwin*) NATIVE_SHELL="zsh" ;;
        CYGWIN*|MINGW*|MSYS*) NATIVE_SHELL="cmd" ;;
        *)       NATIVE_SHELL="bash" ;;
    esac
    export NATIVE_SHELL
}

# Run the fizzbuzz binary through the native shell
# This ensures we test the APE binary execution path for each platform:
#   - Linux: bash (shell script fallback)
#   - macOS: zsh (shell script fallback)
#   - Windows: cmd (PE execution path)
# Note: APE modifies itself on macOS, so we copy to temp each time
run_fizzbuzz() {
    local tmp=$(mktemp)
    cp "$FIZZBUZZ_BIN" "$tmp"
    chmod +x "$tmp"
    if [[ "$NATIVE_SHELL" == "cmd" ]]; then
        run cmd //c "$tmp $*"
    else
        run "$NATIVE_SHELL" -c "\"$tmp\" $*"
    fi
    rm -f "$tmp"
}

# ============================================
# FizzBuzz tests (divisible by both 3 and 5)
# ============================================

@test "fizzbuzz: 10 + 5 = 15 (divisible by 15)" {
    run_fizzbuzz 10 5
    assert_success
    assert_output "fizzbuzz"
}

@test "fizzbuzz: 15 + 15 = 30 (divisible by 15)" {
    run_fizzbuzz 15 15
    assert_success
    assert_output "fizzbuzz"
}

@test "fizzbuzz: 0 + 0 = 0 (zero is divisible by 15)" {
    run_fizzbuzz 0 0
    assert_success
    assert_output "fizzbuzz"
}

@test "fizzbuzz: 45 + 0 = 45 (divisible by 15)" {
    run_fizzbuzz 45 0
    assert_success
    assert_output "fizzbuzz"
}

@test "fizzbuzz: -15 + 0 = -15 (negative divisible by 15)" {
    run_fizzbuzz -15 0
    assert_success
    assert_output "fizzbuzz"
}

@test "fizzbuzz: -10 + -5 = -15 (negative sum divisible by 15)" {
    run_fizzbuzz -10 -5
    assert_success
    assert_output "fizzbuzz"
}

# ============================================
# Fizz tests (divisible by 3, not by 5)
# ============================================

@test "fizz: 2 + 1 = 3 (divisible by 3)" {
    run_fizzbuzz 2 1
    assert_success
    assert_output "fizz"
}

@test "fizz: 3 + 3 = 6 (divisible by 3)" {
    run_fizzbuzz 3 3
    assert_success
    assert_output "fizz"
}

@test "fizz: 5 + 4 = 9 (divisible by 3)" {
    run_fizzbuzz 5 4
    assert_success
    assert_output "fizz"
}

@test "fizz: 10 + 2 = 12 (divisible by 3, not 5)" {
    run_fizzbuzz 10 2
    assert_success
    assert_output "fizz"
}

@test "fizz: -3 + 0 = -3 (negative divisible by 3)" {
    run_fizzbuzz -3 0
    assert_success
    assert_output "fizz"
}

@test "fizz: -6 + 0 = -6 (negative divisible by 3)" {
    run_fizzbuzz -6 0
    assert_success
    assert_output "fizz"
}

# ============================================
# Buzz tests (divisible by 5, not by 3)
# ============================================

@test "buzz: 3 + 2 = 5 (divisible by 5)" {
    run_fizzbuzz 3 2
    assert_success
    assert_output "buzz"
}

@test "buzz: 5 + 5 = 10 (divisible by 5)" {
    run_fizzbuzz 5 5
    assert_success
    assert_output "buzz"
}

@test "buzz: 10 + 10 = 20 (divisible by 5, not 3)" {
    run_fizzbuzz 10 10
    assert_success
    assert_output "buzz"
}

@test "buzz: 20 + 5 = 25 (divisible by 5, not 3)" {
    run_fizzbuzz 20 5
    assert_success
    assert_output "buzz"
}

@test "buzz: -5 + 0 = -5 (negative divisible by 5)" {
    run_fizzbuzz -5 0
    assert_success
    assert_output "buzz"
}

@test "buzz: -10 + 0 = -10 (negative divisible by 5)" {
    run_fizzbuzz -10 0
    assert_success
    assert_output "buzz"
}

# ============================================
# Number tests (not divisible by 3 or 5)
# ============================================

@test "number: 1 + 0 = 1" {
    run_fizzbuzz 1 0
    assert_success
    assert_output "1"
}

@test "number: 1 + 1 = 2" {
    run_fizzbuzz 1 1
    assert_success
    assert_output "2"
}

@test "number: 2 + 2 = 4" {
    run_fizzbuzz 2 2
    assert_success
    assert_output "4"
}

@test "number: 3 + 4 = 7" {
    run_fizzbuzz 3 4
    assert_success
    assert_output "7"
}

@test "number: 4 + 4 = 8" {
    run_fizzbuzz 4 4
    assert_success
    assert_output "8"
}

@test "number: 5 + 6 = 11" {
    run_fizzbuzz 5 6
    assert_success
    assert_output "11"
}

@test "number: 7 + 6 = 13" {
    run_fizzbuzz 7 6
    assert_success
    assert_output "13"
}

@test "number: -1 + 0 = -1 (negative)" {
    run_fizzbuzz -1 0
    assert_success
    assert_output -- "-1"
}

@test "number: -2 + 0 = -2 (negative)" {
    run_fizzbuzz -2 0
    assert_success
    assert_output -- "-2"
}

@test "number: -4 + 0 = -4 (negative)" {
    run_fizzbuzz -4 0
    assert_success
    assert_output -- "-4"
}

# ============================================
# Large number tests
# ============================================

@test "large number: 500 + 500 = 1000 (buzz)" {
    run_fizzbuzz 500 500
    assert_success
    assert_output "buzz"
}

@test "large number: 501 + 498 = 999 (fizz)" {
    run_fizzbuzz 501 498
    assert_success
    assert_output "fizz"
}

@test "large number: 500 + 505 = 1005 (fizzbuzz)" {
    run_fizzbuzz 500 505
    assert_success
    assert_output "fizzbuzz"
}

@test "large number: 12345 + 6789 = 19134 (fizz)" {
    run_fizzbuzz 12345 6789
    assert_success
    assert_output "fizz"
}

# ============================================
# Mixed sign tests
# ============================================

@test "mixed signs: 10 + -7 = 3 (fizz)" {
    run_fizzbuzz 10 -7
    assert_success
    assert_output "fizz"
}

@test "mixed signs: -10 + 15 = 5 (buzz)" {
    run_fizzbuzz -10 15
    assert_success
    assert_output "buzz"
}

@test "mixed signs: 20 + -5 = 15 (fizzbuzz)" {
    run_fizzbuzz 20 -5
    assert_success
    assert_output "fizzbuzz"
}

@test "mixed signs: -8 + 10 = 2 (number)" {
    run_fizzbuzz -8 10
    assert_success
    assert_output "2"
}

# ============================================
# Error handling tests
# ============================================

@test "error: no arguments" {
    run_fizzbuzz
    assert_failure
    assert_output --partial "Usage:"
}

@test "error: only one argument" {
    run_fizzbuzz 5
    assert_failure
    assert_output --partial "Usage:"
}

@test "error: too many arguments" {
    run_fizzbuzz 1 2 3
    assert_failure
    assert_output --partial "Usage:"
}

@test "error: first argument is not a number" {
    run_fizzbuzz abc 5
    assert_failure
    assert_output --partial "Invalid first argument"
}

@test "error: second argument is not a number" {
    run_fizzbuzz 5 xyz
    assert_failure
    assert_output --partial "Invalid second argument"
}

@test "error: both arguments are not numbers" {
    run_fizzbuzz foo bar
    assert_failure
    assert_output --partial "Invalid"
}

@test "error: floating point first argument" {
    run_fizzbuzz 3.14 5
    assert_failure
    assert_output --partial "Invalid first argument"
}

@test "error: floating point second argument" {
    run_fizzbuzz 5 2.71
    assert_failure
    assert_output --partial "Invalid second argument"
}
