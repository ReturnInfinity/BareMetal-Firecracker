; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Initialize network
; =============================================================================


; -----------------------------------------------------------------------------
; init_net -- Configure the first network device it finds
init_net:

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_net
	call os_debug_string
%endif

	; Firecracker
	call net_virtio_mmio_init
	mov byte [os_NetEnabled], 1	; A supported NIC was found. Set flag in the kernel that networking is enabled
	add byte [os_net_icount], 1	; Increment the counter
	jmp init_net_end		; Only 1 NIC at the moment

;init_net_probe_found_finish:
;	mov byte [os_NetEnabled], 1	; A supported NIC was found. Set flag in the kernel that networking is enabled
;	add r9, 15			; Add offset to driver enabled byte
;	mov byte [r9], 1		; Mark device as having a driver
;	add byte [os_net_icount], 1
;	cmp byte [os_net_icount], 2	; Have 2 NIC's been activated?
;	je init_net_end			; If so, bail out as 2 is the max at the moment
;	jmp init_net_check_bus		; Check for another network device

init_net_probe_not_found:

init_net_end:

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_ok
	call os_debug_string
%endif

	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
