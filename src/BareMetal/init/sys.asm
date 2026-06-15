; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Initialize system to start payload
; =============================================================================


; -----------------------------------------------------------------------------
init_sys:

	; Gather boot time
	call kvm_get_usec
	mov [os_boot_time], rax		; Store the boot time in os_boot_time

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_ready
	call os_debug_string
%endif

	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
