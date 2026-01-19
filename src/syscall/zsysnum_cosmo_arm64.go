// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Additional syscall number aliases for Cosmopolitan Libc on arm64.
// The main syscall numbers come from zsysnum_linux_arm64.go.

//go:build cosmo && arm64

package syscall

const (
	// Alias for SYS_FSTATAT (some code uses this name)
	SYS_NEWFSTATAT = 79

	// Added in newer kernels
	SYS_COPY_FILE_RANGE = 285
)
