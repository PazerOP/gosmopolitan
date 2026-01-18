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
// Based on the specification at: ape/specification.md
//
// APE creates polyglot executables that work on multiple OSes:
// - Windows: Uses PE header starting with MZ magic
// - Linux: Uses embedded ELF header (encoded as octal in printf)
// - macOS: Uses dd command to copy Mach-O header backward (ARM64 uses Rosetta2)
// - Windows shell (MSYS/Cygwin): Delegates to cmd.exe for PE execution

const (
	// APE header must be page-aligned for ELF loading
	// Using 64KB for Windows allocation granularity compatibility
	apeHeaderSize = 65536

	// Page sizes
	pageSize4K  = 4096
	pageSize16K = 16384

	// ELF constants
	elfMagic      = "\x7fELF"
	elfClass64    = 2
	elfDataLSB    = 1
	elfOSABIFreeBSD = 9 // Use FreeBSD ABI per spec
	elfTypeExec   = 2
	elfMachineAMD64 = 0x3E
	elfMachineARM64 = 0xB7

	// Mach-O constants
	machoMagic64     = 0xFEEDFACF
	machoCPUTypeX64  = 0x01000007
	machoCPUSubtypeX64 = 0x80000003
	machoFileTypeExec = 0x2
	machoFlagNoUndefs = 0x1
	machoFlagPIE      = 0x200000

	// Load commands
	machoLCSegment64   = 0x19
	machoLCUnixThread  = 0x5
	machoLCMain        = 0x80000028

	// Segment protection
	machoProtRead    = 0x1
	machoProtWrite   = 0x2
	machoProtExec    = 0x4
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

	// Get ELF entry point and program headers for the embedded header
	elfEntry := binary.LittleEndian.Uint64(elfData[24:32])
	elfPhoff := binary.LittleEndian.Uint64(elfData[32:40])
	elfPhnum := binary.LittleEndian.Uint16(elfData[56:58])

	// Create the APE file
	apeFile, err := os.Create(outfile)
	if err != nil {
		Exitf("cannot create APE output: %v", err)
	}
	defer apeFile.Close()

	// Build the APE header with embedded formats
	header := makeAPEHeader(elfData, elfEntry, elfPhoff, elfPhnum, ctxt.Arch.Family)

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
// - MZ/PE header for Windows
// - Shell script with printf-encoded ELF header for Linux/BSD
// - Mach-O header and dd command for macOS x86-64
func makeAPEHeader(elfData []byte, elfEntry, elfPhoff uint64, elfPhnum uint16, arch sys.ArchFamily) []byte {
	header := make([]byte, apeHeaderSize)

	// Determine page size based on architecture
	pageSize := uint64(pageSize4K)
	if arch == sys.ARM64 {
		pageSize = pageSize16K
	}

	// ELF payload starts after the APE header
	elfOffset := uint64(apeHeaderSize)

	// Calculate the actual entry point in the APE file
	// The ELF entry point is relative to the ELF load address
	// We need to adjust for the APE header offset
	apeEntry := elfEntry

	// Create the modified ELF header that points into the APE file
	// This header will be encoded as octal in a printf statement
	embeddedElf := makeEmbeddedElfHeader(elfData, elfOffset, pageSize, arch)

	// Create Mach-O header for macOS x86-64
	var machoHeader []byte
	var machoOffset, machoSize int
	if arch == sys.AMD64 {
		machoHeader = makeMachoHeader(elfData, elfOffset, apeEntry)
		// Place Mach-O header at a specific location in the APE header
		// It will be copied backward by the dd command
		machoOffset = 0x1000 // 4KB into the header
		machoSize = len(machoHeader)
	}

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

	// Here-doc terminator and printf with embedded ELF header
	script.WriteString("__APE__\n")

	// Printf statement for the embedded ELF header (per spec)
	// The printf must exist for APE interpreters to parse, but we redirect
	// stdout to /dev/null when running as a shell script to avoid garbage output
	script.WriteString("printf '")
	for _, b := range embeddedElf {
		if b == '\'' {
			script.WriteString("'\\''")
		} else if b >= 0x20 && b < 0x7f && b != '\\' {
			script.WriteByte(b)
		} else {
			fmt.Fprintf(&script, "\\%03o", b)
		}
	}
	script.WriteString("' >/dev/null 2>&1\n")

	// Add the main execution logic
	script.WriteString(`o="$0"
[ -x "$o" ] || o=$(command -v "$0" 2>/dev/null) || o="$0"
case "$(uname -s)" in
Linux*)
  t="${TMPDIR:-/tmp}/.ape.$$.$(id -u)"
  trap 'rm -f "$t"' EXIT
`)
	fmt.Fprintf(&script, "  tail -c +%d \"$o\" > \"$t\"\n", elfOffset+1)
	script.WriteString(`  chmod +x "$t"
  exec "$t" "$@"
  ;;
Darwin*)
`)
	// Use Mach-O transformation for all Darwin (x86_64 runs native, arm64 uses Rosetta2)
	if arch == sys.AMD64 && machoSize > 0 {
		bs := 8
		skip := machoOffset / bs
		count := (machoSize + bs - 1) / bs
		fmt.Fprintf(&script, "  dd if=\"$o\" of=\"$o\" bs=%d skip=%d count=%d conv=notrunc 2>/dev/null\n", bs, skip, count)
		script.WriteString("  exec \"$o\" \"$@\"\n")
	} else {
		script.WriteString("  echo 'APE: macOS requires amd64 binary' >&2; exit 1\n")
	}
	script.WriteString(`  ;;
FreeBSD*|OpenBSD*|NetBSD*)
  t="${TMPDIR:-/tmp}/.ape.$$.$(id -u)"
  trap 'rm -f "$t"' EXIT
`)
	fmt.Fprintf(&script, "  tail -c +%d \"$o\" > \"$t\"\n", elfOffset+1)
	script.WriteString(`  chmod +x "$t"
  exec "$t" "$@"
  ;;
CYGWIN*|MINGW*|MSYS*)
  exec cmd //c "$o" "$@"
  ;;
esac
exit 1
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

	// === Mach-O header for macOS x86-64 ===
	if machoSize > 0 && machoOffset+machoSize <= apeHeaderSize {
		copy(header[machoOffset:], machoHeader)
	}

	// Ensure there's a newline before the script (required for heredoc terminator)
	// The __APE__ at the start of the script must be at the beginning of a line
	if scriptOffset > 0 {
		header[scriptOffset-1] = '\n'
	}

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

// makeEmbeddedElfHeader creates an ELF header for embedding in the APE printf statement.
// This header points to the actual ELF segments in the APE file.
func makeEmbeddedElfHeader(origElf []byte, elfOffset uint64, pageSize uint64, arch sys.ArchFamily) []byte {
	// Create a minimal ELF header (64 bytes for ELF64)
	hdr := make([]byte, 64)

	// ELF magic
	copy(hdr[0:4], elfMagic)
	hdr[4] = elfClass64                    // 64-bit
	hdr[5] = elfDataLSB                    // Little endian
	hdr[6] = 1                             // ELF version
	hdr[7] = elfOSABIFreeBSD               // FreeBSD ABI per spec

	// Object file type
	binary.LittleEndian.PutUint16(hdr[16:], elfTypeExec)

	// Machine type
	switch arch {
	case sys.ARM64:
		binary.LittleEndian.PutUint16(hdr[18:], elfMachineARM64)
	default:
		binary.LittleEndian.PutUint16(hdr[18:], elfMachineAMD64)
	}

	// ELF version
	binary.LittleEndian.PutUint32(hdr[20:], 1)

	// Entry point - copy from original
	copy(hdr[24:32], origElf[24:32])

	// Program header offset - adjusted for APE header
	phoff := binary.LittleEndian.Uint64(origElf[32:40])
	binary.LittleEndian.PutUint64(hdr[32:], phoff+elfOffset)

	// Section header offset (set to 0, not used for execution)
	binary.LittleEndian.PutUint64(hdr[40:], 0)

	// Flags
	binary.LittleEndian.PutUint32(hdr[48:], 0)

	// ELF header size
	binary.LittleEndian.PutUint16(hdr[52:], 64)

	// Program header entry size and count - copy from original
	copy(hdr[54:56], origElf[54:56]) // e_phentsize
	copy(hdr[56:58], origElf[56:58]) // e_phnum

	// Section header entry size and count (not used)
	binary.LittleEndian.PutUint16(hdr[58:], 64)
	binary.LittleEndian.PutUint16(hdr[60:], 0)
	binary.LittleEndian.PutUint16(hdr[62:], 0)

	return hdr
}

// makeMachoHeader creates a Mach-O header for macOS x86-64.
func makeMachoHeader(elfData []byte, elfOffset uint64, entry uint64) []byte {
	var buf bytes.Buffer

	// Mach-O header (32 bytes)
	binary.Write(&buf, binary.LittleEndian, uint32(machoMagic64))      // magic
	binary.Write(&buf, binary.LittleEndian, uint32(machoCPUTypeX64))   // cputype
	binary.Write(&buf, binary.LittleEndian, uint32(machoCPUSubtypeX64)) // cpusubtype
	binary.Write(&buf, binary.LittleEndian, uint32(machoFileTypeExec)) // filetype
	binary.Write(&buf, binary.LittleEndian, uint32(2))                 // ncmds (LC_SEGMENT_64 + LC_UNIXTHREAD)
	binary.Write(&buf, binary.LittleEndian, uint32(72+184))            // sizeofcmds
	binary.Write(&buf, binary.LittleEndian, uint32(machoFlagNoUndefs)) // flags
	binary.Write(&buf, binary.LittleEndian, uint32(0))                 // reserved

	// LC_SEGMENT_64 for __TEXT (72 bytes)
	binary.Write(&buf, binary.LittleEndian, uint32(machoLCSegment64)) // cmd
	binary.Write(&buf, binary.LittleEndian, uint32(72))               // cmdsize
	buf.WriteString("__TEXT\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")  // segname (16 bytes)
	binary.Write(&buf, binary.LittleEndian, uint64(0x100000000))      // vmaddr
	binary.Write(&buf, binary.LittleEndian, uint64(len(elfData)))     // vmsize
	binary.Write(&buf, binary.LittleEndian, uint64(elfOffset))        // fileoff
	binary.Write(&buf, binary.LittleEndian, uint64(len(elfData)))     // filesize
	binary.Write(&buf, binary.LittleEndian, uint32(machoProtRead|machoProtExec)) // maxprot
	binary.Write(&buf, binary.LittleEndian, uint32(machoProtRead|machoProtExec)) // initprot
	binary.Write(&buf, binary.LittleEndian, uint32(0))                // nsects
	binary.Write(&buf, binary.LittleEndian, uint32(0))                // flags

	// LC_UNIXTHREAD (184 bytes for x86_64)
	binary.Write(&buf, binary.LittleEndian, uint32(machoLCUnixThread)) // cmd
	binary.Write(&buf, binary.LittleEndian, uint32(184))              // cmdsize
	binary.Write(&buf, binary.LittleEndian, uint32(4))                // flavor (x86_THREAD_STATE64)
	binary.Write(&buf, binary.LittleEndian, uint32(42))               // count

	// Thread state (42 uint64 values = 336 bytes, but we only write key ones)
	// Registers: rax, rbx, rcx, rdx, rdi, rsi, rbp, rsp, r8-r15, rip, rflags, cs, fs, gs
	for i := 0; i < 16; i++ {
		binary.Write(&buf, binary.LittleEndian, uint64(0)) // rax through r15
	}
	binary.Write(&buf, binary.LittleEndian, entry)    // rip (entry point)
	binary.Write(&buf, binary.LittleEndian, uint64(0)) // rflags
	for i := 0; i < 4; i++ {
		binary.Write(&buf, binary.LittleEndian, uint64(0)) // cs, fs, gs, etc.
	}

	return buf.Bytes()
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
