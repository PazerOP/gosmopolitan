#!/usr/bin/env bats

# Test suite for APE Mach-O structure verification

setup() {
    TESTDATA_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    load "$TESTDATA_DIR/test_helper/bats-support/load"
    load "$TESTDATA_DIR/test_helper/bats-assert/load"

    [[ -n "$FIZZBUZZ_BIN" ]] || { echo "ERROR: FIZZBUZZ_BIN not set"; return 1; }
    [[ -f "$FIZZBUZZ_BIN" ]] || { echo "ERROR: $FIZZBUZZ_BIN not found"; return 1; }
}

@test "mach-o: header at offset 0x1000 is valid" {
    # Magic
    run xxd -s 0x1000 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "cffaedfe"  # MH_MAGIC_64

    # CPU type
    run xxd -s 0x1004 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "07000001"  # CPU_TYPE_X86_64

    # CPU subtype
    run xxd -s 0x1008 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "03000080"  # CPU_SUBTYPE_X86_64_ALL

    # File type
    run xxd -s 0x100c -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "02000000"  # MH_EXECUTE

    # ncmds
    run xxd -s 0x1010 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "02000000"  # 2 load commands
}

@test "mach-o: dd transform produces valid header" {
    MACHO_BIN=$(mktemp)
    cp "$FIZZBUZZ_BIN" "$MACHO_BIN"
    dd if="$MACHO_BIN" of="$MACHO_BIN" bs=8 skip=512 count=36 conv=notrunc 2>/dev/null

    # Starts with magic after transform
    run xxd -l 4 -p "$MACHO_BIN"
    assert_success
    assert_output "cffaedfe"

    rm -f "$MACHO_BIN"
}

@test "mach-o: otool parses transformed binary" {
    MACHO_BIN=$(mktemp)
    cp "$FIZZBUZZ_BIN" "$MACHO_BIN"
    dd if="$MACHO_BIN" of="$MACHO_BIN" bs=8 skip=512 count=36 conv=notrunc 2>/dev/null

    run "$OTOOL" -l "$MACHO_BIN"
    assert_success
    assert_output --partial "vmaddr 0x0000000100000000"
    assert_output --partial "fileoff 65536"
    assert_output --partial "LC_SEGMENT_64"
    assert_output --partial "LC_UNIXTHREAD"

    rm -f "$MACHO_BIN"
}

@test "mach-o: LC_UNIXTHREAD cmdsize matches thread state" {
    # LC_UNIXTHREAD is at offset 0x1000 + 32 (header) + 72 (LC_SEGMENT_64) = 0x1068
    # cmdsize is at offset 4 within the load command
    run xxd -s 0x106C -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "b8000000"  # 184 = 0xB8 (8 byte header + 8 byte flavor/count + 168 byte thread state)

    # count field is at offset 12 within LC_UNIXTHREAD
    run xxd -s 0x1074 -l 4 -p "$FIZZBUZZ_BIN"
    assert_success
    assert_output "2a000000"  # 42 = 0x2A (42 uint32s = 168 bytes)

    # Total header should be 32 + 72 + 184 = 288 bytes = 0x120
    # Verify we have valid data at end of LC_UNIXTHREAD (offset 0x1000 + 288 - 8 = 0x1118)
    # and garbage/zeros after (at 0x1120)
}

@test "mach-o: entry point matches ELF entry point" {
    MACHO_BIN=$(mktemp)
    ELF_BIN=$(mktemp)

    cp "$FIZZBUZZ_BIN" "$MACHO_BIN"
    dd if="$MACHO_BIN" of="$MACHO_BIN" bs=8 skip=512 count=36 conv=notrunc 2>/dev/null
    dd if="$FIZZBUZZ_BIN" bs=1 skip=65536 of="$ELF_BIN" 2>/dev/null

    elf_entry=$("$READELF" -h "$ELF_BIN" | grep "Entry point" | grep -oE '0x[0-9a-f]+')
    macho_entry=$("$OTOOL" -l "$MACHO_BIN" | grep -A20 "LC_UNIXTHREAD" | grep "rip" | awk '{print $2}')

    echo "ELF entry: $elf_entry"
    echo "Mach-O rip: $macho_entry"

    elf_norm=$(echo "$elf_entry" | tr '[:upper:]' '[:lower:]')
    macho_norm=$(echo "$macho_entry" | tr '[:upper:]' '[:lower:]')
    [[ "$elf_norm" == "$macho_norm" ]]

    rm -f "$MACHO_BIN" "$ELF_BIN"
}
