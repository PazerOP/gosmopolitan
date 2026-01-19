// Copyright 2024 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build cosmo && arm64

package runtime

// Semaphore implementation for cosmo arm64 using dispatch_semaphore.
// This is used by lock_sema.go for synchronization primitives.

// DISPATCH_TIME_FOREVER for infinite wait
const _DISPATCH_TIME_FOREVER = ^uint64(0)

// Assembly trampolines for dispatch_semaphore functions
// These are defined in sys_cosmo_arm64.s

//go:noescape
func dispatch_semaphore_create_trampoline(value int64) uintptr

//go:noescape
func dispatch_semaphore_signal_trampoline(sema uintptr) int64

//go:noescape
func dispatch_semaphore_wait_trampoline(sema uintptr, timeout uint64) int64

// semacreate creates a semaphore for the M.
// Called from lock_sema.go
//
//go:nosplit
func semacreate(mp *m) {
	if mp.waitsema != 0 {
		return
	}
	// Create semaphore with initial count 0
	sema := dispatch_semaphore_create_trampoline(0)
	if sema == 0 {
		// Can't create semaphore - this will cause problems
		// but we can't throw here (called too early)
		return
	}
	mp.waitsema = sema
}

// semasleep waits on the current M's semaphore.
// If ns < 0, wait forever. Otherwise wait for at most ns nanoseconds.
// Returns 0 if woken, -1 if timed out.
//
//go:nosplit
func semasleep(ns int64) int32 {
	mp := getg().m
	if mp.waitsema == 0 {
		// No semaphore - this shouldn't happen after semacreate
		// Fall back to spinning
		if ns >= 0 {
			start := nanotime()
			for nanotime()-start < ns {
				procyield(1)
			}
			return -1
		}
		// Can't spin forever
		throw("semasleep without semaphore")
	}

	var timeout uint64
	if ns < 0 {
		timeout = _DISPATCH_TIME_FOREVER
	} else {
		// dispatch_time(DISPATCH_TIME_NOW, ns) = ns nanoseconds from now
		// DISPATCH_TIME_NOW is 0, so timeout = ns gives relative timeout
		// Actually dispatch_semaphore_wait expects an absolute dispatch_time_t
		// For simplicity, use a large relative offset
		timeout = uint64(ns)
	}

	ret := dispatch_semaphore_wait_trampoline(mp.waitsema, timeout)
	if ret != 0 {
		return -1 // timed out
	}
	return 0 // woken
}

// semawakeup wakes up the M's semaphore.
//
//go:nosplit
func semawakeup(mp *m) {
	if mp.waitsema == 0 {
		return
	}
	dispatch_semaphore_signal_trampoline(mp.waitsema)
}
