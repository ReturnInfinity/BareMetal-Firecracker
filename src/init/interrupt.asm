; =============================================================================
; BareMetal Firecracker Init
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Interrupts
; =============================================================================


; -----------------------------------------------------------------------------
; Default exception handler
align 8
exception_gate:
;	mov esi, int_string00
;	call b_output
;	mov esi, exc_string
;	call b_output
	jmp $				; Hang
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; Default interrupt handler
align 8
interrupt_gate:				; handler for all other interrupts
	iretq				; It was an undefined interrupt so return to caller
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; CPU Exception Gates
align 8
exception_gate_00:			; DE (Division Error)
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x00
	jmp exception_gate_main

align 8
exception_gate_01:			; DB
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x01
	jmp exception_gate_main

align 8
exception_gate_02:
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x02
	jmp exception_gate_main

align 8
exception_gate_03:			; BP
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x03
	jmp exception_gate_main

align 8
exception_gate_04:			; OF
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x04
	jmp exception_gate_main

align 8
exception_gate_05:			; BR
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x05
	jmp exception_gate_main

align 8
exception_gate_06:			; UD (Invalid Opcode)
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x06
	jmp exception_gate_main

align 8
exception_gate_07:			; NM
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x07
	jmp exception_gate_main

align 8
exception_gate_08:			; DF
	push rax
	mov al, 0x08
	jmp exception_gate_main
	times 16 db 0x90

align 8
exception_gate_09:
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x09
	jmp exception_gate_main

align 8
exception_gate_10:			; TS
	push rax
	mov al, 0x0A
	jmp exception_gate_main
	times 16 db 0x90

align 8
exception_gate_11:			; NP
	push rax
	mov al, 0x0B
	jmp exception_gate_main
	times 16 db 0x90

align 8
exception_gate_12:			; SS
	push rax
	mov al, 0x0C
	jmp exception_gate_main
	times 16 db 0x90

align 8
exception_gate_13:			; GP
	push rax
	mov al, 0x0D
	jmp exception_gate_main
	times 16 db 0x90

align 8
exception_gate_14:			; PF (Page Fault)
	; An error code is store in RAX (EAX padded)
	; Register CR2 is set to the virtual address which caused the Page Fault
	push rax
	mov al, 0x0E
	jmp exception_gate_main
	times 16 db 0x90

align 8
exception_gate_15:
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x0F
	jmp exception_gate_main

align 8
exception_gate_16:			; MF
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x10
	jmp exception_gate_main

align 8
exception_gate_17:			; AC
	push rax
	mov al, 0x11
	jmp exception_gate_main
	times 16 db 0x90

align 8
exception_gate_18:			; MC
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x12
	jmp exception_gate_main

align 8
exception_gate_19:			; XM
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x13
	jmp exception_gate_main

align 8
exception_gate_20:			; VE
	mov [rsp-16], rax
	xor eax, eax
	mov [rsp-8], rax
	sub rsp, 16
	mov al, 0x14
	jmp exception_gate_main


; -----------------------------------------------------------------------------
; Main exception handler
align 8
exception_gate_main:
	; Display exception message, APIC ID, and exception type
	push rbx
	push rdi
	push rsi
	push rcx			; Char counter for b_output
	push rax			; Save RAX since b_smp_get_id clobbers it
	call debug_newline
	mov esi, int_string00
	call debug_msg
	mov eax, 0
;	call b_smp_get_id		; Get the local CPU ID and print it
	call debug_dump_eax
	mov esi, int_string01
	call debug_msg
	mov esi, exc_string00
	pop rax

	and eax, 0x00000000000000FF	; Clear out everything in RAX except for AL
	push rax
	mov bl, 8			; Length of each message
	mul bl				; AX = AL x BL
	add rsi, rax			; Use the value in RAX as an offset to get to the right message
	pop rax
	mov bl, 0x0F
	call debug_msg
	pop rcx
	pop rsi
	pop rdi
	pop rbx
	pop rax

	; Dump all registers
	push r15
	push r14
	push r13
	push r12
	push r11
	push r10
	push r9
	push r8
	push rsp
	push rbp
	push rdi
	push rsi
	push rdx
	push rcx
	push rbx
	push rax
	mov esi, reg_string00		; Load address of first register string
	mov edx, 16			; Counter of registers to left to output
	xor ebx, ebx			; Counter of registers output per line
	call debug_newline
exception_gate_main_nextreg:
	call debug_msg
	add esi, 6
	pop rax
	call debug_dump_rax
	add ebx, 1
	cmp ebx, 4			; Number of registers to output per line
	jne exception_gate_main_nextreg_space
	call debug_newline
	xor ebx, ebx
	jmp exception_gate_main_nextreg_continue
exception_gate_main_nextreg_space:
	call debug_space
exception_gate_main_nextreg_continue:
	dec edx
	jnz exception_gate_main_nextreg
	call debug_msg
	mov rax, [rsp+8] 		; RIP of caller
	call debug_dump_rax
	call debug_space
	add esi, 6
	call debug_msg
	mov rax, cr2
	call debug_dump_rax
	call debug_newline

	jmp shutdown
; -----------------------------------------------------------------------------


int_string00 db 'CPU 0x', 0
int_string01 db ' - Exception 0x', 0
; Strings for the error messages
exc_string db 'Unknown Fatal Exception!', 0
exc_string00 db '00 (DE)', 0
exc_string01 db '01 (DB)', 0
exc_string02 db '02     ', 0
exc_string03 db '03 (BP)', 0
exc_string04 db '04 (OF)', 0
exc_string05 db '05 (BR)', 0
exc_string06 db '06 (UD)', 0
exc_string07 db '07 (NM)', 0
exc_string08 db '08 (DF)', 0
exc_string09 db '09     ', 0	; No longer generated on new CPU's
exc_string10 db '10 (TS)', 0
exc_string11 db '11 (NP)', 0
exc_string12 db '12 (SS)', 0
exc_string13 db '13 (GP)', 0
exc_string14 db '14 (PF)', 0
exc_string15 db '15     ', 0
exc_string16 db '16 (MF)', 0
exc_string17 db '17 (AC)', 0
exc_string18 db '18 (MC)', 0
exc_string19 db '19 (XM)', 0
exc_string20 db '20 (VE)', 0

; Strings for registers
reg_string00 db 'RAX= ', 0
reg_string01 db 'RBX= ', 0
reg_string02 db 'RCX= ', 0
reg_string03 db 'RDX= ', 0
reg_string04 db 'RSI= ', 0
reg_string05 db 'RDI= ', 0
reg_string06 db 'RBP= ', 0
reg_string07 db 'RSP= ', 0
reg_string08 db 'R8 = ', 0
reg_string09 db 'R9 = ', 0
reg_string10 db 'R10= ', 0
reg_string11 db 'R11= ', 0
reg_string12 db 'R12= ', 0
reg_string13 db 'R13= ', 0
reg_string14 db 'R14= ', 0
reg_string15 db 'R15= ', 0
reg_string16 db 'RIP= ', 0
reg_string17 db 'CR2= ', 0


; =============================================================================
; EOF
