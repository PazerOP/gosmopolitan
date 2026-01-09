// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build cosmo && amd64

package unix

// Cosmopolitan uses Linux syscall numbers.
const (
	getrandomTrap       uintptr = 318
	copyFileRangeTrap   uintptr = 326
	pidfdSendSignalTrap uintptr = 424
	pidfdOpenTrap       uintptr = 434
	openat2Trap         uintptr = 437
)
