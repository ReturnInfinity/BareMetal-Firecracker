; =============================================================================
; BareMetal Firecracker Init
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Debug
; =============================================================================


init_debug:

	; Dump 4096 bytes of boot_params
	mov edi, boot_params_ptr
	mov esi, [edi]
	xor ecx, ecx
next_line:
	xor edx, edx
	call debug_newline
	mov eax, ecx
	call debug_dump_eax
	call debug_space
	call debug_space
next_byte:
	lodsb
	call debug_dump_al
	call debug_space
	inc ecx
	inc edx
	cmp edx, 16
	jne next_byte
	cmp ecx, 0x1000
	jne next_line
	call debug_newline


	; Verify boot_params as Firecracker sets them in src/vmm/src/arch/x86_64/mod.rs
	mov edi, boot_params_ptr
	mov esi, [edi]
	mov ax, [esi + BP_HDR_BOOT_FLAG]
	cmp ax, 0xAA55
	jne error
	mov eax, [esi + BP_HDR_HEADER]
	cmp eax, 0x53726448
	jne error
	mov eax, [esi + BP_HDR_TYPE_OF_LOADER]
	cmp al, 0xFF
	jne error
	mov eax, [esi + BP_HDR_LOADFLAGS]
	bt eax, 6		; KEEP_SEGMENTS - https://www.kernel.org/doc/Documentation/x86/boot.txt
	jc error

	; Dump the memory map
	xor ecx, ecx
	mov cl, [esi + BP_E820_ENTRIES]
	mov eax, ecx
	call debug_dump_eax
	call debug_newline
	mov eax, esi
	add eax, BP_E820_TABLE
	call debug_dump_eax
	call debug_newline
	mov esi, eax
dump_e820:
	lodsq			; Start of region (64-bit physical address)
	call debug_dump_rax
	call debug_space
	lodsq			; Length of region (64-bit bytes)
	call debug_dump_rax
	call debug_space
	lodsd			; Type of region (1 = usable, 2 = reserved, 3 = ACPI reclaimable, 4 = ACPI NVS)
	call debug_dump_eax
	call debug_newline
	dec ecx
	jnz dump_e820

	mov edi, boot_params_ptr
	mov ebx, [edi]


	; Inspect selected Linux boot protocol fields.

	mov esi, msg_boot_flag
	call debug_msg
	xor eax, eax
	mov ax, [ebx + BP_HDR_BOOT_FLAG]
	call debug_dump_ax
	call debug_newline

	mov esi, msg_header
	call debug_msg
	mov eax, [ebx + BP_HDR_HEADER]
	call debug_dump_eax
	call debug_newline

	mov esi, msg_e820_entries
	call debug_msg
	xor eax, eax
	mov al, [ebx + BP_E820_ENTRIES]
	call debug_dump_al
	call debug_newline

	; Output the physical address of the RSDP table
	mov esi, msg_rsdp
	call debug_msg
	mov rax, [ebx + BP_HDR_RSDP_ADDR]
	call debug_dump_rax
	mov esi, msg_newline
	call debug_msg

	mov esi, msg_cmdline_ptr
	call debug_msg
	mov eax, [ebx + BP_HDR_CMD_LINE_PTR]
	call debug_dump_eax
	mov esi, msg_newline
	call debug_msg

	mov esi, msg_ext_cmdline_ptr
	call debug_msg
	mov eax, [ebx + BP_EXT_CMD_LINE_PTR]
	call debug_dump_eax
	mov esi, msg_newline
	call debug_msg

	; Try to print the command line from hdr.cmd_line_ptr first.
	mov eax, [ebx + BP_HDR_CMD_LINE_PTR]
	test eax, eax
	jz .try_ext_cmdline

	mov esi, msg_cmdline
	call debug_msg
	mov esi, eax
	call debug_msg
	mov esi, msg_newline
	call debug_msg
	jmp end

.try_ext_cmdline:
	mov eax, [ebx + BP_EXT_CMD_LINE_PTR]
	test eax, eax
	jz .no_cmdline

	mov esi, msg_cmdline
	call debug_msg
	mov esi, eax
	call debug_msg
	mov esi, msg_newline
	call debug_msg
	jmp end

.no_cmdline:
	mov esi, msg_cmdline_none
	call debug_msg

end:

	ret

; -----------------------------------------------------------------------------
; debug_msg_char - Send a single char via the serial port
; IN: AL = Byte to send
debug_msg_char:
	pushf
	push rdx
	push rax			; Save the byte
	mov dx, 0x03F8			; Address of first serial port
debug_msg_char_wait:
	add dx, 5			; Offset to Line Status Register
	in al, dx
	sub dx, 5			; Back to to base
	and al, 0x20
	cmp al, 0
	je debug_msg_char_wait
	pop rax				; Restore the byte
	out dx, al			; Send the char to the serial port
debug_msg_char_done:
	pop rdx
	popf
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; debug_msg_char - Send a message via the serial port
; IN: RSI = Location of message, null terminated
debug_msg:
	pushf
	push rsi
	push rdx
	push rax
	cld				; Clear the direction flag.. we want to increment through the string
	mov dx, 0x03F8			; Address of first serial port
debug_msg_next:
	add dx, 5			; Offset to Line Status Register
	in al, dx
	sub dx, 5			; Back to to base
	and al, 0x20
	cmp al, 0
	je debug_msg_next
	lodsb				; Get char from string and store in AL
	cmp al, 0
	je debug_msg_done
	out dx, al			; Send the char to the serial port
	jmp debug_msg_next
debug_msg_done:
	pop rax
	pop rdx
	pop rsi
	popf
	ret
; -----------------------------------------------------------------------------

debug_space:
	push rsi
	mov rsi, msg_space
	call debug_msg
	pop rsi
	ret

debug_newline:
	push rsi
	mov rsi, msg_newline
	call debug_msg
	pop rsi
	ret

; -----------------------------------------------------------------------------
; debug_dump_(rax|eax|ax|al) -- Dump content of RAX, EAX, AX, or AL
;  IN:	RAX/EAX/AX/AL = content to dump
; OUT:	Nothing, all registers preserved
debug_dump_rax:
	rol rax, 8
	call debug_dump_al
	rol rax, 8
	call debug_dump_al
	rol rax, 8
	call debug_dump_al
	rol rax, 8
	call debug_dump_al
	rol rax, 32
debug_dump_eax:				; RAX is used here instead of EAX to preserve the upper 32-bits
	rol rax, 40
	call debug_dump_al
	rol rax, 8
	call debug_dump_al
	rol rax, 16
debug_dump_ax:
	rol ax, 8
	call debug_dump_al
	rol ax, 8
debug_dump_al:
	push rax			; Save RAX
	push ax				; Save AX for the low nibble
	shr al, 4			; Shift the high 4 bits into the low 4, high bits cleared
	or al, '0'			; Add "0"
	cmp al, '9'+1			; Digit?
	jl debug_dump_al_h		; Yes, store it
	add al, 7			; Add offset for character "A"
debug_dump_al_h:
	call debug_msg_char
	pop ax				; Restore AX
	and al, 0x0F			; Keep only the low 4 bits
	or al, '0'			; Add "0"
	cmp al, '9'+1			; Digit?
	jl debug_dump_al_l		; Yes, store it
	add al, 7			; Add offset for character "A"
debug_dump_al_l:
	call debug_msg_char
	pop rax				; Restore RAX
	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
