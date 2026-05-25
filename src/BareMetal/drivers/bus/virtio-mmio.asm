; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Virtio MMIO Bus Driver
; =============================================================================


; -----------------------------------------------------------------------------
; virtio_mmio_init -- Process virtio devices passed by init
virtio_mmio_init:
	mov rsi, 0x5800

virtio_mmio_init_search:
	lodsd					; Load the base address
	cmp eax, 0xffffffff			; Check for end of list
	je virtio_mmio_init_end			; If end, bail out

	; Check that it is a valid device
	cmp dword [rax], 0x74726976		; MagicValue - "virt"
	jne virtio_mmio_init_skip
	cmp dword [rax + 4], 2			; Version (1 = legacy, 2 = modern)
	jne virtio_mmio_init_skip
	cmp dword [rax + 8], 1			; DeviceID (1 = net, 2 = blk)
	je virtio_mmio_init_found_net
	cmp dword [rax + 8], 2			; DeviceID (1 = net, 2 = blk)
	je virtio_mmio_init_found_blk

virtio_mmio_init_skip:
	lodsd					; Load the IRQ
	jmp virtio_mmio_init_search

virtio_mmio_init_found_net:
	mov [os_virtionet_base], rax		; Save it as the base
	lodsd					; Load the IRQ
	mov [virtio_net_irq], eax
	jmp virtio_mmio_init_search

virtio_mmio_init_found_blk:
	mov [os_virtioblk_base], rax		; Save it as the base
	lodsd					; Load the IRQ
	jmp virtio_mmio_init_search

virtio_mmio_init_end:
	ret
; -----------------------------------------------------------------------------


; VIRTIO MMIO Common Registers
VIRTIO_MMIO_MAGIC			equ 0x00 ; 32-bit read-only
VIRTIO_MMIO_VERSION			equ 0x04 ; 32-bit read-only
VIRTIO_MMIO_DEVICEID			equ 0x08 ; 32-bit read-only
VIRTIO_MMIO_VENDORID			equ 0x0C ; 32-bit read-only
VIRTIO_MMIO_DEVICE_FEATURES		equ 0x10 ; 32-bit read-only
VIRTIO_MMIO_DEVICE_FEATURES_SELECT	equ 0x14 ; 32-bit
VIRTIO_MMIO_DRIVER_FEATURES		equ 0x20 ; 32-bit
VIRTIO_MMIO_DRIVER_FEATURES_SELECT	equ 0x24 ; 32-bit
VIRTIO_MMIO_QUEUE_SELECT		equ 0x30 ; 32-bit
VIRTIO_MMIO_QUEUE_NUMMAX		equ 0x34 ; 32-bit read-only
VIRTIO_MMIO_QUEUE_NUM			equ 0x38 ; 32-bit
VIRTIO_MMIO_QUEUE_READY			equ 0x44 ; 32-bit
VIRTIO_MMIO_QUEUE_NOTIFY		equ 0x50 ; 32-bit
VIRTIO_MMIO_INT_STATUS			equ 0x60 ; 32-bit
VIRTIO_MMIO_INT_ACK			equ 0x64 ; 32-bit
VIRTIO_MMIO_STATUS			equ 0x70 ; 32-bit
VIRTIO_MMIO_QUEUE_DESC			equ 0x80 ; 32-bit
VIRTIO_MMIO_QUEUE_DESC_LOW		equ 0x80 ; 32-bit
VIRTIO_MMIO_QUEUE_DESC_HIGH		equ 0x84 ; 32-bit
VIRTIO_MMIO_QUEUE_DRIVER		equ 0x90 ; 32-bit
VIRTIO_MMIO_QUEUE_DRIVER_LOW		equ 0x90 ; 32-bit
VIRTIO_MMIO_QUEUE_DRIVER_HIGH		equ 0x94 ; 32-bit
VIRTIO_MMIO_QUEUE_DEVICE		equ 0xA0 ; 32-bit
VIRTIO_MMIO_QUEUE_DEVICE_LOW		equ 0xA0 ; 32-bit
VIRTIO_MMIO_QUEUE_DEVICE_HIGH		equ 0xA4 ; 32-bit
VIRTIO_MMIO_QUEUE_RESET			equ 0xC0 ; 32-bit
VIRTIO_MMIO_CONFIG_SPACE		equ 0x100

; VIRTIO_STATUS Values
VIRTIO_STATUS_FAILED			equ 0x80 ; Indicates that something went wrong in the guest, and it has given up on the device
VIRTIO_STATUS_DEVICE_NEEDS_RESET	equ 0x40 ; Indicates that the device has experienced an error from which it can’t recover
VIRTIO_STATUS_FEATURES_OK		equ 0x08 ; Indicates that the driver has acknowledged all the features it understands, and feature negotiation is complete
VIRTIO_STATUS_DRIVER_OK			equ 0x04 ; Indicates that the driver is set up and ready to drive the device
VIRTIO_STATUS_DRIVER			equ 0x02 ; Indicates that the guest OS knows how to drive the device
VIRTIO_STATUS_ACKNOWLEDGE		equ 0x01 ; Indicates that the guest OS has found the device and recognized it as a valid virtio device.


; =============================================================================
; EOF
