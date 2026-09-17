; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; 64-bit initialization
; =============================================================================


; -----------------------------------------------------------------------------
init_64:
	; Gather data from Pure64's InfoMap
	mov esi, 0x00005060		; LAPIC
	lodsq
	mov [os_LocalAPICAddress], rax
	mov esi, 0x00005020		; RAMAMOUNT
	lodsd
	sub eax, 2			; Save 2 MiB for kernel
	mov [os_MemAmount], eax		; In MiB's
	mov esi, 0x000050E2
	lodsb
	mov [os_boot_mode], al
	xor eax, eax
	mov esi, 0x00005604		; IOAPIC
	lodsd
	mov [os_IOAPICAddress], rax

	; Create exception gate stubs (Pure64 has already set the correct gate markers)
	xor edi, edi			; 64-bit IDT at linear address 0x0000000000000000
	mov ecx, 32			; Create 32 even though current CPUs only generate up to 21
	mov eax, exception_gate		; A generic exception handler
make_exception_gate_stubs:
	call create_gate
	inc edi
	dec ecx
	jnz make_exception_gate_stubs

	; Set up the exception gates for all of the CPU exceptions
	xor edi, edi
	mov ecx, 21
	mov eax, exception_gate_00
make_exception_gates:
	call create_gate
	inc edi
	add rax, 24			; Each exception gate is 24 bytes
	dec rcx
	jnz make_exception_gates

	; Create interrupt gate stubs (Pure64 has already set the correct gate markers)
	mov edi, 32
	mov ecx, 256-32
	mov eax, interrupt_gate
make_interrupt_gate_stubs:
	call create_gate
	inc edi
	dec ecx
	jnz make_interrupt_gate_stubs

	; Install the ring 3 -> ring 0 syscall gate (int 0x80). Bump its DPL to 3
	; so user-mode app code is allowed to trigger it - every other vector stays
	; DPL 0.
	mov edi, SYSCALL_VECTOR
	mov eax, int_syscall
	call create_gate
	mov edi, SYSCALL_VECTOR
	shl edi, 4			; IDT entry = vector * 16 bytes
	add edi, 5			; Offset of the type/attribute byte within the entry
	or byte [edi], 0x60		; Raise DPL 0 -> DPL 3 (bits 6:5)

	; Zero app_bmos_syscall_ptr so a `syscall` instruction reaching
	; int_syscall_fast before the app has published its own __bmos_syscall()
	; address (crt0.c, very first thing _start_c does) NULL-calls and faults
	; cleanly, instead of jumping into whatever garbage was left in this low
	; page at boot.
	xor eax, eax
	mov [app_bmos_syscall_ptr], rax

	; Install the SYSCALL/SYSRET fast-syscall path (IA32_LSTAR/STAR/FMASK,
	; EFER.SCE) -- a second way from ring 3 into the kernel, alongside int
	; 0x80 above. Added because some ring-3 runtimes (Zig's std is the
	; concrete case) emit the raw `syscall` opcode directly wherever they
	; think they're "talking to Linux", never going through a call musl's
	; patched syscall_arch.h could intercept the way every other syscall
	; here does -- there is nothing to retarget to int 0x80 in that case.
	; See int_syscall_fast's own header (interrupt.asm) for the entry
	; stub itself, and BareMetal-AppPort's ZIG.md/OPENISSUES.md Zig section
	; for the full story, including the boot-crash (Exception 0x06 UD) that
	; motivated this.
	mov ecx, IA32_EFER
	rdmsr
	bts eax, 0			; SCE (SYSCALL Enable, bit 0)
	wrmsr

	mov ecx, IA32_STAR
	xor eax, eax			; Low 32 bits (legacy 32-bit SYSCALL target) unused -- apps here are always 64-bit
	mov edx, (SYSRET_CS32_SEL << 16) | SYS64_CODE_SEL	; [47:32] = SYSCALL target CS (SS = CS+8 = SYS64_DATA_SEL); [63:48] = SYSRET base (see init.asm's gdt64 comment for why CS/SS come from base+16/base+8)
	wrmsr

	mov ecx, IA32_LSTAR
	mov eax, int_syscall_fast	; Kernel loads at 0x100000 (ORG, kernel.asm) -- well within 32 bits, so EDX (bits 63:32) is 0
	xor edx, edx
	wrmsr

	mov ecx, IA32_FMASK
	mov eax, (1 << 9) | (1 << 8) | (1 << 10)	; Clear IF/TF/DF on entry (bits 9/8/10) -- same "interrupts off while we manually swap to the kernel stack" posture int 0x80's interrupt-gate gets for free from the CPU; TF/DF off matches every other kernel entry path here
	xor edx, edx
	wrmsr

	; Set device syscalls to stub
	mov eax, os_stub
	mov rdi, os_nvs_io
	stosq
	stosq

	; Configure the system stack base
	mov eax, os_sys_stack_base
	mov [os_StackBase], rax

	; Configure the TSS so ring 3 -> ring 0 transitions (interrupts, exceptions,
	; and the int 0x80 syscall gate) land on a valid kernel stack. RSP0 is the
	; only field that is used here - IST(1-7)/RSP1/RSP2/the I/O Map Base Address are unused.
	; See "64-Bit TSS Format" in Intel docs
	mov edi, sys_tss
	xor eax, eax
	mov ecx, 0x68/8
	rep stosq			; Zero the whole 104-byte TSS
	mov rax, [os_StackBase]
	add rax, 65536			; Same kernel stack top 'start' (kernel.asm) sets RSP to
	mov [sys_tss+4], rax		; RSP0
	mov ax, TSS_SEL
	ltr ax				; Load Task Register

	; Configure Network packet buffer base
	mov eax, os_rx_buffer
	mov [os_PacketBase], rax

	; Configure the serial port (if present)
	call serial_init

	mov eax, b_output_serial
	mov [0x100018], rax		; Set kernel b_output to the serial port

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_baremetal
	call os_debug_string
	mov esi, msg_64
	call os_debug_string
%endif

	; Initialize the APIC
	call os_apic_init

	; Initialize the I/O APIC
	call os_ioapic_init

	; Initialize the clock
	call os_clock_init

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_ok
	call os_debug_string
%endif

	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; create_gate
; rax = address of handler
; rdi = gate # to configure
create_gate:
	push rdi
	push rax

	shl rdi, 4			; Quickly multiply rdi by 16
	stosw				; Store the low word (15..0)
	shr rax, 16
	add rdi, 4			; Skip the gate marker (selector, ist, type)
	stosw				; Store the high word (31..16)
	shr rax, 16
	stosd				; Store the high dword (63..32)
	xor eax, eax
	stosd				; Reserved bits

	pop rax
	pop rdi
	ret
; -----------------------------------------------------------------------------


; MSR List (SYSCALL/SYSRET)
IA32_EFER		equ 0xC0000080
IA32_STAR		equ 0xC0000081
IA32_LSTAR		equ 0xC0000082
IA32_FMASK		equ 0xC0000084


; =============================================================================
; EOF
