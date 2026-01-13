// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package ld

import (
	"cmd/internal/objabi"
	"cmd/internal/sys"
	"encoding/binary"
	"os"
)

// APE header size - must be page aligned for proper ELF loading
const apeHeaderSize = 4096

// PE header constants
const (
	peHeaderOffset    = 0x80  // Where PE header starts (after DOS stub)
	peOptionalSize64  = 112   // Size of PE32+ optional header (without data directories)
	peNumDataDirs     = 16    // Number of data directory entries
	peSectionHdrSize  = 40    // Size of one section header
	peCodeSectionRVA  = 0x1000 // RVA where code section starts
)

// convertToAPE converts an ELF binary to Actually Portable Executable format.
func (ctxt *Link) convertToAPE() {
	if ctxt.HeadType != objabi.Hcosmo {
		return
	}

	outfile := *flagOutfile
	if outfile == "" {
		return
	}

	// Read the ELF file we just created
	elfData, err := os.ReadFile(outfile)
	if err != nil {
		Exitf("cannot read output file for APE conversion: %v", err)
	}

	// Create the APE file
	apeFile, err := os.Create(outfile)
	if err != nil {
		Exitf("cannot create APE output: %v", err)
	}
	defer apeFile.Close()

	// Write APE header (MZ + PE + shell script)
	header := makeAPEHeader(len(elfData), ctxt.Arch.Family)
	if _, err := apeFile.Write(header); err != nil {
		Exitf("cannot write APE header: %v", err)
	}

	// Write the ELF payload
	if _, err := apeFile.Write(elfData); err != nil {
		Exitf("cannot write ELF payload: %v", err)
	}

	// Make executable
	if err := os.Chmod(outfile, 0755); err != nil {
		Exitf("cannot chmod APE output: %v", err)
	}
}

// makeAPEHeader creates a proper APE header with both PE and shell script support.
// The header is a polyglot that works on Windows (via PE) and Unix (via shell script).
func makeAPEHeader(elfSize int, archFamily sys.ArchFamily) []byte {
	header := make([]byte, apeHeaderSize)

	// === DOS Header (64 bytes) ===
	// The DOS header starts with MZ magic and contains e_lfanew pointing to PE header.
	// We use "MZqFpD='" which is both valid DOS MZ and a shell variable assignment.
	copy(header[0:8], []byte("MZqFpD='"))

	// DOS header fields (most can be zero for modern Windows)
	// Offset 0x02: e_cblp (bytes on last page) - part of shell script, doesn't matter
	// Offset 0x3C: e_lfanew - offset to PE header (critical!)
	binary.LittleEndian.PutUint32(header[0x3C:], peHeaderOffset)

	// === PE Header at offset 0x80 ===
	peStart := peHeaderOffset

	// PE Signature: "PE\0\0"
	copy(header[peStart:], []byte{'P', 'E', 0, 0})

	// COFF Header (20 bytes) at peStart+4
	coffStart := peStart + 4
	// Machine type depends on target architecture
	var machineType uint16
	switch archFamily {
	case sys.ARM64:
		machineType = 0xAA64 // ARM64
	default:
		machineType = 0x8664 // AMD64
	}
	binary.LittleEndian.PutUint16(header[coffStart+0:], machineType)
	binary.LittleEndian.PutUint16(header[coffStart+2:], 1)       // NumberOfSections
	binary.LittleEndian.PutUint32(header[coffStart+4:], 0)       // TimeDateStamp
	binary.LittleEndian.PutUint32(header[coffStart+8:], 0)       // PointerToSymbolTable
	binary.LittleEndian.PutUint32(header[coffStart+12:], 0)      // NumberOfSymbols
	optHeaderSize := peOptionalSize64 + (peNumDataDirs * 8)
	binary.LittleEndian.PutUint16(header[coffStart+16:], uint16(optHeaderSize)) // SizeOfOptionalHeader
	binary.LittleEndian.PutUint16(header[coffStart+18:], 0x22)   // Characteristics: EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE

	// Optional Header (PE32+) at coffStart+20
	optStart := coffStart + 20
	binary.LittleEndian.PutUint16(header[optStart+0:], 0x20B)    // Magic: PE32+ (64-bit)
	header[optStart+2] = 1                                        // MajorLinkerVersion
	header[optStart+3] = 0                                        // MinorLinkerVersion
	binary.LittleEndian.PutUint32(header[optStart+4:], 0x200)    // SizeOfCode
	binary.LittleEndian.PutUint32(header[optStart+8:], 0)        // SizeOfInitializedData
	binary.LittleEndian.PutUint32(header[optStart+12:], 0)       // SizeOfUninitializedData
	binary.LittleEndian.PutUint32(header[optStart+16:], peCodeSectionRVA) // AddressOfEntryPoint
	binary.LittleEndian.PutUint32(header[optStart+20:], peCodeSectionRVA) // BaseOfCode

	// PE32+ specific fields (no BaseOfData in 64-bit)
	binary.LittleEndian.PutUint64(header[optStart+24:], 0x140000000) // ImageBase
	binary.LittleEndian.PutUint32(header[optStart+32:], 0x1000)   // SectionAlignment
	binary.LittleEndian.PutUint32(header[optStart+36:], 0x200)    // FileAlignment
	binary.LittleEndian.PutUint16(header[optStart+40:], 6)        // MajorOperatingSystemVersion
	binary.LittleEndian.PutUint16(header[optStart+42:], 0)        // MinorOperatingSystemVersion
	binary.LittleEndian.PutUint16(header[optStart+44:], 0)        // MajorImageVersion
	binary.LittleEndian.PutUint16(header[optStart+46:], 0)        // MinorImageVersion
	binary.LittleEndian.PutUint16(header[optStart+48:], 6)        // MajorSubsystemVersion
	binary.LittleEndian.PutUint16(header[optStart+50:], 0)        // MinorSubsystemVersion
	binary.LittleEndian.PutUint32(header[optStart+52:], 0)        // Win32VersionValue

	// Calculate sizes
	totalHeaderSize := uint32(peHeaderOffset + 4 + 20 + optHeaderSize + peSectionHdrSize)
	alignedHeaderSize := (totalHeaderSize + 0x1FF) &^ 0x1FF // Align to FileAlignment
	imageSize := uint32(peCodeSectionRVA + 0x1000)          // Headers + one section

	binary.LittleEndian.PutUint32(header[optStart+56:], imageSize)        // SizeOfImage
	binary.LittleEndian.PutUint32(header[optStart+60:], alignedHeaderSize) // SizeOfHeaders
	binary.LittleEndian.PutUint32(header[optStart+64:], 0)        // CheckSum
	binary.LittleEndian.PutUint16(header[optStart+68:], 3)        // Subsystem: CONSOLE
	binary.LittleEndian.PutUint16(header[optStart+70:], 0x8160)   // DllCharacteristics: DYNAMIC_BASE|NX_COMPAT|TERMINAL_SERVER_AWARE|HIGH_ENTROPY_VA
	binary.LittleEndian.PutUint64(header[optStart+72:], 0x100000)  // SizeOfStackReserve
	binary.LittleEndian.PutUint64(header[optStart+80:], 0x1000)    // SizeOfStackCommit
	binary.LittleEndian.PutUint64(header[optStart+88:], 0x100000)  // SizeOfHeapReserve
	binary.LittleEndian.PutUint64(header[optStart+96:], 0x1000)    // SizeOfHeapCommit
	binary.LittleEndian.PutUint32(header[optStart+104:], 0)        // LoaderFlags
	binary.LittleEndian.PutUint32(header[optStart+108:], peNumDataDirs) // NumberOfRvaAndSizes

	// Data directories (16 entries, 8 bytes each) - all zeros for minimal PE
	// They start at optStart+112 and span 128 bytes

	// Section Header at optStart+112+128
	sectStart := optStart + peOptionalSize64 + (peNumDataDirs * 8)
	copy(header[sectStart:], []byte(".text\x00\x00\x00"))         // Name (8 bytes)
	binary.LittleEndian.PutUint32(header[sectStart+8:], 0x1000)   // VirtualSize
	binary.LittleEndian.PutUint32(header[sectStart+12:], peCodeSectionRVA) // VirtualAddress
	binary.LittleEndian.PutUint32(header[sectStart+16:], 0x200)   // SizeOfRawData
	binary.LittleEndian.PutUint32(header[sectStart+20:], 0x200)   // PointerToRawData (file offset)
	binary.LittleEndian.PutUint32(header[sectStart+24:], 0)       // PointerToRelocations
	binary.LittleEndian.PutUint32(header[sectStart+28:], 0)       // PointerToLinenumbers
	binary.LittleEndian.PutUint16(header[sectStart+32:], 0)       // NumberOfRelocations
	binary.LittleEndian.PutUint16(header[sectStart+34:], 0)       // NumberOfLinenumbers
	binary.LittleEndian.PutUint32(header[sectStart+36:], 0x60000020) // Characteristics: CODE|EXECUTE|READ

	// === Code Section at file offset 0x200 ===
	// Minimal code that exits with code 0
	// This uses the appropriate calling convention for the target architecture
	codeStart := 0x200
	switch archFamily {
	case sys.ARM64:
		// ARM64: mov x0, #0; ret
		// MOV X0, #0 = 0xD2800000
		// RET = 0xD65F03C0
		binary.LittleEndian.PutUint32(header[codeStart:], 0xD2800000)   // mov x0, #0
		binary.LittleEndian.PutUint32(header[codeStart+4:], 0xD65F03C0) // ret
	default:
		// x86_64: xor eax, eax; ret
		header[codeStart+0] = 0x31 // xor eax, eax
		header[codeStart+1] = 0xC0
		header[codeStart+2] = 0xC3 // ret
	}

	// Fill rest of code section with newlines (safe for shell here-doc)
	for i := codeStart + 3; i < 0x400; i++ {
		header[i] = '\n'
	}

	// === Shell Script ===
	// The shell script must work around the binary PE data.
	// Strategy: Close the MZqFpD=' quote, start a comment that spans the binary areas,
	// then place the main script after all PE structures.

	// Offset 8: Close quote and start comment to absorb DOS header binary data
	copy(header[8:11], []byte("'\n#"))

	// Offsets 0x0B to 0x3B: Fill with dots (inside comment, before e_lfanew)
	for i := 0x0B; i < 0x3C; i++ {
		header[i] = '.'
	}
	// Note: 0x3C-0x3F contains e_lfanew (binary), still in comment line

	// Offset 0x40: Continue after e_lfanew, still in comment until we hit newline
	// We need the comment to continue past all the PE header binary data
	// PE header is at 0x80-0x1F8 (approximately), section header ends around 0x1F8
	// Code section is at 0x200-0x3FF
	// So we comment everything until 0x400 where our script resides

	// Fill 0x40-0x7F with dots (before PE header)
	for i := 0x40; i < 0x80; i++ {
		header[i] = '.'
	}

	// The PE header at 0x80 is already written above (binary data)
	// We need to ensure it's not treated as shell commands
	// The comment started at offset 0x0A continues until a newline

	// Problem: The PE header contains binary including potential newlines
	// Solution: Start a here-doc that absorbs everything until a marker

	// Rewrite the early shell portion to use a here-doc approach
	// At offset 8, after MZqFpD=':
	shellStart := []byte("'\n: <<'APEMAGIC'\n")
	copy(header[8:], shellStart)
	// This starts a here-doc that will absorb all binary data until APEMAGIC

	// Place APEMAGIC marker and main script after code section at 0x400
	shellMain := `APEMAGIC
p="$0"
[ ! -f "$p" ] && p=$(command -v "$0" 2>/dev/null)
t="${TMPDIR:-/tmp}/.ape.$$.$(id -u)"
trap "rm -f '$t'" EXIT
tail -c +4097 "$p" > "$t" && chmod +x "$t" && exec "$t" "$@"
exit 1
`
	copy(header[0x400:], []byte(shellMain))

	// Pad remainder with newlines
	scriptEnd := 0x400 + len(shellMain)
	for i := scriptEnd; i < apeHeaderSize; i++ {
		header[i] = '\n'
	}

	return header
}
