; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; PS/2 Keyboard Functions
; =============================================================================


; -----------------------------------------------------------------------------
; ps2_init -- Enables interrupts
ps2_init:

	; Create the entry in the IDT
	mov edi, 0x21
	mov eax, int_keyboard
	call create_gate

	; Enable specific interrupt
	mov ecx, 1			; Keyboard IRQ
	mov eax, 0x21			; Keyboard Interrupt Vector
	call os_ioapic_mask_clear

	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; ps2_keyboard_interrupt -- Converts scan code from keyboard to character
ps2_keyboard_interrupt:
	push rbx
	push rax

	xor eax, eax

	; Firecracker only uses the keyboard to send a Crtl-Alt-Del
	; 0x14 - Left Control Pressed
	; 0x11 - Left Alt Pressed
	; 0xE0, 0x71 - Delete Pressed
	; Since that is all that should be expected we can just shut down
	; as soon as a Left Control comes in
	in al, PS2_DATA			; Get the scan code from the keyboard
	cmp al, 0x14			; Firecracker sends this on a Ctrl-Alt-Del
	je b_system_shutdown

	pop rax
	pop rbx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; ps2_send_cmd -- Send a single byte command to the PS/2 Controller
;  IN:	AL = Command to send
; OUT:	Nothing
ps2_send_cmd:
	call ps2_wait			; Wait if a command is still in process
	out PS2_CMD, al			; Send the command
	call ps2_wait			; Wait for the command to be completed
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; ps2_wait -- Wait for the PS/2 Controller input buffer to be empty
;  IN:	Nothing
; OUT:	Nothing
ps2_wait:
	push rax
ps2_wait_read:
	in al, PS2_STATUS		; Read Status Register
	bt ax, 1			; Check if Input buffer is full
	jc ps2_wait_read
	pop rax
	ret
; -----------------------------------------------------------------------------


; PS/2 Ports
PS2_DATA		equ 0x60 ; Data Port - Read/Write
PS2_STATUS		equ 0x64 ; Status Register - Read
PS2_CMD			equ 0x64 ; Command Register - Write

; PS/2 Status Codes
PS2_STATUS_ACK		equ 0xFA
PS2_STATUS_RESEND	equ 0xFE
PS2_STATUS_ERROR	equ 0xFC

; PS/2 Status Bits
PS2_STATUS_OUTPUT	equ 0 ; Output buffer status (0 = empty, 1 = full)
PS2_STATUS_INPUT	equ 1 ; Input buffer status (0 = empty, 1 = full)
PS2_STATUS_FLAG		equ 2 ; System Flag. Should be set to 1 by system firmware
PS2_STATUS_COMMAND	equ 3 ; Command/data (0 = data written to input is for PS/2 device, 1 = data written to input is for PS/2 controller)
PS2_STATUS_BIT4		equ 4 ; ???
PS2_STATUS_BIT5		equ 5 ; ???
PS2_STATUS_TIMEOUT	equ 6 ; Time-out error (0 = no error, 1 = time-out error)
PS2_STATUS_PARITY	equ 7 ; Parity error (0 = no error, 1 = parity error)

; PS/2 Controller Configuration Bits
PS2_CCB_KBD_INT		equ 0 ; First PS/2 port interrupt (1 = enabled, 0 = disabled)
PS2_CCB_AUX_INT		equ 1 ; Second PS/2 port interrupt (1 = enabled, 0 = disabled, only if 2 PS/2 ports supported)
PS2_CCB_SYSFLAG		equ 2 ; System Flag (1 = system passed POST, 0 = your OS shouldn't be running)
PS2_CCB_BIT3		equ 3 ; ???
PS2_CCB_KBD_CLK		equ 4 ; First PS/2 port clock (1 = disabled, 0 = enabled)
PS2_CCB_AUX_CLK		equ 5 ; Second PS/2 port clock (1 = disabled, 0 = enabled, only if 2 PS/2 ports supported)
PS2_CCB_KBD_TRANS	equ 6 ; First PS/2 port translation (1 = enabled, 0 = disabled)
PS2_CCB_BIT7		equ 7 ; ???

; PS/2 Controller Commands
PS2_RD_CCB		equ 0x20 ; Read byte 0 of the PS/2 Controller Configuration Byte
PS2_WR_CCB		equ 0x60 ; Write byte 0 of the PS/2 Controller Configuration Byte
PS2_AUX_DIS		equ 0xA7 ; Disable Auxiliary Device
PS2_AUX_EN		equ 0xA8 ; Enable Auxiliary Device
PS2_CTRL_TEST		equ 0xAA ; Test PS/2 Controller
PS2_KBD_TEST		equ 0xAB ; Test first PS/2 port
PS2_KBD_DIS		equ 0xAD ; Disable first PS/2 port
PS2_KBD_EN		equ 0xAE ; Enable first PS/2 port
PS2_AUX_WRITE		equ 0xD4 ; Write to Auxiliary Device
PS2_RESET_CPU		equ 0xFE ; Reset the CPU

; PS/2 Keyboard Commands
PS2_KBD_SET_LEDS	equ 0xED
PS2_KBD_SCANSET		equ 0xF0
PS2_KBD_RATE		equ 0xF3
PS2_KBD_ENABLE		equ 0xF4


; =============================================================================
; EOF
