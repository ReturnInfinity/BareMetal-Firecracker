; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; The BareMetal exokernel
; =============================================================================


BITS 64					; Specify 64-bit
ORG 0x0000000000100000			; The kernel needs to be loaded at this address
DEFAULT ABS

%DEFINE BAREMETAL_VER 'v1.0.0 (January 21, 2020)', 13, 'Copyright (C) 2008-2026 Return Infinity', 13, 0
%DEFINE BAREMETAL_API_VER 1
KERNELSIZE equ 8 * 1024			; Pad the kernel to this length


kernel_start:
	jmp start			; Skip over the function call index
	nop
	db 'BAREMETAL'			; Kernel signature

align 16
	dq b_input			; 0x0010
	dq b_output			; 0x0018
	dq b_net_tx			; 0x0020
	dq b_net_rx			; 0x0028
	dq b_nvs_read			; 0x0030
	dq b_nvs_write			; 0x0038
	dq b_system			; 0x0040
	dq b_user			; 0x0048

align 16
start:
	mov rsp, 0x10000		; Set the temporary stack

	; System and driver initialization
	call init_64			; After this point we are in a working 64-bit environment
	call init_bus			; Initialize system busses
	call init_nvs			; Initialize non-volatile storage
	call init_net			; Initialize network
	call init_hid			; Initialize human interface devices
	call init_sys			; Initialize system

	sti
	; Set the stack
	mov rax, [os_StackBase]		; The stack decrements when you "push", start at 64 KiB in
	add rax, 65536			; 64 KiB Stack
	mov rsp, rax
	mov rbp, rax
	jmp 0x1E0000

; Includes
%include "init.asm"
%include "syscalls.asm"
%include "drivers.asm"
%include "interrupt.asm"
%include "sysvar.asm"			; Include this last to keep the read/write variables away from the code

EOF:
	db 0xDE, 0xAD, 0xC0, 0xDE

times KERNELSIZE-($-$$) db 0x90		; Set the compiled kernel binary to at least this size in bytes


; =============================================================================
; EOF
