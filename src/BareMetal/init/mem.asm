; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Initialize hot-pluggable memory
; =============================================================================


; -----------------------------------------------------------------------------
; init_mem -- Configure the virtio-mem device, if Firecracker provided one
init_mem:

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_mem
	call os_debug_string
%endif

	call virtio_mem_mmio_init

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_ok
	call os_debug_string
%endif

	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
