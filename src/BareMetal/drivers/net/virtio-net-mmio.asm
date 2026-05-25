; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Virtio MMIO NIC Driver
; =============================================================================


; -----------------------------------------------------------------------------
; Initialize a Virtio NIC
net_virtio_mmio_init:
	push rdi
	push rsi
	push rdx
	push rcx
	push rbx
	push rax

	; Check for a valid device
	mov rsi, [os_virtionet_base]
	cmp rsi, 0
	je virtio_net_mmio_init_done

; Get the MAC address
	mov rdi, 0x11A000
	mov ax, 0x1AF4
	stosw
	add rdi, 6

	add esi, 0x100
	mov ecx, 6
	rep movsb

	add byte [os_net_icount], 1

	call net_virtio_mmio_reset

	; TODO - Get value below from init
	; Configure interrupt handler
	mov edi, 0x26
	mov eax, int_network
	call create_gate

	; Enable specific interrupts
	mov ecx, 6			; Network IRQ
	mov eax, 0x26			; Network Interrupt Vector
	call os_ioapic_mask_clear

virtio_net_mmio_init_done:
	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rsi
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; net_virtio_reset - Reset a Virtio NIC
;  IN:	RDX = Interface ID
; OUT:	Nothing, all registers preserved
net_virtio_mmio_reset:
	push rdi
	push rsi
	push rcx
	push rax

	mov rsi, [os_virtionet_base]

	; Device Initialization (section 3.1)

	; 3.1.1 - Step 1 -  Reset the device (section 2.4)
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_STATUS], eax
virtio_net_mmio_reset_wait:
	mov eax, [rsi+VIRTIO_MMIO_STATUS]
	cmp eax, 0
	jne virtio_net_mmio_reset_wait

	; 3.1.1 - Step 2 - Tell the device we see it
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE
	mov [rsi+VIRTIO_MMIO_STATUS], eax

	; 3.1.1 - Step 3 - Tell the device we support it
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER
	mov [rsi+VIRTIO_MMIO_STATUS], eax

	; 3.1.1 - Step 4
	; Process the first 32-bits of Feature bits
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_DEVICE_FEATURES_SELECT], eax
	mov eax, [rsi+VIRTIO_MMIO_DEVICE_FEATURES]
	; Returns 2000DDA3
;	xor eax, eax
;	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES_SELECT], eax
;	mov eax, 0x00010020		; Feature bits 31:0 - STATUS (16), MAC (5)
;	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES], eax
	; Process the next 32-bits of Feature bits
	mov eax, 1
	mov [rsi+VIRTIO_MMIO_DEVICE_FEATURES_SELECT], eax
	mov eax, [rsi+VIRTIO_MMIO_DEVICE_FEATURES]
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
	jnc net_virtio_mmio_reset_error

	; 3.1.1 - Step 7
	; Set up the device and the queues
	; discovery of virtqueues for the device
	; optional per-bus setup
	; reading and possibly writing the device’s virtio configuration space
	; population of virtqueues

	; Set up Queue 0 (Receive)
	; For simplicity each Ring is the same memory size as the Table
	; This wastes some memory (for 256 entries - 5620 bytes are unused)
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_QUEUE_SELECT], eax
	mov eax, [rsi+VIRTIO_MMIO_QUEUE_NUMMAX]	; Return the size of the queue
	; returns 0x00000100 on firecracker
	mov [virtio_net_rxqueuesize], eax		; Store receive queue size
	mov [rsi+VIRTIO_MMIO_QUEUE_NUM], eax	; Tell the device we support that number
	mov ebx, eax			; Copy receive queue size to EBX
	shl ebx, 4			; Multiply by 16 (size of a descriptor)
	mov rax, os_rx_desc		; Set address of Descriptor ring
	mov [rsi+VIRTIO_MMIO_QUEUE_DESC], eax
	rol rax, 32
	mov [rsi+VIRTIO_MMIO_QUEUE_DESC+4], eax
	rol rax, 32
	add rax, rbx			; Set address of Available ring
	; TODO - The available ring does not need the same amount of memory as the descriptor ring
	mov [rsi+VIRTIO_MMIO_QUEUE_DRIVER], eax
	rol rax, 32
	mov [rsi+VIRTIO_MMIO_QUEUE_DRIVER+4], eax
	rol rax, 32
	add rax, rbx			; Set address of Used ring
	; TODO - The used ring does not need the same amount of memory as the descriptor ring
	mov [rsi+VIRTIO_MMIO_QUEUE_DEVICE], eax
	rol rax, 32
	mov [rsi+VIRTIO_MMIO_QUEUE_DEVICE+4], eax
	mov eax, 1
	mov [rsi+VIRTIO_MMIO_QUEUE_READY], eax

	; Set up Queue 1 (Transmit)
	; For simplicity each Ring is the same memory size as the Table
	; This wastes some memory (for 256 entries - 5620 bytes are unused)
	mov eax, 1
	mov [rsi+VIRTIO_MMIO_QUEUE_SELECT], eax
	mov eax, [rsi+VIRTIO_MMIO_QUEUE_NUMMAX]	; Return the size of the queue
	mov [virtio_net_txqueuesize], eax		; Store receive queue size
	mov [rsi+VIRTIO_MMIO_QUEUE_NUM], eax	; Tell the device we support that number
	mov ebx, eax			; Copy transmit queue size to EBX
	shl ebx, 4			; Multiply by 16 (size of a descriptor)
	mov rax, os_tx_desc		; Set address of Descriptor ring
	mov [rsi+VIRTIO_MMIO_QUEUE_DESC], eax
	rol rax, 32
	mov [rsi+VIRTIO_MMIO_QUEUE_DESC+4], eax
	rol rax, 32
	add rax, rbx			; Set address of Available ring
	; TODO - The available ring does not need the same amount of memory as the descriptor ring
	mov [rsi+VIRTIO_MMIO_QUEUE_DRIVER], eax
	rol rax, 32
	mov [rsi+VIRTIO_MMIO_QUEUE_DRIVER+4], eax
	rol rax, 32
	add rax, rbx			; Set address of Used ring
	; TODO - The used ring does not need the same amount of memory as the descriptor ring
	mov [rsi+VIRTIO_MMIO_QUEUE_DEVICE], eax
	rol rax, 32
	mov [rsi+VIRTIO_MMIO_QUEUE_DEVICE+4], eax
	mov eax, 1
	mov [rsi+VIRTIO_MMIO_QUEUE_READY], eax

	; Populate TX Descriptor Table Entries
	mov ecx, [virtio_net_txqueuesize]	; Gather TX queue size from net_table
	mov ax, 1
	mov rdi, os_tx_desc
	add rdi, 14
virtio_net_init_pop_tx_d:
	mov [rdi], ax
	add rdi, 16
	add ax, 1
	dec ecx
	jnz virtio_net_init_pop_tx_d
	mov ax, 0
	sub rdi, 16
	mov [rdi], ax			; Last next pointer wraps to beginning

	; Populate RX Descriptor Table Entries
	mov ecx, [virtio_net_rxqueuesize]	; Gather RX queue size from net_table
	mov rdi, os_rx_desc
	mov rbx, [os_PacketBase]
virtio_net_init_pop_rx_d:
	mov rax, rbx			; 64-bit Address
	add rbx, 2048
	stosq
	mov eax, 2048			; 32-bit Length
	stosd
	mov ax, VIRTQ_DESC_F_WRITE
	stosw				; 16-bit Flags
	mov ax, 0
	stosw				; 16-bit Next
	dec ecx
	jnz virtio_net_init_pop_rx_d

	; Populate RX Available Ring Entries
	xor eax, eax
	mov rdi, os_rx_desc
	mov eax, [virtio_net_rxqueuesize]	; Gather RX queue size from net_table
	mov ecx, eax
	shl eax, 4			; Quick multiply by 16
	add rdi, rax			; Add offset to Available Ring
	xor eax, eax
	stosw				; 16-bit flags
	mov eax, [virtio_net_rxqueuesize]	; Mark all RX descriptors as available
	stosw				; 16-bit index
	xor eax, eax
virtio_net_init_pop_rx_a:
	stosw				; 16-bit ring
	inc ax
	cmp ax, cx
	jne virtio_net_init_pop_rx_a

	; 3.1.1 - Step 8 - At this point the device is “live”
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_DRIVER_OK | VIRTIO_STATUS_FEATURES_OK
	mov [rsi+VIRTIO_MMIO_STATUS], eax

	; Acknowledge any existing interrupt
	mov eax, [rsi+VIRTIO_MMIO_INT_STATUS]
	mov [rsi+VIRTIO_MMIO_INT_ACK], eax

net_virtio_mmio_reset_done:
	pop rax
	pop rcx
	pop rsi
	pop rdi
	ret

net_virtio_mmio_reset_error:
	; TODO Handle error
	jmp net_virtio_mmio_reset_done
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; net_virtio_config -
;  IN:	RAX = Base address to store packets
;	RDX = Interface ID
; OUT:	Nothing
net_virtio_mmio_config:
	push rdi
	push rcx
	push rax

	pop rax
	pop rcx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; net_virtio_transmit - Transmit a packet via a Virtio NIC
;  IN:	RSI = Physical memory location of packet
;	RDX = Interface ID
;	RCX = Length of packet
; OUT:	Nothing
net_virtio_mmio_transmit:
	push r11
	push r10
	push r9
	push r8
	push rdi
	push rdx
	push rcx
	push rbx
	push rax

	; Gather TX queue info
	xor r9, r9
	mov r8, os_tx_desc			; TX descriptor table base
	mov r9d, [virtio_net_txqueuesize]	; TX queue size
	mov r10, r9
	dec r10					; Queue size - 1 (for power-of-2 modulo)
	shl r9, 5				; Quick multiply by 32 to get to Used Ring offset

	; Build descriptor 0 (virtio-net header)
	movzx r11d, word [txavailindex]		; Current descriptor head index
	and r11d, r10d				; Modulo by queue size
	mov ebx, r11d
	shl ebx, 4				; Quick multiply by 16 (descriptor entry size)
	lea rdi, [r8+rbx]
	mov rax, virtio_net_hdr
	mov [rdi], rax				; Header address
	mov dword [rdi+8], 12			; Header length (12 bytes)
	mov ax, VIRTQ_DESC_F_NEXT
	mov [rdi+12], ax			; Flags = NEXT
	mov eax, r11d
	inc ax
	and ax, r10w
	mov [rdi+14], ax			; Next descriptor index

	; Build descriptor 1 (packet payload)
	movzx ebx, ax
	shl ebx, 4				; Quick multiply by 16 (descriptor entry size)
	lea rdi, [r8+rbx]
	mov [rdi], rsi				; Packet address (physical)
	mov eax, ecx
	mov [rdi+8], eax			; Packet length
	xor eax, eax
	mov [rdi+12], ax			; Flags = 0

	; Add the descriptor chain head to the Available Ring
	shr r9, 1				; Quick divide by 2 = Available Ring offset (queue_size * 16)
	mov rdi, r8
	add rdi, r9				; Available Ring base
	movzx ebx, word [rdi+2]			; Current available ring idx
	mov ax, bx				; Save a copy
	and ebx, r10d				; Modulo by queue size
	shl ebx, 1				; Multiply by 2 (16-bit entries)
	add ebx, 4				; Skip flags(2) + idx(2)
	mov [rdi+rbx], r11w			; Write descriptor chain head index to ring
	inc ax
	mov [rdi+2], ax				; Update available ring idx

	; Notify the TX queue (Queue 1)
	mov rdi, [os_virtionet_base]
	mov eax, 1				; Queue 1 = TX
	mov [rdi+VIRTIO_MMIO_QUEUE_NOTIFY], eax

	; Wait for device to consume the TX request
	shl r9, 1				; Convert Available Ring offset back to Used Ring offset
	mov rdi, r8
	add rdi, r9				; Used Ring base
	mov ax, [txusedindex]			; Our last processed TX used index
net_virtio_mmio_transmit_wait:
	cmp ax, [rdi+2]				; Compare with device's used ring idx
	jne net_virtio_mmio_transmit_done
	jmp net_virtio_mmio_transmit_wait

net_virtio_mmio_transmit_done:
	inc word [txusedindex]			; Track the consumed used entry

	; Advance TX descriptor head by 2 (2 descriptors used per TX)
	movzx eax, word [txavailindex]
	add ax, 2
	and ax, r10w
	mov [txavailindex], ax

	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rdi
	pop r8
	pop r9
	pop r10
	pop r11
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; net_virtio_poll - Polls the Virtio NIC for a received packet
;  IN:	RDX = Interface ID
; OUT:	RDI = Location of stored packet
;	RCX = Length of packet
net_virtio_mmio_poll:
	push r11
	push r10
	push r9
	push r8
	push rsi
	push rdx
	push rbx
	push rax

	; Gather RX queue info
	xor r9, r9
	mov r8, os_rx_desc			; RX descriptor table base
	mov r9d, [virtio_net_rxqueuesize]	; RX queue size
	mov r10, r9
	dec r10					; Queue size - 1 (for power-of-2 modulo)
	shl r9, 5				; Quick multiply by 32 to get to Used Ring offset

	; Check the Used Ring for new entries
	xor ecx, ecx				; Default: no packet (length = 0)
	mov rsi, r8
	add rsi, r9				; Used Ring base
	shr r9, 1				; Quick divide by 2 = Available Ring offset
	mov ax, [rxavailindex]			; Our last processed RX used index
	cmp ax, [rsi+2]				; Compare with device's used ring idx
	je net_virtio_mmio_poll_nodata		; Same = no new packet

	; Calculate offset into Used Ring entries (8 bytes each: 4-byte id + 4-byte len)
	movzx ebx, ax				; Our current index
	and ebx, r10d				; Modulo by queue size
	shl ebx, 3				; Quick multiply by 8 (entry size)
	add ebx, 4				; Skip flags(2) + idx(2)

	; Read the Used Ring entry
	mov eax, [rsi+rbx]			; 32-bit Descriptor ID
	mov ecx, [rsi+rbx+4]			; 32-bit Total bytes written by device
	mov r11d, eax				; Preserve descriptor ID for Available Ring refill

	; Get buffer address from the Descriptor Table
	movzx ebx, ax				; Descriptor ID
	shl ebx, 4				; Quick multiply by 16 (descriptor entry size)
	mov rdi, [r8+rbx]			; 64-bit buffer address from descriptor

	; Adjust for virtio_net_hdr (12 bytes)
	cmp ecx, 12
	jb net_virtio_mmio_poll_malformed
	add rdi, 12				; Skip past virtio_net_hdr
	sub ecx, 12				; Subtract header size from length

net_virtio_mmio_poll_refill:
	; Re-add the descriptor to the Available Ring
	mov rsi, r8
	add rsi, r9				; Available Ring base
	movzx ebx, word [rsi+2]			; Current available ring idx
	push rbx
	and ebx, r10d				; Modulo by queue size
	shl ebx, 1				; Multiply by 2 (16-bit entries)
	add ebx, 4				; Skip flags(2) + idx(2)
	mov [rsi+rbx], r11w			; Write descriptor index to ring
	pop rbx
	inc bx
	mov [rsi+2], bx				; Store updated idx

	; Notify the device about the refilled RX buffer (Queue 0)
	mov rsi, [os_virtionet_base]
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_QUEUE_NOTIFY], eax	; Queue 0 = RX

	; Update tracked RX used ring index
	inc word [rxavailindex]

net_virtio_mmio_poll_nodata:
	pop rax
	pop rbx
	pop rdx
	pop rsi
	pop r8
	pop r9
	pop r10
	pop r11
	ret

net_virtio_mmio_poll_malformed:
	xor ecx, ecx				; Return no packet data
	xor edi, edi
	jmp net_virtio_mmio_poll_refill
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; Virtio-net Interrupt
align 8
net_virtio_mmio_int:
	push rcx
	push rax


	pop rax
	pop rcx
	iretq
; -----------------------------------------------------------------------------

; Variables
txavailindex: dw 0
txusedindex: dw 0
rxavailindex: dw 0

; VIRTQUEUE Descriptor Flags
VIRTQ_DESC_F_NEXT			equ 1
VIRTQ_DESC_F_WRITE			equ 2
VIRTQ_DESC_F_INDIRECT			equ 4

align 16
virtio_net_hdr:
flags: db 0x00
gso_type: db 0x00
hdr_len: dw 0x0000
gso_size: dw 0x0000
csum_start: dw 0x0000
csum_offset: dw 0x0000
num_buffers: dw 0x0000

; VIRTIO_DEVICEFEATURES bits
VIRTIO_NET_F_CSUM		equ 0 ; Device handles packets with partial checksum
VIRTIO_NET_F_GUEST_CSUM		equ 1 ; Driver handles packets with partial checksum
VIRTIO_NET_F_CTRL_GUEST_OFFLOADS	equ 2 ; Control channel offloads reconfiguration support
VIRTIO_NET_F_MTU		equ 3 ; Device maximum MTU reporting is supported
VIRTIO_NET_F_MAC		equ 5 ; Device has given MAC address
VIRTIO_NET_F_GSO		equ 6 ; LEGACY Device handles packets with any GSO type
VIRTIO_NET_F_GUEST_TSO4		equ 7 ; Driver can receive TSOv4
VIRTIO_NET_F_GUEST_TSO6		equ 8 ; Driver can receive TSOv6
VIRTIO_NET_F_GUEST_ECN		equ 9 ; Driver can receive TSO with ECN
VIRTIO_NET_F_GUEST_UFO		equ 10 ; Driver can receive UFO
VIRTIO_NET_F_HOST_TSO4		equ 11 ; Device can receive TSOv4
VIRTIO_NET_F_HOST_TSO6		equ 12 ; Device can receive TSOv6
VIRTIO_NET_F_HOST_ECN		equ 13 ; Device can receive TSO with ECN
VIRTIO_NET_F_HOST_UFO		equ 14 ; Device can receive UFO
VIRTIO_NET_F_MRG_RXBUF		equ 15 ; Driver can merge receive buffers
VIRTIO_NET_F_STATUS		equ 16 ; Configuration status field is available
VIRTIO_NET_F_CTRL_VQ		equ 17 ; Control channel is available
VIRTIO_NET_F_CTRL_RX		equ 18 ; Control channel RX mode support
VIRTIO_NET_F_CTRL_VLAN		equ 19 ; Control channel VLAN filtering
VIRTIO_NET_F_CTRL_RX_EXTRA	equ 20 ; ???
VIRTIO_NET_F_GUEST_ANNOUNCE	equ 21 ; Driver can send gratuitous packets
VIRTIO_NET_F_MQ			equ 22 ; Device supports multiqueue with automatic receive steering
VIRTIO_NET_F_CTRL_MAC_ADDR	equ 23 ; Set MAC address through control channel
VIRTIO_NET_F_GUEST_RSC4		equ 41 ; LEGACY Device coalesces TCPIP v4 packets
VIRTIO_NET_F_GUEST_RSC6		equ 42 ; LEGACY Device coalesces TCPIP v6 packets
VIRTIO_NET_F_HOST_USO		equ 56 ; Device can receive USO packets
VIRTIO_NET_F_HASH_REPORT	equ 57 ; Device can report per-packet hash value and a type of calculated hash.
VIRTIO_NET_F_GUEST_HDRLEN	equ 59 ; Driver can provide the exact hdr_len value. Device benefits from knowing the exact header length.
VIRTIO_NET_F_RSS		equ 60 ; Device supports RSS (receive-side scaling) with Toeplitz hash calculation and configurable hash parameters for receive steering.
VIRTIO_NET_F_RSC_EXT		equ 61 ; Device can process duplicated ACKs and report number of coalesced segments and duplicated ACKs.
VIRTIO_NET_F_STANDBY		equ 62 ; Device may act as a standby for a primary device with the same MAC address.
VIRTIO_NET_F_SPEED_DUPLEX	equ 63 ; Device reports speed and duplex

; VIRTQUEUES
VIRTIO_NET_QUEUE_RX		equ 0	; The first of the Receive Queues
VIRTIO_NET_QUEUE_TX		equ 1	; The first of the Transmit Queues

; VIRTIO_NET_HDR flags
VIRTIO_NET_HDR_F_NEEDS_CSUM	equ 1
VIRTIO_NET_HDR_F_DATA_VALID	equ 2
VIRTIO_NET_HDR_F_RSC_INFO	equ 4

; VIRTIO_NET_HDR gso_type
VIRTIO_NET_HDR_GSO_NONE		equ 0
VIRTIO_NET_HDR_GSO_TCPV4	equ 1
VIRTIO_NET_HDR_GSO_UDP		equ 3
VIRTIO_NET_HDR_GSO_TCPV6	equ 4
VIRTIO_NET_HDR_GSO_UDP_L4	equ 5
VIRTIO_NET_HDR_GSO_ECN		equ 0x80


; =============================================================================
; EOF
