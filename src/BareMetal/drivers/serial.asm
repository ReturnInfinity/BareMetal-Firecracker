; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Serial Functions
; =============================================================================


; -----------------------------------------------------------------------------
; serial_init -- Enable interrupts
serial_init:

	; Set flag that Serial was enabled
	or qword [os_SysConfEn], 1 << 2

	; Configure interrupt handler
	mov edi, 0x24
	mov eax, int_serial
	call create_gate

	; Enable specific interrupts
	mov ecx, 4			; Serial IRQ
	mov eax, 0x24			; Serial Interrupt Vector
	call os_ioapic_mask_clear

	; Enable serial port interrupts
	mov dx, COM_PORT_INTERRUPT_ENABLE
	mov al, 1			; Set bit 0 for Received Data Available
	out dx, al

	mov eax, b_output_serial
	mov [0x100018], rax		; Set kernel b_output to the serial port

	mov dx, COM_PORT_INTERRUPT_ID	; Clear existing interrupt if any?
	in al, dx

serial_init_error:
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; serial_send -- Send a character via the configured serial port
;  IN:	AL = Character to send
; OUT:	All registers preserved
serial_send:
	push rdx
	push rax

serial_send_wait:
	mov dx, COM_PORT_LINE_STATUS
	in al, dx
	and al, 0x20			; Bit 5
	cmp al, 0
	je serial_send_wait

	; Restore the byte and write to the serial port
	pop rax
	mov dx, COM_PORT_DATA
	out dx, al

	pop rdx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; serial_recv -- Pull the next character from the serial ring buffer
;  IN:	Nothing
; OUT:	AL = Next character from ring buffer, 0 if no character available
;	All other registers preserved
serial_recv:
	push rbx

	movzx ebx, byte [serial_rb_head]
	mov al, [serial_rb_tail]
	cmp bl, al			; If head equals tail then buffer is empty
	je serial_recv_empty		; Bail out if so

	mov al, [serial_rb + rbx]	; Read character at head
	inc bl				; Advance head (wraps back to zero on its own)
	mov [serial_rb_head], bl	; Store it

	pop rbx
	ret

serial_recv_empty:
	xor al, al
	pop rbx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; serial_interrupt -- Receives characters into the serial ring buffer
serial_interrupt:
	push rdx
	push rax
	push rbx
	push rcx

serial_interrupt_check_iir:
	mov dx, COM_PORT_INTERRUPT_ID
	in al, dx
	test al, 1			; bit 0 = 0 means interrupt pending
	jnz serial_interrupt_done	; bit 0 = 1 means no more interrupts
	and al, 0x0E			; Isolate interrupt ID bits
	cmp al, 0x04			; Received Data Available
	je serial_interrupt_recv_data
	cmp al, 0x0C			; Character Timeout
	je serial_interrupt_recv_data
	cmp al, 0x06			; Receiver Line Status - clear by reading LSR
	je serial_interrupt_line_status
	cmp al, 0x00			; Modem Status - clear by reading MSR
	je serial_interrupt_modem_status
	jmp serial_interrupt_check_iir

serial_interrupt_recv_data:
	mov dx, COM_PORT_LINE_STATUS
	in al, dx
	test al, 0x01			; Bit 0 = Data Ready
	jz serial_interrupt_check_iir	; No more data, check IIR for other interrupts
	mov dx, COM_PORT_DATA
	in al, dx
	cmp al, 0x0D			; Enter via serial?
	je serial_interrupt_recv_enter
	cmp al, 0x7F			; Backspace via serial?
	je serial_interrupt_recv_backspace

serial_interrupt_recv_store:
	movzx rbx, byte [serial_rb_tail]
	mov cl, bl
	inc cl				; Next tail position (wraps as byte)
	cmp cl, [serial_rb_head]	; Full when next tail == head
	je serial_interrupt_recv_data	; Drop character but keep draining
	mov [serial_rb + rbx], al
	mov [serial_rb_tail], cl
	jmp serial_interrupt_recv_data	; Check LSR for more data

serial_interrupt_recv_enter:
	mov al, 0x1C			; Adjust to match keyboard scancode
	jmp serial_interrupt_recv_store

serial_interrupt_recv_backspace:
	mov al, 0x0E			; Adjust to match keyboard scancode
	jmp serial_interrupt_recv_store

serial_interrupt_line_status:
	mov dx, COM_PORT_LINE_STATUS
	in al, dx			; Reading LSR clears the interrupt
	jmp serial_interrupt_check_iir

serial_interrupt_modem_status:
	mov dx, COM_PORT_MODEM_STATUS
	in al, dx			; Reading MSR clears the interrupt
	jmp serial_interrupt_check_iir

serial_interrupt_done:
	pop rcx
	pop rbx
	pop rax
	pop rdx
	ret
; -----------------------------------------------------------------------------


; Port Registers
COM_BASE			equ 0x3F8
COM_PORT_DATA			equ COM_BASE + 0
COM_PORT_INTERRUPT_ENABLE	equ COM_BASE + 1
COM_PORT_FIFO_CONTROL		equ COM_BASE + 2 ; WRITE
COM_PORT_INTERRUPT_ID		equ COM_BASE + 2 ; READ
COM_PORT_LINE_CONTROL		equ COM_BASE + 3
COM_PORT_MODEM_CONTROL		equ COM_BASE + 4
COM_PORT_LINE_STATUS		equ COM_BASE + 5
COM_PORT_MODEM_STATUS		equ COM_BASE + 6
COM_PORT_SCRATCH_REGISTER	equ COM_BASE + 7

; Baud Rates
BAUD_115200			equ 1
BAUD_57600			equ 2
BAUD_9600			equ 12
BAUD_300			equ 384


; =============================================================================
; EOF
