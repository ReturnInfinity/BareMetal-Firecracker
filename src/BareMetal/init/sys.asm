; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Initialize system to start payload
; =============================================================================


; -----------------------------------------------------------------------------
init_sys:

	; Firecracker
	call mem_virtio_mmio_init

	; Gather boot time
	call kvm_ns
	xor edx, edx
	mov ecx, 1000
	div ecx
	mov [os_boot_time], rax		; Store the boot time in os_boot_time

	; Calibrate the APIC timer against KVM
	call os_apic_timer_calibrate

	; Start the periodic timer
	mov rax, 1000000		; 1,000,000 ns = 1ms (1000Hz)
	mov ecx, 0x68
	call b_system

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_ready
	call os_debug_string
%endif

	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
