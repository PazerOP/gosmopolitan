// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build cosmo && arm64

#include "textflag.h"

TEXT _rt0_arm64_cosmo(SB),NOSPLIT|NOFRAME,$0
	MOVD	0(RSP), R0	// argc
	ADD	$8, RSP, R1	// argv
	BL	main(SB)

TEXT _rt0_arm64_cosmo_lib(SB),NOSPLIT,$0
	B	_rt0_arm64_lib(SB)

TEXT main(SB),NOSPLIT|NOFRAME,$0
	MOVD	$runtime·rt0_go(SB), R2
	BL	(R2)
exit:
	MOVD	$0, R0
	MOVD	$94, R8	// SYS_exit_group
	SVC
	B	exit
