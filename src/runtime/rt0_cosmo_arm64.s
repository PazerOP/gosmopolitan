// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build cosmo && arm64

#include "textflag.h"

TEXT _rt0_arm64_cosmo(SB),NOSPLIT|NOFRAME,$0
	JMP	_rt0_arm64(SB)

TEXT _rt0_arm64_cosmo_lib(SB),NOSPLIT,$0
	JMP	_rt0_arm64_lib(SB)
