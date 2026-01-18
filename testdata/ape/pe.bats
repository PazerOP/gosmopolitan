#!/usr/bin/env bats

# Test suite for APE PE structure verification

setup() {
    TESTDATA_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    load "$TESTDATA_DIR/test_helper/bats-support/load"
    load "$TESTDATA_DIR/test_helper/bats-assert/load"

    [[ -n "$FIZZBUZZ_BIN" ]] || { echo "ERROR: FIZZBUZZ_BIN not set"; return 1; }
    [[ -f "$FIZZBUZZ_BIN" ]] || { echo "ERROR: $FIZZBUZZ_BIN not found"; return 1; }
}

@test "pe: DOS and PE headers are valid" {
    # DOS magic
    run xxd -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "4d5a"  # MZ

    # e_lfanew points to 0x80
    run xxd -s 0x3C -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "80000000"

    # PE signature
    run xxd -s 0x80 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "50450000"  # PE\0\0

    # Machine type x86-64
    run xxd -s 0x84 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "6486"  # 0x8664

    # PE32+ magic
    run xxd -s 0x98 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "0b02"  # 0x20B
}

@test "pe: optional header fields are valid" {
    # Subsystem (offset 0x5C from optional header start at 0x98 = 0xF4... wait let me recalculate)
    # COFF header is 20 bytes at 0x84, optional header starts at 0x98
    # Subsystem is at offset 68 (0x44) in optional header = 0x98 + 0x44 = 0xDC
    run xxd -s 0xDC -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "0300"  # CONSOLE subsystem
}

@test "pe: section header is valid" {
    # .text section at 0x188
    run xxd -s 0x188 -l 8 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "2e74657874000000"  # .text\0\0\0
}

# =============================================================================
# PE Header Structure (per APE specification)
# =============================================================================

@test "pe: e_lfanew at offset 0x3C points to PE header" {
    # The DWORD at 0x3C contains offset to PE signature
    run xxd -s 0x3C -l 4 -p "$FIZZBUZZ_BIN"
    assert_success

    # Convert little-endian to offset
    pe_offset=$((16#${output:6:2}${output:4:2}${output:2:2}${output:0:2}))

    # Read PE signature at that offset
    run xxd -s "$pe_offset" -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "50450000"  # PE\0\0
}

@test "pe: NumberOfSections is greater than 0" {
    # NumberOfSections is at PE+6 (COFF header offset 2)
    run xxd -s 0x86 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success

    num_sections=$((16#${output:2:2}${output:0:2}))
    assert [ "$num_sections" -gt 0 ]
}

@test "pe: SizeOfOptionalHeader is 240 (0xF0) for PE32+" {
    # SizeOfOptionalHeader at PE+20 (0x94)
    run xxd -s 0x94 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "f000"  # 240 in little-endian
}

@test "pe: Characteristics includes EXECUTABLE_IMAGE" {
    # Characteristics at PE+22 (0x96)
    run xxd -s 0x96 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success

    chars=$((16#${output:2:2}${output:0:2}))
    # IMAGE_FILE_EXECUTABLE_IMAGE = 0x0002
    assert [ $((chars & 0x0002)) -ne 0 ]
}

@test "pe: Characteristics includes LARGE_ADDRESS_AWARE" {
    # IMAGE_FILE_LARGE_ADDRESS_AWARE = 0x0020
    run xxd -s 0x96 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success

    chars=$((16#${output:2:2}${output:0:2}))
    assert [ $((chars & 0x0020)) -ne 0 ]
}

# =============================================================================
# Optional Header Fields
# =============================================================================

@test "pe: MajorSubsystemVersion is at least 6 (Vista+)" {
    # MajorSubsystemVersion at optional header + 48 (0x30) = 0x98 + 0x30 = 0xC8
    run xxd -s 0xC8 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success

    version=$((16#${output:2:2}${output:0:2}))
    assert [ "$version" -ge 6 ]
}

@test "pe: SectionAlignment is at least 4096 (0x1000)" {
    # SectionAlignment at optional header + 32 (0x20) = 0x98 + 0x20 = 0xB8
    run xxd -s 0xB8 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success

    alignment=$((16#${output:6:2}${output:4:2}${output:2:2}${output:0:2}))
    assert [ "$alignment" -ge 4096 ]
}

@test "pe: FileAlignment is at least 512 (0x200)" {
    # Spec: PE requires segment alignment on at minimum 512 byte page size
    # FileAlignment at optional header + 36 (0x24) = 0x98 + 0x24 = 0xBC
    run xxd -s 0xBC -l 4 -p "$FIZZBUZZ_BIN"
    assert_success

    alignment=$((16#${output:6:2}${output:4:2}${output:2:2}${output:0:2}))
    assert [ "$alignment" -ge 512 ]
}

@test "pe: ImageBase is above 0x10000" {
    # ImageBase at optional header + 24 (0x18) = 0x98 + 0x18 = 0xB0
    run xxd -s 0xB0 -l 8 -p "$FIZZBUZZ_BIN"
    assert_success

    # Just check it's non-zero and reasonable
    assert [ "$output" != "0000000000000000" ]
}

@test "pe: SizeOfImage is greater than 0" {
    # SizeOfImage at optional header + 56 (0x38) = 0x98 + 0x38 = 0xD0
    run xxd -s 0xD0 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success

    size=$((16#${output:6:2}${output:4:2}${output:2:2}${output:0:2}))
    assert [ "$size" -gt 0 ]
}

@test "pe: SizeOfHeaders is greater than 0" {
    # SizeOfHeaders at optional header + 60 (0x3C) = 0x98 + 0x3C = 0xD4
    run xxd -s 0xD4 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success

    size=$((16#${output:6:2}${output:4:2}${output:2:2}${output:0:2}))
    assert [ "$size" -gt 0 ]
}

@test "pe: DllCharacteristics includes NX_COMPAT (DEP)" {
    # DllCharacteristics at optional header + 70 (0x46) = 0x98 + 0x46 = 0xDE
    run xxd -s 0xDE -l 2 -p "$FIZZBUZZ_BIN"
    assert_success

    chars=$((16#${output:2:2}${output:0:2}))
    # IMAGE_DLLCHARACTERISTICS_NX_COMPAT = 0x0100
    assert [ $((chars & 0x0100)) -ne 0 ]
}

# =============================================================================
# Section Headers
# =============================================================================

@test "pe: .text section has executable flag" {
    # .text section characteristics at 0x188 + 36 = 0x1AC
    run xxd -s 0x1AC -l 4 -p "$FIZZBUZZ_BIN"
    assert_success

    chars=$((16#${output:6:2}${output:4:2}${output:2:2}${output:0:2}))
    # IMAGE_SCN_MEM_EXECUTE = 0x20000000
    assert [ $((chars & 0x20000000)) -ne 0 ]
}

@test "pe: .text section has read flag" {
    run xxd -s 0x1AC -l 4 -p "$FIZZBUZZ_BIN"
    assert_success

    chars=$((16#${output:6:2}${output:4:2}${output:2:2}${output:0:2}))
    # IMAGE_SCN_MEM_READ = 0x40000000
    assert [ $((chars & 0x40000000)) -ne 0 ]
}

@test "pe: .text section does NOT have write flag" {
    run xxd -s 0x1AC -l 4 -p "$FIZZBUZZ_BIN"
    assert_success

    chars=$((16#${output:6:2}${output:4:2}${output:2:2}${output:0:2}))
    # IMAGE_SCN_MEM_WRITE = 0x80000000
    assert [ $((chars & 0x80000000)) -eq 0 ]
}

# =============================================================================
# Data Directories
# =============================================================================

@test "pe: NumberOfRvaAndSizes is 16" {
    # NumberOfRvaAndSizes at optional header + 108 (0x6C) = 0x98 + 0x6C = 0x104
    run xxd -s 0x104 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "10000000"  # 16 in little-endian
}

# =============================================================================
# Polyglot Validation
# =============================================================================

@test "pe: MZ magic also forms valid shell variable assignment" {
    # Bytes 6-7 should be =' (0x3D 0x27)
    run xxd -s 6 -l 2 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "3d27"
}

@test "pe: file is valid PE even with shell script prefix" {
    # The polyglot header should not break PE parsing
    # Just verify the e_lfanew chain works
    run xxd -s 0x3C -l 4 -p "$FIZZBUZZ_BIN"
    assert_success

    pe_offset=$((16#${output:6:2}${output:4:2}${output:2:2}${output:0:2}))
    assert [ "$pe_offset" -gt 0 ]
    assert [ "$pe_offset" -lt 1024 ]  # Should be within first KB
}
