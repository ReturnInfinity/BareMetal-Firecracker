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

	; Set device syscalls to stub
	mov eax, os_stub
	mov rdi, os_nvs_io
	stosq
	stosq

	; Configure the Stack base
	mov eax, 0x1D0000		; Stacks start at 2MiB
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


; =============================================================================
; EOF
