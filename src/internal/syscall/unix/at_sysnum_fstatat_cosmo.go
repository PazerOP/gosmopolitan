// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build cosmo

package unix

import "syscall"

// Cosmopolitan uses Linux syscall numbers; for amd64 NEWFSTATAT is the right call
const fstatatTrap uintptr = syscall.SYS_NEWFSTATAT
