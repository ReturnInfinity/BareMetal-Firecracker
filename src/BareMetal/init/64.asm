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
	mov ecx, 32
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
	mov ecx, 256-32
	mov eax, interrupt_gate
make_interrupt_gate_stubs:
	call create_gate
	inc edi
	dec ecx
	jnz make_interrupt_gate_stubs

	; Set device syscalls to stub
	mov eax, os_stub
	mov rdi, os_nvs_io
	stosq
	stosq

	; Configure the Stack base
	mov eax, 0x1D0000		; Stacks start at 2MiB
	mov [os_StackBase], rax

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

	; Initialize the timer
	call os_timer_init

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
