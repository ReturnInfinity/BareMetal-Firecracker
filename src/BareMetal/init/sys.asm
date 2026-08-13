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

; Debug - test callback
	mov rax, sys_debug_callback
	mov ecx, 0x60
	call b_system

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_ready
	call os_debug_string
%endif

	ret
; -----------------------------------------------------------------------------

sys_debug_callback:
	push rax

; Debug - Display 01 every X ticks
	mov rax, [os_ticks]
	test rax, 0x3FF			; Only print about once a second (every 1024 ticks @ 1000Hz)
	jnz int_apic_timer_debug_skip
	mov al, 01
	call os_debug_dump_al
int_apic_timer_debug_skip:

	pop rax
	ret

; =============================================================================
; EOF
