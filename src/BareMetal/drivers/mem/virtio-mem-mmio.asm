; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Virtio MMIO MEM Driver
; =============================================================================


; -----------------------------------------------------------------------------
; Initialize a Virtio MEM
mem_virtio_mmio_init:
	push rdi
	push rsi
	push rdx
	push rcx
	push rbx
	push rax

	; Check for a valid device
	mov rsi, [os_virtiomem_base]
	cmp rsi, 0
	je mem_virtio_mmio_init_done

	call mem_virtio_mmio_reset

mem_virtio_mmio_init_done:
	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rsi
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; mem_virtio_reset - Reset a Virtio MEM device
;  IN:	RDX = Interface ID
; OUT:	Nothing, all registers preserved
mem_virtio_mmio_reset:
	push rdi
	push rsi
	push rcx
	push rax

	mov rsi, [os_virtiomem_base]

;	block size (should match MEMHOTPLUG_BLOCK)
	mov rax, [rsi+0x100]
	call os_debug_dump_rax
	call os_debug_newline

;	addr
	mov rax, [rsi+0x110]
	call os_debug_dump_rax
	call os_debug_newline

;	region size (should match MEMHOTPLUG_MAX)
	mov rax, [rsi+0x118]
	call os_debug_dump_rax
	call os_debug_newline

;	usable region size
	mov rax, [rsi+0x120]
	call os_debug_dump_rax
	call os_debug_newline

;	plug size
	mov rax, [rsi+0x128]
	call os_debug_dump_rax
	call os_debug_newline

;	request size
	mov rax, [rsi+0x130]
	call os_debug_dump_rax
	call os_debug_newline

	; Device Initialization (section 3.1)

	; 3.1.1 - Step 1 -  Reset the device (section 2.4)
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_STATUS], eax
mem_virtio_mmio_reset_wait:
	mov eax, [rsi+VIRTIO_MMIO_STATUS]
	cmp eax, 0
	jne mem_virtio_mmio_reset_wait

	; 3.1.1 - Step 2 - Tell the device we see it
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE
	mov [rsi+VIRTIO_MMIO_STATUS], eax

	; 3.1.1 - Step 3 - Tell the device we support it
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER
	mov [rsi+VIRTIO_MMIO_STATUS], eax

	; 3.1.1 - Step 4
	; Process the first 32-bits of Feature bits
;	xor eax, eax
;	mov [rsi+VIRTIO_MMIO_DEVICE_FEATURES_SELECT], eax
;	mov eax, [rsi+VIRTIO_MMIO_DEVICE_FEATURES]
	; Returns 2000DDA3
;	xor eax, eax
;	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES_SELECT], eax
;	mov eax, 0x00010020		; Feature bits 31:0 - STATUS (16), MAC (5)
;	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES], eax
	; Process the next 32-bits of Feature bits
;	mov eax, 1
;	mov [rsi+VIRTIO_MMIO_DEVICE_FEATURES_SELECT], eax
;	mov eax, [rsi+VIRTIO_MMIO_DEVICE_FEATURES]
	; Returns ?
;	mov eax, 1
;	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES_SELECT], eax
;	; TODO - Check into how LEGACY affects the 12-byte header
;	mov eax, 1			; Feature bits 63:32 - LEGACY (32)
;	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES], eax

	; 3.1.1 - Step 5
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_FEATURES_OK
	mov [rsi+VIRTIO_MMIO_STATUS], eax

	; 3.1.1 - Step 6 - Re-read device status to make sure FEATURES_OK is still set
	mov eax, [rsi+VIRTIO_MMIO_STATUS]
	bt eax, 3			; VIRTIO_STATUS_FEATURES_OK
	jnc mem_virtio_mmio_reset_error

	; 3.1.1 - Step 7
	; Set up the device and the queues
	; discovery of virtqueues for the device
	; optional per-bus setup
	; reading and possibly writing the device’s virtio configuration space
	; population of virtqueues



	; 3.1.1 - Step 8 - At this point the device is “live”
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_DRIVER_OK | VIRTIO_STATUS_FEATURES_OK
	mov [rsi+VIRTIO_MMIO_STATUS], eax

	; Acknowledge any existing interrupt
	mov eax, [rsi+VIRTIO_MMIO_INT_STATUS]
	mov [rsi+VIRTIO_MMIO_INT_ACK], eax

mem_virtio_mmio_reset_done:
	pop rax
	pop rcx
	pop rsi
	pop rdi
	ret

mem_virtio_mmio_reset_error:
	; TODO Handle error
	jmp mem_virtio_mmio_reset_done
; -----------------------------------------------------------------------------


; VIRTQUEUE Descriptor Flags

; VIRTIO_MEM_DEVICE CONFIG
; le64 block_size
; le16 node_id
; le8 padding[6]
; le64 addr
; le64 region_size
; le64 usable_region_size
; le64 plugged_size
; le64 requested_size

; VIRTIO_DEVICEFEATURES bits
VIRTIO_MEM_F_ACPI_PXM			equ 0 ;
VIRTIO_MEM_F_UNPLUGGED_INACCESSIBLE	equ 1 ;
VIRTIO_MEM_F_PERSISTENT_SUSPEND		equ 2 ;

; VIRTQUEUES
VIRTIO_MEM_GUEST_REQUEST	equ 0	; The Request Queue


; =============================================================================
; EOF
