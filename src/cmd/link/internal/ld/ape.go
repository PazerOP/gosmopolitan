// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package ld

import (
	"bytes"
	"cmd/internal/objabi"
	"cmd/internal/sys"
	"encoding/binary"
	"fmt"
	"os"
)

// APE (Actually Portable Executable) format implementation
//
// APE creates polyglot executables that work on multiple OSes:
// - The file starts with MZ magic (DOS/PE header)
// - Contains a shell script that extracts and runs the embedded ELF
// - Works on Linux, macOS, *BSD, and Windows (via shell emulation like Git Bash)

const (
	// APE header must be page-aligned for ELF loading
	// Using 64KB for Windows allocation granularity compatibility
	apeHeaderSize = 65536

	// ELF magic for validation
	elfMagic = "\x7fELF"
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

	// Verify it's a valid ELF
	if len(elfData) < 64 || string(elfData[0:4]) != elfMagic {
		Exitf("output file is not a valid ELF binary")
	}

	// Create the APE file
	apeFile, err := os.Create(outfile)
	if err != nil {
		Exitf("cannot create APE output: %v", err)
	}
	defer apeFile.Close()

	// Build the APE header
	header := makeAPEHeader(elfData, ctxt.Arch.Family)

	if _, err := apeFile.Write(header); err != nil {
		Exitf("cannot write APE header: %v", err)
	}

	// Write the ELF payload at the expected offset
	if _, err := apeFile.Write(elfData); err != nil {
		Exitf("cannot write ELF payload: %v", err)
	}

	// Make executable
	if err := os.Chmod(outfile, 0755); err != nil {
		Exitf("cannot chmod APE output: %v", err)
	}
}

// makeAPEHeader creates an APE header following the specification.
// The header is a polyglot containing:
// - MZ/PE header for Windows (stub that falls through to shell)
// - Shell script that extracts and runs the ELF payload
func makeAPEHeader(elfData []byte, arch sys.ArchFamily) []byte {
	_ = elfData // elfData size could be used for validation if needed

	header := make([]byte, apeHeaderSize)

	// ELF payload starts after the APE header
	elfOffset := uint64(apeHeaderSize)

	// === Build the APE header with shell script ===
	//
	// The APE format is a polyglot that must satisfy:
	// 1. DOS/PE: Starts with "MZ", e_lfanew at 0x3C points to PE header at 0x80
	// 2. Shell: Valid shell script that can run on UNIX systems
	//
	// Structure:
	// - Bytes 0-7: "MZqFpD='" - DOS magic + shell variable start
	// - Byte 8: newline (required by spec for shell safety)
	// - Bytes 9-59: Filler (inside shell single quote)
	// - Bytes 60-63 (0x3C): e_lfanew = 0x80 (binary, inside quote)
	// - Bytes 64-127: More filler until we close the quote
	// - After PE header area: Close quote and actual script
	//
	// The shell script is placed after offset 0x200 to avoid PE header conflicts

	// Write the APE magic at offset 0
	copy(header[0:8], []byte("MZqFpD='"))
	header[8] = '\n'

	// Fill bytes 9-59 with safe characters (inside the single-quoted string)
	// These will be part of the shell variable value (ignored)
	for i := 9; i < 0x3C; i++ {
		header[i] = ' '
	}

	// e_lfanew at 0x3C-0x3F - must point to PE header at 0x80
	// This binary data is inside the single-quoted string (safe)
	binary.LittleEndian.PutUint32(header[0x3C:], 0x80)

	// Fill bytes 0x40-0x7F with spaces (still in quoted string)
	for i := 0x40; i < 0x80; i++ {
		header[i] = ' '
	}

	// PE header goes at 0x80 - this is binary data
	// We need to close the quote before this and use a here-doc to absorb it
	// Rewrite bytes just before 0x80 to close quote and start here-doc

	// At byte 0x40, close the quote and start a here-doc to absorb PE header
	heredocStart := []byte("'\n: <<'__APE__'\n")
	copy(header[0x40:], heredocStart)

	// The PE header at 0x80 will be absorbed by the here-doc
	// We need to place the here-doc terminator and script after the PE header area

	// The script starts at offset 0x400 (after PE code section)
	// Build the script content
	var script bytes.Buffer

	// Here-doc terminator
	script.WriteString("__APE__\n")

	// Note: We don't output the embedded ELF header via printf anymore.
	// The original APE spec used printf for binfmt_misc registration,
	// but for our use case we just extract and execute the ELF payload.

	// Add the main execution logic with proper error handling
	script.WriteString(`set -e
o="$0"
[ -x "$o" ] || o=$(command -v "$0" 2>/dev/null) || o="$0"
case "$(uname -s)" in
Linux*|CYGWIN*|MINGW*|MSYS*)
  t="${TMPDIR:-/tmp}/.ape.$$.$(id -u)"
  trap 'rm -f "$t"' EXIT
`)
	fmt.Fprintf(&script, "  tail -c +%d \"$o\" > \"$t\" || { echo 'APE: Failed to extract binary' >&2; exit 1; }\n", elfOffset+1)
	script.WriteString(`  chmod +x "$t" || { echo 'APE: Failed to chmod' >&2; exit 1; }
  exec "$t" "$@"
  ;;
Darwin*)
  t="${TMPDIR:-/tmp}/.ape.$$.$(id -u)"
  trap 'rm -f "$t"' EXIT
  case "$(uname -m)" in
  x86_64)
`)
	fmt.Fprintf(&script, "    tail -c +%d \"$o\" > \"$t\" || { echo 'APE: Failed to extract binary' >&2; exit 1; }\n", elfOffset+1)
	script.WriteString(`    chmod +x "$t" || { echo 'APE: Failed to chmod' >&2; exit 1; }
    exec "$t" "$@"
    ;;
  arm64)
`)
	fmt.Fprintf(&script, "    tail -c +%d \"$o\" > \"$t\" || { echo 'APE: Failed to extract binary' >&2; exit 1; }\n", elfOffset+1)
	script.WriteString(`    chmod +x "$t" || { echo 'APE: Failed to chmod' >&2; exit 1; }
    exec "$t" "$@"
    ;;
  esac
  ;;
FreeBSD*|OpenBSD*|NetBSD*)
  t="${TMPDIR:-/tmp}/.ape.$$.$(id -u)"
  trap 'rm -f "$t"' EXIT
`)
	fmt.Fprintf(&script, "  tail -c +%d \"$o\" > \"$t\" || { echo 'APE: Failed to extract binary' >&2; exit 1; }\n", elfOffset+1)
	script.WriteString(`  chmod +x "$t" || { echo 'APE: Failed to chmod' >&2; exit 1; }
  exec "$t" "$@"
  ;;
*)
  echo "APE: Unsupported OS: $(uname -s)" >&2
  exit 1
  ;;
esac
`)

	scriptBytes := script.Bytes()

	// Place script at offset 0x400
	scriptOffset := 0x400
	if len(scriptBytes) > apeHeaderSize-scriptOffset {
		Exitf("APE shell script too large: %d bytes", len(scriptBytes))
	}
	copy(header[scriptOffset:], scriptBytes)

	// === PE Header at offset 0x80 ===
	// Required for Windows support
	writePEHeader(header, arch)

	// Pad remainder with newlines (safe for shell parsing)
	// Start after the script ends
	scriptEnd := scriptOffset + len(scriptBytes)
	for i := scriptEnd; i < apeHeaderSize; i++ {
		if header[i] == 0 {
			header[i] = '\n'
		}
	}

	return header
}

// writePEHeader writes the PE header for Windows support.
func writePEHeader(header []byte, arch sys.ArchFamily) {
	peStart := 0x80

	// PE Signature
	copy(header[peStart:], []byte{'P', 'E', 0, 0})

	// COFF Header
	coffStart := peStart + 4
	var machineType uint16
	switch arch {
	case sys.ARM64:
		machineType = 0xAA64
	default:
		machineType = 0x8664
	}
	binary.LittleEndian.PutUint16(header[coffStart+0:], machineType)
	binary.LittleEndian.PutUint16(header[coffStart+2:], 1)     // NumberOfSections
	binary.LittleEndian.PutUint32(header[coffStart+4:], 0)     // TimeDateStamp
	binary.LittleEndian.PutUint32(header[coffStart+8:], 0)     // PointerToSymbolTable
	binary.LittleEndian.PutUint32(header[coffStart+12:], 0)    // NumberOfSymbols
	binary.LittleEndian.PutUint16(header[coffStart+16:], 240)  // SizeOfOptionalHeader
	binary.LittleEndian.PutUint16(header[coffStart+18:], 0x22) // Characteristics

	// Optional Header (PE32+)
	optStart := coffStart + 20
	binary.LittleEndian.PutUint16(header[optStart+0:], 0x20B)       // Magic: PE32+
	header[optStart+2] = 1                                          // MajorLinkerVersion
	header[optStart+3] = 0                                          // MinorLinkerVersion
	binary.LittleEndian.PutUint32(header[optStart+4:], 0x200)       // SizeOfCode
	binary.LittleEndian.PutUint32(header[optStart+8:], 0)           // SizeOfInitializedData
	binary.LittleEndian.PutUint32(header[optStart+12:], 0)          // SizeOfUninitializedData
	binary.LittleEndian.PutUint32(header[optStart+16:], 0x1000)     // AddressOfEntryPoint
	binary.LittleEndian.PutUint32(header[optStart+20:], 0x1000)     // BaseOfCode
	binary.LittleEndian.PutUint64(header[optStart+24:], 0x140000000) // ImageBase
	binary.LittleEndian.PutUint32(header[optStart+32:], 0x1000)     // SectionAlignment
	binary.LittleEndian.PutUint32(header[optStart+36:], 0x200)      // FileAlignment
	binary.LittleEndian.PutUint16(header[optStart+40:], 6)          // MajorOSVersion
	binary.LittleEndian.PutUint16(header[optStart+42:], 0)          // MinorOSVersion
	binary.LittleEndian.PutUint16(header[optStart+44:], 0)          // MajorImageVersion
	binary.LittleEndian.PutUint16(header[optStart+46:], 0)          // MinorImageVersion
	binary.LittleEndian.PutUint16(header[optStart+48:], 6)          // MajorSubsystemVersion
	binary.LittleEndian.PutUint16(header[optStart+50:], 0)          // MinorSubsystemVersion
	binary.LittleEndian.PutUint32(header[optStart+52:], 0)          // Win32VersionValue
	binary.LittleEndian.PutUint32(header[optStart+56:], 0x2000)     // SizeOfImage
	binary.LittleEndian.PutUint32(header[optStart+60:], 0x200)      // SizeOfHeaders
	binary.LittleEndian.PutUint32(header[optStart+64:], 0)          // CheckSum
	binary.LittleEndian.PutUint16(header[optStart+68:], 3)          // Subsystem: CONSOLE
	binary.LittleEndian.PutUint16(header[optStart+70:], 0x8160)     // DllCharacteristics
	binary.LittleEndian.PutUint64(header[optStart+72:], 0x100000)   // SizeOfStackReserve
	binary.LittleEndian.PutUint64(header[optStart+80:], 0x1000)     // SizeOfStackCommit
	binary.LittleEndian.PutUint64(header[optStart+88:], 0x100000)   // SizeOfHeapReserve
	binary.LittleEndian.PutUint64(header[optStart+96:], 0x1000)     // SizeOfHeapCommit
	binary.LittleEndian.PutUint32(header[optStart+104:], 0)         // LoaderFlags
	binary.LittleEndian.PutUint32(header[optStart+108:], 16)        // NumberOfRvaAndSizes

	// Section Header
	sectStart := optStart + 240
	copy(header[sectStart:], []byte(".text\x00\x00\x00"))
	binary.LittleEndian.PutUint32(header[sectStart+8:], 0x1000)
	binary.LittleEndian.PutUint32(header[sectStart+12:], 0x1000)
	binary.LittleEndian.PutUint32(header[sectStart+16:], 0x200)
	binary.LittleEndian.PutUint32(header[sectStart+20:], 0x200)
	binary.LittleEndian.PutUint32(header[sectStart+24:], 0)
	binary.LittleEndian.PutUint32(header[sectStart+28:], 0)
	binary.LittleEndian.PutUint16(header[sectStart+32:], 0)
	binary.LittleEndian.PutUint16(header[sectStart+34:], 0)
	binary.LittleEndian.PutUint32(header[sectStart+36:], 0x60000020)

	// Minimal code at 0x200
	header[0x200] = 0x31 // xor eax, eax
	header[0x201] = 0xC0
	header[0x202] = 0xC3 // ret
}
