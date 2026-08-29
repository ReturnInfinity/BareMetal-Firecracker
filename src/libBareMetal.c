// =============================================================================
// BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
// Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
//
// Version 1.0
// =============================================================================


#include "libBareMetal.h"

// Apps run in ring 3 (see AppPort's port/crt0.c), so a plain near `call` to
// the kernel's fixed function-pointer table at 0x100010 can't be trusted:
// paging lets ring 3 execute those addresses, but any privileged instruction
// inside one - e.g. b_system's IRQ_ENABLE/IRQ_DISABLE, which is `sti`/`cli`
// in syscalls/system.asm - still runs at CPL 3 and #GPs, since a near call
// doesn't change CS/CPL. Every b_* call below instead traps via `int $0x80`
// with R9 = the syscall index; interrupt.asm's int_syscall gate reuses the
// same 0x100010 table but issues the `call` itself from ring 0, so
// privileged instructions inside the target function work.
#define SYSCALL_INPUT		0
#define SYSCALL_OUTPUT		1
#define SYSCALL_NET_TX		2
#define SYSCALL_NET_RX		3
#define SYSCALL_NVS_READ	4
#define SYSCALL_NVS_WRITE	5
#define SYSCALL_SYSTEM		6
#define SYSCALL_EXIT		7	// Repurposed/unused b_user slot - see int_syscall_exit


// Input/Output

u8 b_input(void) {
	u8 chr;
	register u64 idx asm("r9") = SYSCALL_INPUT;
	asm volatile ("int $0x80" : "=a"(chr) : "r"(idx) : "memory");
	return chr;
}

void b_output(const char *str, u64 nbr) {
	register u64 idx asm("r9") = SYSCALL_OUTPUT;
	asm volatile ("int $0x80" : : "S"(str), "c"(nbr), "r"(idx) : "memory");
}


// Network

void b_net_tx(void *mem, u64 len, u64 iid) {
	register u64 idx asm("r9") = SYSCALL_NET_TX;
	asm volatile ("int $0x80" : : "S"(mem), "c"(len), "d"(iid), "r"(idx) : "memory");
}

u64 b_net_rx(void **mem, u64 iid) {
	u64 tlong;
	register u64 idx asm("r9") = SYSCALL_NET_RX;
	asm volatile ("int $0x80" : "=D"(*mem), "=c"(tlong) : "d"(iid), "r"(idx) : "memory");
	return tlong;
}


// Non-volatile Storage

u64 b_nvs_read(void *mem, u64 start, u64 num, u64 drivenum) {
	u64 tlong;
	register u64 idx asm("r9") = SYSCALL_NVS_READ;
	asm volatile ("int $0x80" : "=c"(tlong) : "a"(start), "c"(num), "d"(drivenum), "D"(mem), "r"(idx) : "memory");
	return tlong;
}

u64 b_nvs_write(void *mem, u64 start, u64 num, u64 drivenum) {
	u64 tlong = 0;
	register u64 idx asm("r9") = SYSCALL_NVS_WRITE;
	asm volatile ("int $0x80" : "=c"(tlong) : "a"(start), "c"(num), "d"(drivenum), "S"(mem), "r"(idx) : "memory");
	return tlong;
}


// System

u64 b_system(u64 function, u64 var1, u64 var2) {
	u64 tlong;
	register u64 idx asm("r9") = SYSCALL_SYSTEM;
	asm volatile ("int $0x80" : "=a"(tlong) : "c"(function), "a"(var1), "d"(var2), "r"(idx) : "memory");
	return tlong;
}

// Exit -- interrupt.asm's int_syscall_exit tears down to the kernel's own
// stack and resumes start_app (kernel.asm) instead of iretq-ing back here,
// so this never returns.
__attribute__((noreturn)) void b_exit(void) {
	register u64 idx asm("r9") = SYSCALL_EXIT;
	asm volatile ("int $0x80" : : "r"(idx) : "memory");
	__builtin_unreachable();
}


// =============================================================================
// EOF
