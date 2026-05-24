; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Virtio MMIO Bus Driver
; =============================================================================


; -----------------------------------------------------------------------------
; virtio_mmio_init --
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


; =============================================================================
; EOF
