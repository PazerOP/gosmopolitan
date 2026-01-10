// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package os

import "syscall"

func hostname() (name string, err error) {
	// Use uname to get hostname
	var un syscall.Utsname
	err = syscall.Uname(&un)
	if err != nil {
		return "", err
	}

	var buf [512]byte // Enough for a DNS name.
	for i, b := range un.Nodename[:] {
		buf[i] = uint8(b)
		if b == 0 {
			name = string(buf[:i])
			break
		}
	}
	// If we got a name and it's not potentially truncated
	// (Nodename is 65 bytes), return it.
	if len(name) > 0 && len(name) < 64 {
		return name, nil
	}

	f, err := Open("/proc/sys/kernel/hostname")
	if err != nil {
		return "", err
	}
	defer f.Close()

	n, err := f.Read(buf[:])
	if err != nil {
		return "", err
	}

	if n > 0 && buf[n-1] == '\n' {
		n--
	}
	return string(buf[:n]), nil
}
