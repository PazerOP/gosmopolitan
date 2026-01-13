#!/usr/bin/env bats

# Test suite for fizzbuzz APE binary
# The binary takes two numbers, adds them, and outputs:
#   "fizzbuzz" if sum is divisible by 15
#   "fizz" if sum is divisible by 3
#   "buzz" if sum is divisible by 5
#   the sum itself otherwise

# FIZZBUZZ_BIN should be set to the path of the binary being tested

setup() {
    if [[ -z "$FIZZBUZZ_BIN" ]]; then
        echo "ERROR: FIZZBUZZ_BIN environment variable must be set"
        return 1
    fi
    if [[ ! -x "$FIZZBUZZ_BIN" ]]; then
        echo "ERROR: $FIZZBUZZ_BIN is not executable"
        return 1
    fi
}

# ============================================
# FizzBuzz tests (divisible by both 3 and 5)
# ============================================

@test "fizzbuzz: 10 + 5 = 15 (divisible by 15)" {
    run "$FIZZBUZZ_BIN" 10 5
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizzbuzz" ]
}

@test "fizzbuzz: 15 + 15 = 30 (divisible by 15)" {
    run "$FIZZBUZZ_BIN" 15 15
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizzbuzz" ]
}

@test "fizzbuzz: 0 + 0 = 0 (zero is divisible by 15)" {
    run "$FIZZBUZZ_BIN" 0 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizzbuzz" ]
}

@test "fizzbuzz: 45 + 0 = 45 (divisible by 15)" {
    run "$FIZZBUZZ_BIN" 45 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizzbuzz" ]
}

@test "fizzbuzz: -15 + 0 = -15 (negative divisible by 15)" {
    run "$FIZZBUZZ_BIN" -15 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizzbuzz" ]
}

@test "fizzbuzz: -10 + -5 = -15 (negative sum divisible by 15)" {
    run "$FIZZBUZZ_BIN" -10 -5
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizzbuzz" ]
}

# ============================================
# Fizz tests (divisible by 3, not by 5)
# ============================================

@test "fizz: 2 + 1 = 3 (divisible by 3)" {
    run "$FIZZBUZZ_BIN" 2 1
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizz" ]
}

@test "fizz: 3 + 3 = 6 (divisible by 3)" {
    run "$FIZZBUZZ_BIN" 3 3
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizz" ]
}

@test "fizz: 5 + 4 = 9 (divisible by 3)" {
    run "$FIZZBUZZ_BIN" 5 4
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizz" ]
}

@test "fizz: 10 + 2 = 12 (divisible by 3, not 5)" {
    run "$FIZZBUZZ_BIN" 10 2
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizz" ]
}

@test "fizz: -3 + 0 = -3 (negative divisible by 3)" {
    run "$FIZZBUZZ_BIN" -3 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizz" ]
}

@test "fizz: -6 + 0 = -6 (negative divisible by 3)" {
    run "$FIZZBUZZ_BIN" -6 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizz" ]
}

# ============================================
# Buzz tests (divisible by 5, not by 3)
# ============================================

@test "buzz: 3 + 2 = 5 (divisible by 5)" {
    run "$FIZZBUZZ_BIN" 3 2
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "buzz" ]
}

@test "buzz: 5 + 5 = 10 (divisible by 5)" {
    run "$FIZZBUZZ_BIN" 5 5
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "buzz" ]
}

@test "buzz: 10 + 10 = 20 (divisible by 5, not 3)" {
    run "$FIZZBUZZ_BIN" 10 10
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "buzz" ]
}

@test "buzz: 20 + 5 = 25 (divisible by 5, not 3)" {
    run "$FIZZBUZZ_BIN" 20 5
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "buzz" ]
}

@test "buzz: -5 + 0 = -5 (negative divisible by 5)" {
    run "$FIZZBUZZ_BIN" -5 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "buzz" ]
}

@test "buzz: -10 + 0 = -10 (negative divisible by 5)" {
    run "$FIZZBUZZ_BIN" -10 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "buzz" ]
}

# ============================================
# Number tests (not divisible by 3 or 5)
# ============================================

@test "number: 1 + 0 = 1" {
    run "$FIZZBUZZ_BIN" 1 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "number: 1 + 1 = 2" {
    run "$FIZZBUZZ_BIN" 1 1
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "number: 2 + 2 = 4" {
    run "$FIZZBUZZ_BIN" 2 2
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "4" ]
}

@test "number: 3 + 4 = 7" {
    run "$FIZZBUZZ_BIN" 3 4
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "7" ]
}

@test "number: 4 + 4 = 8" {
    run "$FIZZBUZZ_BIN" 4 4
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "8" ]
}

@test "number: 5 + 6 = 11" {
    run "$FIZZBUZZ_BIN" 5 6
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "11" ]
}

@test "number: 7 + 6 = 13" {
    run "$FIZZBUZZ_BIN" 7 6
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "13" ]
}

@test "number: -1 + 0 = -1 (negative)" {
    run "$FIZZBUZZ_BIN" -1 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "-1" ]
}

@test "number: -2 + 0 = -2 (negative)" {
    run "$FIZZBUZZ_BIN" -2 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "-2" ]
}

@test "number: -4 + 0 = -4 (negative)" {
    run "$FIZZBUZZ_BIN" -4 0
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "-4" ]
}

# ============================================
# Large number tests
# ============================================

@test "large number: 500 + 500 = 1000 (buzz)" {
    run "$FIZZBUZZ_BIN" 500 500
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "buzz" ]
}

@test "large number: 501 + 498 = 999 (fizz)" {
    run "$FIZZBUZZ_BIN" 501 498
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizz" ]
}

@test "large number: 500 + 505 = 1005 (fizzbuzz)" {
    run "$FIZZBUZZ_BIN" 500 505
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizzbuzz" ]
}

@test "large number: 12345 + 6789 = 19134 (fizz)" {
    run "$FIZZBUZZ_BIN" 12345 6789
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizz" ]
}

# ============================================
# Mixed sign tests
# ============================================

@test "mixed signs: 10 + -7 = 3 (fizz)" {
    run "$FIZZBUZZ_BIN" 10 -7
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizz" ]
}

@test "mixed signs: -10 + 15 = 5 (buzz)" {
    run "$FIZZBUZZ_BIN" -10 15
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "buzz" ]
}

@test "mixed signs: 20 + -5 = 15 (fizzbuzz)" {
    run "$FIZZBUZZ_BIN" 20 -5
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "fizzbuzz" ]
}

@test "mixed signs: -8 + 10 = 2 (number)" {
    run "$FIZZBUZZ_BIN" -8 10
    echo "Output: $output"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

# ============================================
# Error handling tests
# ============================================

@test "error: no arguments" {
    run "$FIZZBUZZ_BIN"
    echo "Output: $output"
    echo "Status: $status"
    [ "$status" -ne 0 ]
}

@test "error: only one argument" {
    run "$FIZZBUZZ_BIN" 5
    echo "Output: $output"
    echo "Status: $status"
    [ "$status" -ne 0 ]
}

@test "error: too many arguments" {
    run "$FIZZBUZZ_BIN" 1 2 3
    echo "Output: $output"
    echo "Status: $status"
    [ "$status" -ne 0 ]
}

@test "error: first argument is not a number" {
    run "$FIZZBUZZ_BIN" abc 5
    echo "Output: $output"
    echo "Status: $status"
    [ "$status" -ne 0 ]
}

@test "error: second argument is not a number" {
    run "$FIZZBUZZ_BIN" 5 xyz
    echo "Output: $output"
    echo "Status: $status"
    [ "$status" -ne 0 ]
}

@test "error: both arguments are not numbers" {
    run "$FIZZBUZZ_BIN" foo bar
    echo "Output: $output"
    echo "Status: $status"
    [ "$status" -ne 0 ]
}

@test "error: floating point first argument" {
    run "$FIZZBUZZ_BIN" 3.14 5
    echo "Output: $output"
    echo "Status: $status"
    [ "$status" -ne 0 ]
}

@test "error: floating point second argument" {
    run "$FIZZBUZZ_BIN" 5 2.71
    echo "Output: $output"
    echo "Status: $status"
    [ "$status" -ne 0 ]
}
