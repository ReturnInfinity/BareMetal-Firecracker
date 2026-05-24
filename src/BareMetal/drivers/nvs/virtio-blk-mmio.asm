; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Virtio Block Driver
; =============================================================================


; -----------------------------------------------------------------------------
; Initialize a Virtio Block device
virtio_blk_mmio_init:
	push rsi
	push rdx			; RDX should already point to a supported device for os_bus_read/write
	push rbx
	push rax

	; Check for a valid device
	mov rsi, [os_virtioblk_base]
	cmp rsi, 0
	je virtio_blk_mmio_init_done

	; Device Initialization (section 3.1)
	; TODO - Move to reset function

	; 3.1.1 - Step 1 - Reset the device (section 2.4)
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_STATUS], eax
virtio_blk_mmio_reset_wait:
	mov eax, [rsi+VIRTIO_MMIO_STATUS]
	cmp eax, 0
	jne virtio_blk_mmio_reset_wait

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
;	call os_debug_dump_eax
;	call os_debug_newline
	; returns 0x20000000
;	xor eax, eax
;	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES_SELECT], eax
;	btc eax, VIRTIO_BLK_F_MQ	; Disable Multiqueue support for this driver
;	btc eax, VIRTIO_F_INDIRECT_DESC
;	mov eax, 0x44			; Only support BLK_SIZE (6) & SEG_MAX (2)
;	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES], eax
	; Process the next 32-bits of Feature bits
	mov eax, 1
	mov [rsi+VIRTIO_MMIO_DEVICE_FEATURES_SELECT], eax
	mov eax, [rsi+VIRTIO_MMIO_DEVICE_FEATURES]
;	call os_debug_dump_eax
;	call os_debug_newline
	; returns 0x00000001
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
	jnc virtio_blk_mmio_init_error

	; 3.1.1 - Step 7
	; Set up the device and the queues
	; discovery of virtqueues for the device
	; optional per-bus setup
	; reading and possibly writing the device’s virtio configuration space
	; population of virtqueues

	; Set up Queue 0
	; For simplicity each Ring is the same memory size as the Table
	; This wastes some memory (for 256 entries - 5620 bytes are unused)
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_QUEUE_SELECT], eax
	mov eax, [rsi+VIRTIO_MMIO_QUEUE_NUMMAX]	; Return the size of the queue
	; returns 0x00000100 on firecracker
	mov [virtio_blk_queuesize], eax		; Store receive queue size
	mov [rsi+VIRTIO_MMIO_QUEUE_NUM], eax	; Tell the device we support that number
	mov ebx, eax			; Copy receive queue size to EBX
	shl ebx, 4			; Multiply by 16 (size of a descriptor)
	mov eax, os_nvs_mem		; Set address of Descriptor Table
	mov [rsi+VIRTIO_MMIO_QUEUE_DESC], eax
	rol rax, 32
	mov [rsi+VIRTIO_MMIO_QUEUE_DESC+4], eax
	rol rax, 32
	add rax, rbx			; Set address of Available Ring
	; TODO - The available ring does not need the same amount of memory as the descriptor ring
	mov [rsi+VIRTIO_MMIO_QUEUE_DRIVER], eax
	rol rax, 32
	mov [rsi+VIRTIO_MMIO_QUEUE_DRIVER+4], eax
	rol rax, 32
	add rax, rbx			; Set address of Used Ring
	; TODO - The used ring does not need the same amount of memory as the descriptor ring
	mov [rsi+VIRTIO_MMIO_QUEUE_DEVICE], eax
	rol rax, 32
	mov [rsi+VIRTIO_MMIO_QUEUE_DEVICE+4], eax
	mov eax, 1
	mov [rsi+VIRTIO_MMIO_QUEUE_READY], eax

	; Populate the 16-bit Next entries in the description ring
	mov ecx, [virtio_blk_queuesize]	; Receive queue size
	mov ax, 1
	mov rdi, os_nvs_mem
	add rdi, 14
virtio_blk_mmio_init_pop:
	mov [rdi], ax
	add rdi, 16
	add ax, 1
	dec ecx
	jnz virtio_blk_mmio_init_pop
	mov ax, 0
	sub rdi, 16
	mov [rdi], ax			; Last next pointer wraps to beginning

	; 3.1.1 - Step 8 - At this point the device is “live”
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_DRIVER_OK | VIRTIO_STATUS_FEATURES_OK
	mov [rsi+VIRTIO_MMIO_STATUS], eax

virtio_blk_mmio_init_done:
	bts word [os_nvsVar], 3		; Set the bit flag that Virtio Block has been initialized
	mov rdi, os_nvs_io		; Write over the storage function addresses
	mov eax, virtio_blk_mmio_io
	stosq
	mov eax, virtio_blk_mmio_id
	stosq
	pop rax
	pop rbx
	pop rdx
	pop rsi
	ret

virtio_blk_mmio_init_error:
	pop rax
	pop rbx
	pop rdx
	pop rsi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; virtio_blk_io -- Perform an I/O operation on a VIRTIO Block device
; IN:	RAX = starting sector #
;	RBX = I/O Opcode
;	RCX = number of sectors
;	RDX = drive #
;	RDI = memory location used for reading/writing data from/to device
; OUT:	Nothing
;	All other registers preserved
virtio_blk_mmio_io:
	push r9
	push rdi
	push rdx
	push rcx
	push rbx
	push rax

	; Opcode sanity check
	cmp ebx, 0
	je virtio_blk_mmio_io_error
	cmp ebx, 2
	ja virtio_blk_mmio_io_error

	; Convert I/O Opcode
	; BareMetal I/O opcode for Read is 2, Write is 1
	; Virtio-blk I/O opcode for Read is 0, Write is 1
	xor ebx, 2
	shr ebx, 1

	push rax			; Save the starting sector
	mov r9, rdi			; Save the memory address

	mov rdi, os_nvs_mem		; This driver always starts at beginning of the Descriptor Table
					; FIXME: Add desc_index offset

	; Add header to Descriptor Entry 0
	mov eax, header			; Address of the header
	stosq				; 64-bit address
	mov eax, 16
	stosd				; 32-bit length
	mov ax, VIRTQ_DESC_F_NEXT
	stosw				; 16-bit Flags
	add rdi, 2			; Skip Next as it is pre-populated

	; Add data to Descriptor Entry 1
	mov rax, r9			; Address to store the data
	stosq
	mov eax, ecx			; Number of bytes
	shl rax, 12			; Covert count to 4096B sectors
	stosd
	mov ax, VIRTQ_DESC_F_NEXT
	cmp bx, 1
	je skip_write
	or ax, VIRTQ_DESC_F_WRITE
skip_write:
	stosw				; 16-bit Flags
	add rdi, 2			; Skip Next as it is pre-populated

	; Add footer to Descriptor Entry 2
	mov eax, footer			; Address of the footer
	stosq				; 64-bit address
	mov eax, 1
	stosd				; 32-bit length
	mov eax, VIRTQ_DESC_F_WRITE
	stosw				; 16-bit Flags
	add rdi, 2			; Skip Next as it is pre-populated

	; Build the header
	mov edi, header
	mov eax, ebx			; Opcode
	stosd				; type
	xor eax, eax
	stosd				; reserved
	pop rax				; Restore the starting sector
	shl rax, 3			; Multiply by 8 as we use 4096-byte sectors internally
	stosq				; starting sector

	; Build the footer
	mov edi, footer
	xor eax, eax
	stosb

	; Add entry to Avail ring
	mov rdi, os_nvs_mem
	mov eax, [virtio_blk_queuesize]
	shl eax, 4			; queuesize * 16 = avail ring offset
	add rdi, rax			; rdi = avail_ring_base

	; ring[availindex % queuesize] = 0 (descriptor chain head)
	movzx eax, word [availindex]
	mov ecx, [virtio_blk_queuesize]
	xor edx, edx
	div ecx				; edx = availindex % queuesize (works for any queue size)
	mov word [rdi + rdx * 2 + 4], 0	; Clear the entry

	; Increment first, then publish the new idx
	inc word [availindex]
	mov ax, 1			; flags: suppress interrupt
	mov [rdi], ax
	mov ax, [availindex]
	mov [rdi + 2], ax		; avail_ring.idx = post-increment value

	; Notify the queue
	mov rdi, [os_virtioblk_base]
	add rdi, VIRTIO_MMIO_QUEUE_NOTIFY
	xor eax, eax
	stosd

	; Wait for used_ring.idx to reach availindex
	mov rdi, os_nvs_mem
	mov eax, [virtio_blk_queuesize]
	shl eax, 4
	add rdi, rax			; skip descriptor table
	add rdi, rax			; skip available ring
	add rdi, 2			; skip used ring flags, land on idx
	mov bx, [availindex]		; bx = post-increment value just published
virtio_blk_mmio_io_wait:
	; TODO - Add a timeout delay and cleanup if the command failed
	mov ax, [rdi]
	cmp ax, bx
	jne virtio_blk_mmio_io_wait

virtio_blk_mmio_io_error:
	pop rax
	pop rbx
	pop rcx
	pop rdx
	pop rdi
	pop r9
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; virtio_blk_id --
; IN:	EAX = CDW0
;	EBX = CDW1
;	ECX = CDW10
;	EDX = CDW11
;	RDI = CDW6-7
; OUT:	Nothing
;	All other registers preserved
virtio_blk_mmio_id:
	; TODO - Low priority
	ret
; -----------------------------------------------------------------------------

; Variables
availindex: dw 0
virtio_blk_queuesize: dd 0

; Descriptors
align 16
footer:
db 0x00

align 16
header:
dd 0x00					; 32-bit type
dd 0x00					; 32-bit reserved
dq 0					; 64-bit sector

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

; VIRTIO BLK Registers
VIRTIO_BLK_CAPACITY				equ 0x14 ; 64-bit Capacity (in 512-byte sectors)
VIRTIO_BLK_SIZE_MAX				equ 0x1C ; 32-bit Maximum Segment Size
VIRTIO_BLK_SEG_MAX				equ 0x20 ; 32-bit Maximum Segment Count
VIRTIO_BLK_CYLINDERS				equ 0x24 ; 16-bit Cylinder Count
VIRTIO_BLK_HEADS				equ 0x26 ; 8-bit Head Count
VIRTIO_BLK_SECTORS				equ 0x27 ; 8-bit Sector Count
VIRTIO_BLK_BLK_SIZE				equ 0x28 ; 32-bit Block Length
VIRTIO_BLK_PHYSICAL_BLOCK_EXP			equ 0x2C ; 8-bit # OF LOGICAL BLOCKS PER PHYSICAL BLOCK (LOG2)
VIRTIO_BLK_ALIGNMENT_OFFSET			equ 0x2D ; 8-bit OFFSET OF FIRST ALIGNED LOGICAL BLOCK
VIRTIO_BLK_MIN_IO_SIZE				equ 0x2E ; 16-bit SUGGESTED MINIMUM I/O SIZE IN BLOCKS
VIRTIO_BLK_OPT_IO_SIZE				equ 0x30 ; 32-bit OPTIMAL (SUGGESTED MAXIMUM) I/O SIZE IN BLOCKS
VIRTIO_BLK_WRITEBACK				equ 0x34 ; 8-bit
VIRTIO_BLK_NUM_QUEUES				equ 0x36 ; 16-bit
VIRTIO_BLK_MAX_DISCARD_SECTORS			equ 0x38 ; 32-bit
VIRTIO_BLK_MAX_DISCARD_SEG			equ 0x3C ; 32-bit
VIRTIO_BLK_DISCARD_SECTOR_ALIGNMENT		equ 0x40 ; 32-bit
VIRTIO_BLK_MAX_WRITE_ZEROES_SECTORS		equ 0x44 ; 32-bit
VIRTIO_BLK_MAX_WRITE_ZEROES_SEG			equ 0x48 ; 32-bit
VIRTIO_BLK_WRITE_ZEROES_MAY_UNMAP		equ 0x4C ; 8-bit
VIRTIO_BLK_MAX_SECURE_ERASE_SECTORS		equ 0x50 ; 32-bit
VIRTIO_BLK_MAX_SECURE_ERASE_SEG			equ 0x54 ; 32-bit
VIRTIO_BLK_SECURE_ERASE_SECTOR_ALIGNMENT	equ 0x58 ; 32-bit

; VIRTIO_DEVICEFEATURES bits
VIRTIO_BLK_F_BARRIER			equ 0 ; Legacy - Device supports request barriers
VIRTIO_BLK_F_SIZE_MAX			equ 1 ; Maximum size of any single segment is in size_max
VIRTIO_BLK_F_SEG_MAX			equ 2 ; Maximum number of segments in a request is in seg_max
VIRTIO_BLK_F_GEOMETRY			equ 4 ; Disk-style geometry specified in geometry
VIRTIO_BLK_F_RO				equ 5 ; Device is read-only
VIRTIO_BLK_F_BLK_SIZE			equ 6 ; Block size of disk is in blk_size
VIRTIO_BLK_F_SCSI			equ 7 ; Legacy - Device supports scsi packet commands
VIRTIO_BLK_F_FLUSH			equ 9 ; Cache flush command support
VIRTIO_BLK_F_TOPOLOGY			equ 10 ; Device exports information on optimal I/O alignment
VIRTIO_BLK_F_CONFIG_WCE			equ 11 ; Device can toggle its cache between writeback and writethrough modes
VIRTIO_BLK_F_MQ				equ 12 ; Device supports multiqueue
VIRTIO_BLK_F_DISCARD			equ 13 ; Device can support discard command
VIRTIO_BLK_F_WRITE_ZEROES		equ 14 ; Device can support write zeroes command
VIRTIO_BLK_F_LIFETIME			equ 15 ; Device supports providing storage lifetime information
VIRTIO_BLK_F_SECURE_ERASE		equ 16 ; Device supports secure erase command

; VIRTIO Block Types
VIRTIO_BLK_T_IN				equ 0 ; Read from device
VIRTIO_BLK_T_OUT			equ 1 ; Write to device
VIRTIO_BLK_T_FLUSH			equ 4 ; Flush
VIRTIO_BLK_T_GET_ID			equ 8 ; Get device ID string
VIRTIO_BLK_T_GET_LIFETIME		equ 10 ; Get device lifetime
VIRTIO_BLK_T_DISCARD			equ 11 ; Discard
VIRTIO_BLK_T_WRITE_ZEROES		equ 13 ; Write zeros
VIRTIO_BLK_T_SECURE_ERASE		equ 14 ; Secure erase


; =============================================================================
; EOF
