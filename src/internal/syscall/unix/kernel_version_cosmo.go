// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build cosmo

package unix

// KernelVersion returns the major and minor version of the kernel.
// For Cosmopolitan, we report a reasonable Linux kernel version
// since Cosmopolitan provides Linux syscall compatibility.
func KernelVersion() (major int, minor int) {
	// Report Linux 5.0 as a baseline for modern syscall support
	return 5, 0
}
