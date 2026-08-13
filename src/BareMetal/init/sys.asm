; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Initialize system to start payload
; =============================================================================


; -----------------------------------------------------------------------------
init_sys:

	; Gather boot time
	call kvm_ns
	xor edx, edx
	mov ecx, 1000
	div ecx
	mov [os_boot_time], rax		; Store the boot time in os_boot_time

; Debug
	; Calibrate the APIC timer against KVM
	call os_apic_timer_calibrate

; Debug
; TODO - Set as system call to enable
	; Start the periodic timer
	mov rax, SCHED_TICK_PERIOD_NS
	call os_apic_timer_set

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_ready
	call os_debug_string
%endif

	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
