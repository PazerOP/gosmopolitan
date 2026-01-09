// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package ld

import (
	"cmd/internal/objabi"
	"os"
)

// APE header size - must be page aligned for proper ELF loading
const apeHeaderSize = 4096

// convertToAPE converts an ELF binary to Actually Portable Executable format.
// APE is a polyglot format created by Justine Tunney for Cosmopolitan Libc.
// See https://justine.lol/ape.html and https://github.com/jart/cosmopolitan
//
// The APE format is a polyglot that combines:
// - DOS MZ header (for Windows)
// - Shell script (for Unix systems)
// - ELF payload (the actual program)
//
// The magic bytes "MZqFpD='" serve as both a valid DOS MZ signature
// and a shell variable assignment, allowing the file to be executed
// as either a Windows executable or a Unix shell script.
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

	// Write APE header (MZ + shell script)
	header := makeAPEHeader()
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

// makeAPEHeader creates the APE header following the Cosmopolitan format.
// Reference: https://github.com/jart/cosmopolitan/blob/master/ape/ape.S
// Reference: https://github.com/jart/cosmopolitan/blob/master/ape/specification.md
func makeAPEHeader() []byte {
	header := make([]byte, apeHeaderSize)

	// APE magic: "MZqFpD='" (hex: 4d 5a 71 46 70 44 3d 27)
	// This is both a valid DOS MZ signature AND a shell variable assignment.
	// When executed as a shell script, the shell assigns an empty string to
	// the variable MZqFpD and continues executing the rest as shell commands.
	copy(header[0:], []byte("MZqFpD='"))

	// Offset 0x08: Continue the shell script
	// The single quote from MZqFpD=' is closed, then we start the shell code.
	// We use a here-document to skip over the binary MZ header fields.
	shellScript := `'
# APE - Actually Portable Executable
# https://justine.lol/ape.html
o="$0"
if [ ! -f "$o" ]; then
  o=$(command -v "$0" 2>/dev/null)
fi
# Try system APE loader first
if command -v ape >/dev/null 2>&1; then
  exec ape "$o" "$@"
fi
# Extract and run embedded ELF
t="${TMPDIR:-/tmp}/.ape-$(id -u).$$"
trap "rm -f \"$t\"" EXIT
tail -c +4097 "$o" > "$t" && chmod +x "$t" && exec "$t" "$@"
echo "APE: execution failed" >&2
exit 1
#`
	copy(header[8:], []byte(shellScript))

	// Fill remaining header with padding
	// Use newlines which are safe in shell context
	scriptEnd := 8 + len(shellScript)
	for i := scriptEnd; i < apeHeaderSize; i++ {
		header[i] = '\n'
	}

	return header
}
