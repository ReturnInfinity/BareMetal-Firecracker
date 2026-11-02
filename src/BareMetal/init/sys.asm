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

	; Calibrate the APIC timer against KVM
	call os_apic_timer_calibrate

	; No periodic timer is started here anymore. The kernel is tickless: an idle
	; HLT stays halted until a device interrupt arrives, and b_sleep arms a
	; one-shot LAPIC timer only for the duration of the sleep. An app that
	; wants a periodic tick (e.g. for CALLBACK_TIMER) enables it via TIMER_SET.

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_ready
	call os_debug_string
%endif

	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
