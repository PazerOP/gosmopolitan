#!/usr/bin/env bats

# Test suite for APE shell script header verification
# Based on ape/specification.md from Cosmopolitan

setup() {
    TESTDATA_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    load "$TESTDATA_DIR/test_helper/bats-support/load"
    load "$TESTDATA_DIR/test_helper/bats-assert/load"

    [[ -n "$FIZZBUZZ_BIN" ]] || { echo "ERROR: FIZZBUZZ_BIN not set"; return 1; }
    [[ -f "$FIZZBUZZ_BIN" ]] || { echo "ERROR: $FIZZBUZZ_BIN not found"; return 1; }
}

# =============================================================================
# APE Magic Tests
# =============================================================================

@test "shell: starts with MZ magic (MZqFpD=')" {
    # MZqFpD=' = 4d 5a 71 46 70 44 3d 27
    run xxd -l 8 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "4d5a714670443d27"
}

@test "shell: magic followed by newline (0x0a) for shell binary safety" {
    # Spec: magic should be immediately followed by newline
    # FreeBSD SH and Zsh impose binary safety check on first line
    run xxd -s 8 -l 1 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "0a"
}

@test "shell: first line contains no NUL bytes before newline" {
    # Read first 64 bytes, find newline position
    first_64=$(xxd -l 64 -p "$FIZZBUZZ_BIN" | tr -d '\n')

    # Find position of first 0a (newline)
    before_newline=${first_64%%0a*}

    # Should not contain 00 (NUL)
    run echo "$before_newline"
    assert_success
    refute_output --partial "00"
}

# =============================================================================
# Embedded ELF Header (printf statement) Tests
# =============================================================================

@test "shell: contains printf statement in first 8192 bytes" {
    # Spec: printf statement MUST appear in first 8192 bytes
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep -c \"printf '\""
    assert_success
    # At least one printf statement
    assert [ "$output" -ge 1 ]
}

@test "shell: printf contains ELF magic (\\177ELF)" {
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep -o \"printf '.*\\\\\\\\177ELF\" | head -1"
    assert_success
    assert_output --partial "\\177ELF"
}

@test "shell: printf contains 64-bit ELF marker (\\2)" {
    # After \177ELF, \2 = ELFCLASS64
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep -o \"printf '.*\\\\\\\\177ELF\\\\\\\\2\" | head -1"
    assert_success
    assert_output --partial "\\177ELF\\2"
}

@test "shell: printf contains little-endian marker (\\1)" {
    # \177ELF\2\1 = 64-bit little-endian
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep -o \"printf '.*\\\\\\\\177ELF\\\\\\\\2\\\\\\\\1\" | head -1"
    assert_success
    assert_output --partial "\\177ELF\\2\\1"
}

@test "shell: printf uses only octal escapes (not \\n, \\t shortcuts)" {
    # Spec: MUST NOT use space saving escape codes such as \n
    header=$(dd if="$FIZZBUZZ_BIN" bs=8192 count=1 2>/dev/null)
    printf_line=$(echo "$header" | grep "printf '" | head -1)

    # Should not contain \n, \t, \r, \b, \f, \v, \a (only \NNN octal)
    run echo "$printf_line"
    assert_success
    refute_output --regexp '\\[ntrbfva]'
}

# =============================================================================
# dd Statement Tests (Mach-O x86-64)
# =============================================================================

@test "shell: contains dd statement for Mach-O relocation" {
    # Spec: dd if="\$o" of="\$o" bs=... skip=... count=... conv=notrunc
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep 'dd.*bs=.*skip=.*count=.*conv=notrunc'"
    assert_success
}

@test "shell: dd bs parameter is 8 (standard block size)" {
    dd_line=$(dd if="$FIZZBUZZ_BIN" bs=8192 count=1 2>/dev/null | grep 'dd.*conv=notrunc' | head -1)
    bs=$(echo "$dd_line" | grep -oE 'bs=[0-9]+' | grep -oE '[0-9]+')

    run echo "$bs"
    assert_success
    assert_output "8"
}

@test "shell: dd skip parameter is positive integer" {
    dd_line=$(dd if="$FIZZBUZZ_BIN" bs=8192 count=1 2>/dev/null | grep 'dd.*conv=notrunc' | head -1)
    skip=$(echo "$dd_line" | grep -oE 'skip=[0-9]+' | grep -oE '[0-9]+')

    run echo "$skip"
    assert_success
    assert [ "$skip" -gt 0 ]
}

@test "shell: dd count parameter is positive integer" {
    dd_line=$(dd if="$FIZZBUZZ_BIN" bs=8192 count=1 2>/dev/null | grep 'dd.*conv=notrunc' | head -1)
    count=$(echo "$dd_line" | grep -oE 'count=[0-9]+' | grep -oE '[0-9]+')

    run echo "$count"
    assert_success
    assert [ "$count" -gt 0 ]
}

@test "shell: Mach-O header at dd offset has MH_MAGIC_64" {
    dd_line=$(dd if="$FIZZBUZZ_BIN" bs=8192 count=1 2>/dev/null | grep 'dd.*conv=notrunc' | head -1)
    bs=$(echo "$dd_line" | grep -oE 'bs=[0-9]+' | grep -oE '[0-9]+')
    skip=$(echo "$dd_line" | grep -oE 'skip=[0-9]+' | grep -oE '[0-9]+')
    offset=$((skip * bs))

    # MH_MAGIC_64 = 0xFEEDFACF (little-endian: cf fa ed fe)
    run xxd -s "$offset" -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "cffaedfe"
}

# =============================================================================
# Architecture Detection Tests
# =============================================================================

@test "shell: contains uname -m for architecture detection" {
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep 'uname -m'"
    assert_success
}

@test "shell: handles x86_64 architecture name" {
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep 'x86_64'"
    assert_success
}

@test "shell: handles amd64 architecture name" {
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep 'amd64'"
    assert_success
}

# =============================================================================
# OS Detection Tests
# =============================================================================

@test "shell: detects macOS via /Applications directory check" {
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep '/Applications'"
    assert_success
}

# =============================================================================
# Self-Modification / Loader Tests
# =============================================================================

@test "shell: uses exec for re-execution after transformation" {
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep -E 'exec \"\\\$'"
    assert_success
}

@test "shell: references TMPDIR or .ape for loader cache" {
    run bash -c "dd if='$FIZZBUZZ_BIN' bs=8192 count=1 2>/dev/null | grep -E 'TMPDIR|\\.ape'"
    assert_success
}

# =============================================================================
# Shell Script Validity Tests
# =============================================================================

@test "shell: variable assignment ends with single quote" {
    # MZqFpD=' - the = and ' start a string assignment
    run xxd -s 6 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "3d27"  # ='
}

@test "shell: closing quote exists before shell commands" {
    # The binary payload must be closed with ' before shell commands begin
    header=$(dd if="$FIZZBUZZ_BIN" bs=4096 count=1 2>/dev/null)

    # Should have a closing quote followed by newline somewhere
    run bash -c "echo '$header' | grep -c \"^'\""
    assert_success
    assert [ "$output" -ge 1 ]
}
