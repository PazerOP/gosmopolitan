#!/usr/bin/env bats

# Test suite for APE ELF structure verification

setup() {
    TESTDATA_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    load "$TESTDATA_DIR/test_helper/bats-support/load"
    load "$TESTDATA_DIR/test_helper/bats-assert/load"

    [[ -n "$FIZZBUZZ_BIN" ]] || { echo "ERROR: FIZZBUZZ_BIN not set"; return 1; }
    [[ -f "$FIZZBUZZ_BIN" ]] || { echo "ERROR: $FIZZBUZZ_BIN not found"; return 1; }
}

@test "elf: header structure is valid" {
    # Check magic
    run xxd -s 0x10000 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "7f454c46"  # \x7fELF

    # Check 64-bit
    run xxd -s 0x10004 -l 1 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "02"  # ELFCLASS64

    # Check little-endian
    run xxd -s 0x10005 -l 1 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "01"  # ELFDATA2LSB

    # Check executable type
    run xxd -s 0x10010 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "0200"  # ET_EXEC little-endian

    # Check x86-64
    run xxd -s 0x10012 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "3e00"  # EM_X86_64 little-endian
}

@test "elf: segments are valid" {
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -l "$ELF_BIN"
    assert_success
    assert_output --partial "0x0000000100000000"  # base address
    assert_output --partial "R E"  # executable segment

    rm -f "$ELF_BIN"
}

@test "elf: readelf -a parses successfully" {
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -a "$ELF_BIN"
    assert_success

    rm -f "$ELF_BIN"
}

# =============================================================================
# ELF Header Fields (per APE specification)
# =============================================================================

@test "elf: OS/ABI is ELFOSABI_FREEBSD (9)" {
    # Spec: OS ABI field SHOULD be set to ELFOSABI_FREEBSD
    # EI_OSABI is at offset 7 in ELF header
    run xxd -s $((0x10000 + 7)) -l 1 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "09"  # ELFOSABI_FREEBSD = 9
}

@test "elf: ELF version is 1 (EV_CURRENT)" {
    # EI_VERSION at offset 6
    run xxd -s $((0x10000 + 6)) -l 1 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "01"
}

@test "elf: e_version is 1" {
    # e_version at offset 20 (0x14) in Elf64_Ehdr
    run xxd -s $((0x10000 + 0x14)) -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "01000000"  # 1 in little-endian
}

@test "elf: e_ehsize is 64 bytes (Elf64_Ehdr size)" {
    # e_ehsize at offset 52 (0x34)
    run xxd -s $((0x10000 + 0x34)) -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "4000"  # 64 in little-endian
}

@test "elf: e_phentsize is 56 bytes (Elf64_Phdr size)" {
    # e_phentsize at offset 54 (0x36)
    run xxd -s $((0x10000 + 0x36)) -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "3800"  # 56 in little-endian
}

@test "elf: e_phnum is greater than 0" {
    # e_phnum at offset 56 (0x38)
    run xxd -s $((0x10000 + 0x38)) -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    phnum=$((16#${output:2:2}${output:0:2}))  # Convert little-endian
    assert [ "$phnum" -gt 0 ]
}

@test "elf: entry point is above 0x100000000 (4GB)" {
    # Spec: ARM64 loads at 0x000800000000, x86-64 at 0x100000000
    # e_entry at offset 24 (0x18)
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    entry=$("$READELF" -h "$ELF_BIN" | grep "Entry point" | grep -oE '0x[0-9a-fA-F]+')
    entry_dec=$((entry))

    # Should be >= 0x100000000 (4GB)
    run echo "$entry_dec"
    assert_success
    assert [ "$entry_dec" -ge 4294967296 ]

    rm -f "$ELF_BIN"
}

# =============================================================================
# Program Headers
# =============================================================================

@test "elf: has PT_LOAD segment" {
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -l "$ELF_BIN"
    assert_success
    assert_output --partial "LOAD"

    rm -f "$ELF_BIN"
}

@test "elf: has executable segment (R E)" {
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -l "$ELF_BIN"
    assert_success
    assert_output --partial "R E"

    rm -f "$ELF_BIN"
}

@test "elf: has read-only data segment (R)" {
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -l "$ELF_BIN"
    assert_success
    # Should have at least one read-only segment
    assert_output --regexp 'R   0x'

    rm -f "$ELF_BIN"
}

@test "elf: has read-write data segment (RW)" {
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -l "$ELF_BIN"
    assert_success
    assert_output --partial "RW"

    rm -f "$ELF_BIN"
}

@test "elf: no segment is both writable and executable (W+E)" {
    # Security: RWX segments are dangerous
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -l "$ELF_BIN"
    assert_success
    refute_output --partial "RWE"

    rm -f "$ELF_BIN"
}

# =============================================================================
# Alignment (per APE specification)
# =============================================================================

@test "elf: segment alignment is page-size compatible" {
    # Spec: file offsets congruent with virtual addresses mod page size
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -l "$ELF_BIN"
    assert_success
    # All LOAD segments should have alignment >= 0x1000 (4KB)
    assert_output --partial "0x1000"

    rm -f "$ELF_BIN"
}

# =============================================================================
# Symbols and Sections
# =============================================================================

@test "elf: has .text section" {
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -S "$ELF_BIN"
    assert_success
    assert_output --partial ".text"

    rm -f "$ELF_BIN"
}

@test "elf: has .rodata or .rdata section" {
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -S "$ELF_BIN"
    assert_success
    # Either .rodata or .rdata should exist
    [[ "$output" =~ \.rodata ]] || [[ "$output" =~ \.rdata ]]
}

@test "elf: has .data section" {
    ELF_BIN=$(mktemp)
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    run "$READELF" -S "$ELF_BIN"
    assert_success
    assert_output --partial ".data"

    rm -f "$ELF_BIN"
}
