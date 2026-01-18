// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build cosmo && arm64

#include "textflag.h"

// The APE loader (ape-m1.c) passes the following when jumping to the entry point:
//   X0  = stack pointer (not used, SP is already set)
//   X2  = path to executable
//   X3  = host OS indicator (8 = XNU/macOS, 0 = Linux, etc.)
//   X15 = Syslib pointer (Apple APIs for macOS)
//   X16 = entry point (used for the jump, not relevant here)
//
// We need to save X3 and X15 before calling the Go runtime.

DATA runtime·__hostos+0(SB)/4, $0
GLOBL runtime·__hostos(SB), NOPTR, $4

DATA runtime·__syslib+0(SB)/8, $0
GLOBL runtime·__syslib(SB), NOPTR, $8

TEXT _rt0_arm64_cosmo(SB),NOSPLIT|NOFRAME,$0
	// Save host OS indicator (X3) and Syslib pointer (X15)
	// These are passed by the APE loader on macOS ARM64.
	// On Linux, these registers may contain garbage, but that's OK
	// because we check __hostos before using __syslib.
	MOVW	R3, runtime·__hostos(SB)
	MOVD	R15, runtime·__syslib(SB)

	// Jump to the common ARM64 entry point
	JMP	_rt0_arm64(SB)

TEXT _rt0_arm64_cosmo_lib(SB),NOSPLIT,$0
	// For shared library builds, also save the Syslib info
	MOVW	R3, runtime·__hostos(SB)
	MOVD	R15, runtime·__syslib(SB)
	JMP	_rt0_arm64_lib(SB)
