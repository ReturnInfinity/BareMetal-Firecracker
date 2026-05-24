; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Initialize non-volatile storage
; =============================================================================


; -----------------------------------------------------------------------------
; init_nvs -- Configure the first non-volatile storage device it finds
init_nvs:

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_nvs
	call os_debug_string
%endif

	call virtio_blk_mmio_init

; TEST CODE
;	mov eax, 0
;	mov edi, 0x300000
;	mov ecx, 512
;	mov rdx, 0
;	call b_nvs_read

init_nvs_done:

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_ok
	call os_debug_string
%endif

	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
