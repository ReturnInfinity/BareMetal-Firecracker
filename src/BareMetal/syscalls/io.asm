; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Input/Output Functions
; =============================================================================


; -----------------------------------------------------------------------------
; b_input -- Returns a byte of input
;  IN:	Nothing
; OUT:	AL = 0 if no byte, otherwise ASCII code, other regs preserved
;	All other registers preserved
b_input:
	call serial_recv
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; b_output -- Outputs characters via kernel call
;  IN:	RSI = Memory address of message (non zero-terminated)
;	RCX = number of chars to output
; OUT:	All registers preserved
b_output:
	call [0x00100018]		; Call kernel function in table
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; b_output_serial -- Outputs characters via serial
;  IN:	RSI = Memory address of message (non zero-terminated)
;	ECX = number of chars to output
; OUT:	All registers preserved
b_output_serial:
	push rsi
	push rcx
	push rax

b_output_serial_next:
	lodsb				; Load a byte from the string into AL
	cmp al, 3			; Check for Decrement cursor
	je b_output_serial_decrement
	cmp al, 10			; Check for Line Feed
	jne b_output_serial_send
	mov al, 13			; Carriage Return
	call serial_send
	mov al, 10
b_output_serial_send:
	call serial_send		; Output it via serial
	dec ecx				; Decrement the counter
	jnz b_output_serial_next	; Loop if counter isn't zero

	pop rax
	pop rcx
	pop rsi
	ret

b_output_serial_decrement:
	mov al, 8			; Backspace
	jmp b_output_serial_send
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
