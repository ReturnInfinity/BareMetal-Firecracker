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
KERNELSIZE equ 0xDF000			; Pad the kernel to this length (0xE0000 - 0x1000)


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

	; Set the stack
	mov rax, [os_StackBase]		; The stack decrements when you "push", start at 64 KiB in
	add rax, 65536			; 64 KiB Stack
	mov rsp, rax
	mov rbp, rax

	; Enable interrupts on BSP
	sti

; TODO - Move the following code to payload.asm
; ============================================================================

	; Check payload
	cmp dword [os_MemAmount], 0	; Check for existence of App RAM
	je start_monitor
	cmp qword [0x200000], 0		; Check if something is in App RAM
	je start_monitor
	cmp dword [0x200000], 0x464C457F	; EI_MAG[0-3] - 0x7F, 'E', 'L', 'F'
	je start_elf_app

	; If there is data in App RAM and it doesn't match the ELF magic then treat it as a flat binary
start_flat_app:
	mov esi, msg_payload_start
	call os_debug_string
	call [app_start]		; Execute app
	mov esi, msg_payload_end
	call os_debug_string
	jmp shutdown

	; If it matched the ELF magic then treat it as such
	; https://github.com/torvalds/linux/blob/master/include/uapi/linux/elf.h
	; https://github.com/corkami/pics/blob/master/binary/elf101/elf101-64.pdf
	;
	; ELF Header
	;
	; e_ident	0x00 - 16 bytes
	; 	EI_MAG		0x00 - 4 bytes
	;	EI_CLASS	0x04 - 1 byte
	;	EI_DATA		0x05 - 1 byte
	;	EI_VERSION	0x06 - 1 byte
	;	padding		0x07 - 9 bytes
	; e_type	0x10 - 2 bytes
	; e_machine	0x12 - 2 bytes
	; e_version	0x14 - 4 bytes
	; e_entry	0x18 - 8 bytes
	; e_phoff	0x20 - 8 bytes
	; e_shoff	0x28 - 8 bytes
	; padding	0x30 - 4 bytes
	; e_ehsize	0x34 - 2 bytes
	; e_phentsize	0x36 - 2 bytes
	; e_phnum	0x38 - 2 bytes
	; e_shentsize	0x3A - 2 bytes
	; e_shnum	0x3C - 2 bytes
	; e_shstrndx	0x3E - 2 bytes
	;
	; Program Header Entries
	; Hex values below are the offsets into the entry
	;
	; p_type	0x00 - 4 bytes
	; p_flags	0x04 - 4 bytes
	; p_offset	0x08 - 8 bytes
	; p_vaddr	0x10 - 8 bytes
	; p_paddr	0x18 - 8 bytes
	; p_filesz	0x20 - 8 bytes
	; p_memsz	0x28 - 8 bytes

start_elf_app:
;	; Debug to show elf header
;	push rsi
;	push rcx
;	mov rsi, 0xFFFF800000000000
;	mov ecx, 100
;	call os_debug_dump_mem
;	pop rcx
;	pop rsi

	; Verify the rest of e_ident
	cmp word [0x200004], 0x0102	; EI_CLASS = 2 (64-bit), EI_DATA = 1 (Little endian)
	jne shutdown

	; Verify e_type = 2 (executable) and e_machine = 0x3E (64-bit x86)
	cmp dword [0x200010], 0x003E0002
	jne shutdown

	mov esi, msg_payload_start
	call os_debug_string

	mov esi, msg_payload_start_elf	; Debug
	call os_debug_string

	mov ebx, 0x00200000		; Physical base of the loaded ELF image
	mov r11, 0xFFFF800000000000	; Virtual base of the loaded ELF image
	mov r12, [rbx+0x18]		; Elf Header -> e_entry - Address where execution starts

	mov rsi, [rbx+0x20]		; Elf Header -> e_phoff - Program headers offset
	add rsi, rbx			; RSI -> physical program header table
	movzx r9, word [rbx+0x38]	; Elf Header -> e_phnum - Count of program headers
	movzx r10, word [rbx+0x36]	; Elf Header -> e_phentsize - Size of a single program header

	; Copy the program header table onto the stack before copying any PT_LOAD segment
	; The ELF Header and Program Header Table will be overwritten in memory
	; TODO - Can we build an ELF where e_entry points to the actual code start?
	mov rax, r9
	mul r10				; RDX:RAX = e_phnum * e_phentsize (phdr table size)
	mov r13, rax
	sub rsp, rax
	mov rdi, rsp
	mov r8, rdi			; R8 -> stack copy of the program header table
	mov rcx, rax
	rep movsb

elf_load_phdr:
	cmp r9, 0
	je elf_load_run
	cmp dword [r8], 1		; Program Header -> p_type = PT_LOAD?
	jne elf_load_next

	mov rsi, [r8+0x08]		; p_offset - Offset where it should be read
	add rsi, rbx			; RSI -> physical source (segment's file-backed bytes)
	mov rdi, [r8+0x10]		; Program Header -> p_vaddr - Virtual address where it should be loaded
	sub rdi, r11			; Rebase off the higher-half image base
	add rdi, rbx			; RDI -> physical destination
	mov rcx, [r8+0x20]		; Program Header -> p_filesz - Size on file
	push rdi
	push rcx
	rep movsb			; Copy the segment's file-backed bytes

	pop rcx				; Program Header -> p_filesz - Size on file
	pop rdi
	add rdi, rcx			; RDI -> end of file-backed data, start of the BSS tail
	mov rcx, [r8+0x28]		; Program Header -> p_memsz - Size in memory
	sub rcx, [r8+0x20]		; RCX = p_memsz - p_filesz (BSS bytes still needing a zero-fill)
	xor eax, eax
	rep stosb			; Zero-fill BSS (skips if RCX is already 0)

elf_load_next:
	add r8, r10
	dec r9
	jmp elf_load_phdr

elf_load_run:
	add rsp, r13			; Clear the phdr table snapshot

;	; Debug to show elf program
;	push rsi
;	push rcx
;	mov rsi, 0xFFFF800000000000
;	mov ecx, 100
;	call os_debug_dump_mem
;	pop rcx
;	pop rsi

	call r12			; Execute app (Elf Header e_entry)
	mov esi, msg_payload_end
	call os_debug_string
	jmp shutdown

start_monitor:
	call 0x1E0000			; Execute monitor

; ============================================================================

shutdown:
	; Shut down the system
	jmp b_system_shutdown

; Includes
%include "init.asm"
%include "syscalls.asm"
%include "drivers.asm"
%include "interrupt.asm"
%include "sysvar.asm"			; Include this last to keep the read/write variables away from the code

EOF:
	db 0xDE, 0xAD, 0xC0, 0xDE

times KERNELSIZE-($-$$) db 0x00		; Set the compiled kernel binary to at least this size in bytes


; =============================================================================
; EOF
