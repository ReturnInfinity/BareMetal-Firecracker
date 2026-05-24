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
; serial_recv -- Receives a character via the configured serial port
;  IN:	Nothing
; OUT:	AL = Character received, 0 if no character
serial_recv:
	push rdx

	; Check if serial port has pending data
	mov dx, COM_PORT_LINE_STATUS
	in al, dx
	and al, 0x01			; Bit 0
	cmp al, 0
	je serial_recv_nochar

	; Read from the serial port
	mov dx, COM_PORT_DATA
	in al, dx
	cmp al, 0x0D			; Enter via serial?
	je serial_recv_enter
	cmp al, 0x7F			; Backspace via serial?
	je serial_recv_backspace

serial_recv_done:
	pop rdx
	ret

serial_recv_nochar:
	xor al, al
	pop rdx
	ret

serial_recv_enter:
	mov al, 0x1C			; Adjust it to the same value as a keyboard
	jmp serial_recv_done
serial_recv_backspace:
	mov al, 0x0E			; Adjust it to the same value as a keyboard
	jmp serial_recv_done
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; serial_interrupt -- Receives a character via the configured serial port
serial_interrupt:
	push rdx
	push rax
serial_interrupt_check_iir:
	mov dx, COM_PORT_INTERRUPT_ID
	in al, dx
	test al, 1		; bit 0 = 0 means interrupt pending
	jnz serial_interrupt_done	; bit 0 = 1 means no more interrupts
	and al, 0x0E		; Isolate interrupt ID bits
	cmp al, 0x04		; Received Data Available
	je serial_interrupt_recv_data
	cmp al, 0x0C		; Character Timeout
	je serial_interrupt_recv_data
	cmp al, 0x06		; Receiver Line Status. Clear by reading LSR
	je serial_interrupt_line_status
	cmp al, 0x00		; Modem Status - clear by reading MSR
	je serial_interrupt_modem_status
	jmp serial_interrupt_check_iir
serial_interrupt_recv_data:
	call serial_recv	; TODO this checks line status again
	mov [key], al
	jmp serial_interrupt_check_iir
serial_interrupt_line_status:
	mov dx, COM_PORT_LINE_STATUS
	in al, dx		; Reading LSR clears the interrupt
	jmp serial_interrupt_check_iir
serial_interrupt_modem_status:
	mov dx, COM_PORT_MODEM_STATUS
	in al, dx		; Reading MSR clears the interrupt
	jmp serial_interrupt_check_iir

serial_interrupt_done:
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
