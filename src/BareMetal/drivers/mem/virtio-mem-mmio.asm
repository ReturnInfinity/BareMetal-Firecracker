; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Virtio Memory (virtio-mem) Driver
; =============================================================================
;
; Firecracker exposes hot-pluggable RAM as a virtio-mem device (virtio spec
; section 5.15). The device owns a large, initially-unbacked guest-physical
; region (Firecracker places it above 512 GiB, see its arch/x86_64/layout.rs)
; carved into fixed-size blocks (2 MiB by default). The guest claims blocks
; with PLUG requests on queue 0. The host only allows plugging up to the
; `requested_size` it publishes in the config space (set through Firecracker's
; `PATCH /hotplug/memory` API -- it starts at 0) and NACKs anything beyond it.
;
; This driver plugs blocks on demand -- b_system(GROW_MEMORY) -- and appends
; each one to the app's virtual memory window (0xFFFF800000000000+) by adding
; 2 MiB page-directory entries right after the ones init built for boot RAM.
; The app therefore sees a single contiguous window that simply gets bigger,
; and b_system(FREE_MEMORY) (os_MemAmount) grows to match. Nothing is ever
; unplugged: the kernel hands memory straight to the app and has no way to
; take it back.
;
; Requests are completed synchronously by polling the used ring, the same way
; the virtio-blk driver does; no interrupt is used.


; -----------------------------------------------------------------------------
; virtio_mem_mmio_init -- Initialize a Virtio Memory device
; IN:	Nothing ([os_virtiomem_base] was set by virtio_mmio_init)
; OUT:	Nothing. [os_virtiomem_base] is cleared if the device can't be used
;	All registers preserved
virtio_mem_mmio_init:
	push rsi
	push rdi
	push rcx
	push rbx
	push rax

	; Check for a valid device
	mov rsi, [os_virtiomem_base]
	cmp rsi, 0
	je virtio_mem_mmio_init_done

	; Device Initialization (section 3.1)

	; 3.1.1 - Step 1 - Reset the device (section 2.4)
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_STATUS], eax
virtio_mem_mmio_reset_wait:
	mov eax, [rsi+VIRTIO_MMIO_STATUS]
	cmp eax, 0
	jne virtio_mem_mmio_reset_wait

	; 3.1.1 - Step 2 - Tell the device we see it
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE
	mov [rsi+VIRTIO_MMIO_STATUS], eax

	; 3.1.1 - Step 3 - Tell the device we support it
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER
	mov [rsi+VIRTIO_MMIO_STATUS], eax

	; 3.1.1 - Step 4 - Feature negotiation
	; Unlike the blk/net drivers this one can't skip it: Firecracker refuses
	; to activate virtio-mem unless the driver acknowledges
	; VIRTIO_MEM_F_UNPLUGGED_INACCESSIBLE, and VIRTIO_F_VERSION_1 (bit 32)
	; is mandatory for any modern (non-legacy) device.
	; Feature bits 31:0
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_DEVICE_FEATURES_SELECT], eax
	mov eax, [rsi+VIRTIO_MMIO_DEVICE_FEATURES]
	bt eax, VIRTIO_MEM_F_UNPLUGGED_INACCESSIBLE
	jnc virtio_mem_mmio_init_error
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES_SELECT], eax
	mov eax, 1 << VIRTIO_MEM_F_UNPLUGGED_INACCESSIBLE
	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES], eax
	; Feature bits 63:32
	mov eax, 1
	mov [rsi+VIRTIO_MMIO_DEVICE_FEATURES_SELECT], eax
	mov eax, [rsi+VIRTIO_MMIO_DEVICE_FEATURES]
	bt eax, VIRTIO_F_VERSION_1 - 32
	jnc virtio_mem_mmio_init_error
	mov eax, 1
	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES_SELECT], eax
	mov eax, 1 << (VIRTIO_F_VERSION_1 - 32)
	mov [rsi+VIRTIO_MMIO_DRIVER_FEATURES], eax

	; 3.1.1 - Step 5
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_FEATURES_OK
	mov [rsi+VIRTIO_MMIO_STATUS], eax

	; 3.1.1 - Step 6 - Re-read device status to make sure FEATURES_OK is still set
	mov eax, [rsi+VIRTIO_MMIO_STATUS]
	bt eax, 3			; VIRTIO_STATUS_FEATURES_OK
	jnc virtio_mem_mmio_init_error

	; 3.1.1 - Step 7 - Device-specific setup

	; Read the static config fields. Both have to be 2 MiB multiples since
	; plugged blocks are mapped with 2 MiB pages (Firecracker: block size is
	; a power of two >= 2 MiB and the region is slot-aligned, so this holds)
	mov ecx, VIRTIO_MEM_BLOCK_SIZE
	call virtio_mem_cfg64
	test rax, rax
	jz virtio_mem_mmio_init_error
	test rax, 0x1FFFFF
	jnz virtio_mem_mmio_init_error
	mov [virtio_mem_block_size], rax
	mov ecx, VIRTIO_MEM_ADDR
	call virtio_mem_cfg64
	test rax, 0x1FFFFF
	jnz virtio_mem_mmio_init_error
	mov [virtio_mem_addr], rax

	; Clear the virtqueue memory
	mov edi, os_mem_mem
	xor eax, eax
	mov ecx, 4096/8
	rep stosq
	mov word [virtio_mem_availindex], 0

	; Set up Queue 0 (guest-request). One request is ever in flight at a
	; time so a tiny queue is plenty; the device only requires a power of
	; two no larger than QUEUE_NUMMAX
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_QUEUE_SELECT], eax
	mov eax, [rsi+VIRTIO_MMIO_QUEUE_NUMMAX]
	cmp eax, VIRTIO_MEM_QUEUE_SIZE
	jb virtio_mem_mmio_init_error
	mov eax, VIRTIO_MEM_QUEUE_SIZE
	mov [rsi+VIRTIO_MMIO_QUEUE_NUM], eax
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_QUEUE_DESC_HIGH], eax
	mov [rsi+VIRTIO_MMIO_QUEUE_DRIVER_HIGH], eax
	mov [rsi+VIRTIO_MMIO_QUEUE_DEVICE_HIGH], eax
	mov eax, virtio_mem_desc
	mov [rsi+VIRTIO_MMIO_QUEUE_DESC_LOW], eax
	mov eax, virtio_mem_avail
	mov [rsi+VIRTIO_MMIO_QUEUE_DRIVER_LOW], eax
	mov eax, virtio_mem_used
	mov [rsi+VIRTIO_MMIO_QUEUE_DEVICE_LOW], eax
	mov eax, 1
	mov [rsi+VIRTIO_MMIO_QUEUE_READY], eax

	; Find where init stopped filling the high page directory. Init lays
	; the boot RAM's 2 MiB PDEs out back-to-back from the start of sys_pdh
	; (init.asm, pde_high) and everything past them is still zero, so the
	; first empty slot is where hot-plugged blocks get appended
	mov rdi, sys_pdh
	xor ecx, ecx
virtio_mem_mmio_init_pde_scan:
	cmp qword [rdi+rcx*8], 0
	je virtio_mem_mmio_init_pde_found
	inc ecx
	cmp ecx, VIRTIO_MEM_PDE_MAX
	jb virtio_mem_mmio_init_pde_scan
	jmp virtio_mem_mmio_init_error	; Page directory already full - nothing can be added
virtio_mem_mmio_init_pde_found:
	mov [virtio_mem_pde_next], ecx

	; 3.1.1 - Step 8 - At this point the device is "live"
	mov eax, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_DRIVER_OK | VIRTIO_STATUS_FEATURES_OK
	mov [rsi+VIRTIO_MMIO_STATUS], eax

virtio_mem_mmio_init_done:
	pop rax
	pop rbx
	pop rcx
	pop rdi
	pop rsi
	ret

virtio_mem_mmio_init_error:
	; Tell the device we gave up on it and forget it exists so
	; virtio_mem_grow becomes a no-op
	mov eax, VIRTIO_STATUS_FAILED
	mov [rsi+VIRTIO_MMIO_STATUS], eax
	mov qword [os_virtiomem_base], 0
	jmp virtio_mem_mmio_init_done
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; virtio_mem_grow -- Plug more RAM and append it to the app's memory window
; IN:	RAX = Number of MiB wanted
; OUT:	RAX = Total app RAM in MiB now (the value b_system(FREE_MEMORY) returns).
;	      Unchanged if nothing could be added: no device, the host's
;	      requested_size budget is used up, or the device refused
;	All other registers preserved
; Note:	The request is rounded up to whole blocks and clamped to what the host
;	currently allows, so the caller may get less (or more) than asked for.
;	Compare the result against the previous FREE_MEMORY value.
virtio_mem_grow:
	push rbx
	push rcx
	push rdx
	push rsi
	push rdi
	push r8
	push r9
	push r10

	mov r8, rax			; R8 = MiB wanted
	mov rsi, [os_virtiomem_base]
	test rsi, rsi
	jz virtio_mem_grow_done		; No usable device
	test r8, r8
	jz virtio_mem_grow_done		; Nothing asked for

	; First-use grace period. requested_size (the plug ceiling) is 0 at
	; boot, and Firecracker only accepts the host's PATCH /hotplug/memory
	; that raises it once this driver has activated the device -- so an
	; app that needs memory right after boot can race baremetal.sh's
	; PATCH. If no budget has been published yet, wait up to
	; VIRTIO_MEM_BUDGET_WAIT_NS for one. Only once: a host that never
	; sets a budget then costs a single stall instead of one per call
	cmp byte [virtio_mem_waited], 0
	jne virtio_mem_grow_budget_ready
	mov byte [virtio_mem_waited], 1
	call [sys_timer]		; RAX = nanoseconds since boot (kvm_ns, works with interrupts off)
	mov r9, rax
	add r9, VIRTIO_MEM_BUDGET_WAIT_NS	; R9 = deadline
virtio_mem_grow_budget_wait:
	mov ecx, VIRTIO_MEM_REQUESTED_SIZE
	call virtio_mem_cfg64
	test rax, rax
	jnz virtio_mem_grow_budget_ready
	pause
	call [sys_timer]
	cmp rax, r9
	jb virtio_mem_grow_budget_wait
virtio_mem_grow_budget_ready:

	; How much may be plugged right now? The host caps the driver at the
	; smaller of usable_region_size and requested_size (re-read on every
	; call: the host can raise it at any time via PATCH /hotplug/memory).
	; plugged_size is where the next unplugged block starts, since this
	; driver only ever plugs sequentially from the start of the region
	mov ecx, VIRTIO_MEM_USABLE_REGION_SIZE
	call virtio_mem_cfg64
	mov r9, rax
	mov ecx, VIRTIO_MEM_REQUESTED_SIZE
	call virtio_mem_cfg64
	cmp rax, r9
	cmovb r9, rax			; R9 = min(usable_region_size, requested_size)
	mov ecx, VIRTIO_MEM_PLUGGED_SIZE
	call virtio_mem_cfg64
	mov r10, rax			; R10 = plugged_size = offset of the next unplugged block
	cmp r10, r9
	jae virtio_mem_grow_done	; Budget already used up
	sub r9, r10			; R9 = bytes still allowed

	; Convert the request to whole blocks, rounding up
	mov rbx, [virtio_mem_block_size]
	shl r8, 20			; MiB -> bytes
	lea rax, [r8+rbx-1]
	xor edx, edx
	div rbx
	mov r8, rax			; R8 = blocks wanted

	; Clamp to what the host allows
	mov rax, r9
	xor edx, edx
	div rbx
	cmp rax, r8
	cmovb r8, rax			; R8 = min(wanted, allowed)

	; Clamp to what the high page directory has room for
	mov eax, VIRTIO_MEM_PDE_MAX
	sub eax, [virtio_mem_pde_next]	; EAX = free 2 MiB PDEs
	shl rax, 21			; -> bytes
	xor edx, edx
	div rbx
	cmp rax, r8
	cmovb r8, rax

	; nb_blocks is a 16-bit field
	mov eax, 0xFFFF
	cmp r8, rax
	cmova r8, rax

	test r8, r8
	jz virtio_mem_grow_done

	; Build the PLUG request (struct virtio_mem_req, 24 bytes)
	mov rdi, virtio_mem_req
	xor eax, eax
	stosq				; type = VIRTIO_MEM_REQ_PLUG (0), padding
	mov rax, [virtio_mem_addr]
	add rax, r10
	stosq				; addr = region start + plugged_size
	mov rax, r8
	stosq				; nb_blocks (16-bit) + padding

	call virtio_mem_request		; Submit it and wait for the device

	cmp word [virtio_mem_resp], VIRTIO_MEM_RESP_ACK
	jne virtio_mem_grow_done	; NACK/BUSY/ERROR - leave everything as it was

	; The blocks are ours. Map them: R8 blocks of RBX bytes each, starting
	; at physical [virtio_mem_addr]+R10, appended to the app's window
	mov rax, r8
	mul rbx				; RAX = bytes plugged
	mov rcx, rax
	shr rax, 20
	add [os_MemAmount], eax		; Grow what b_system(FREE_MEMORY) reports
	shr rcx, 21			; RCX = number of 2 MiB pages to map
	mov rax, [virtio_mem_addr]
	add rax, r10
	or rax, 0x87			; Bits 0 (P), 1 (R/W), 2 (U/S - app runs in ring 3), and 7 (PS) set
	mov edi, [virtio_mem_pde_next]
virtio_mem_grow_map:
	test edi, 0x1FF
	jnz virtio_mem_grow_map_pde	; Not the first PDE of a page directory
	; Crossing into a new 4 KiB page directory (1 GiB of window): make sure
	; the high PDPT has an entry pointing at it. Init only created entries
	; for the boot RAM (plus one spare), the rest are still zero
	push rax
	mov eax, edi
	shr eax, 9			; PDPT index
	mov edx, eax
	shl edx, 12			; PDs are 4 KiB apart
	add edx, sys_pdh | 0x07		; Bits 0 (P), 1 (R/W), 2 (U/S) set
	mov [sys_pdph+rax*8], rdx
	pop rax
virtio_mem_grow_map_pde:
	mov [sys_pdh+rdi*8], rax
	add rax, 0x200000		; Next 2 MiB page
	inc edi
	dec rcx
	jnz virtio_mem_grow_map
	mov [virtio_mem_pde_next], edi

	; Reload CR3 so the paging-structure caches pick up the new entries
	mov rax, cr3
	mov cr3, rax

virtio_mem_grow_done:
	mov eax, [os_MemAmount]

	pop r10
	pop r9
	pop r8
	pop rdi
	pop rsi
	pop rdx
	pop rcx
	pop rbx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; virtio_mem_request -- Submit virtio_mem_req on queue 0 and wait for it
; IN:	RSI = Device MMIO base
; OUT:	Nothing. The device's reply is in virtio_mem_resp
;	All registers preserved
virtio_mem_request:
	push rdi
	push rbx
	push rax

	; Descriptor 0 - the request (device-readable), chained to descriptor 1
	mov rdi, virtio_mem_desc
	mov eax, virtio_mem_req
	stosq				; 64-bit address
	mov eax, VIRTIO_MEM_REQ_SIZE
	stosd				; 32-bit length
	mov ax, VIRTQ_DESC_F_NEXT
	stosw				; 16-bit flags
	mov ax, 1
	stosw				; 16-bit next

	; Descriptor 1 - the response (device-writable)
	mov eax, virtio_mem_resp
	stosq
	mov eax, VIRTIO_MEM_RESP_SIZE
	stosd
	mov ax, VIRTQ_DESC_F_WRITE
	stosw
	xor eax, eax
	stosw

	; Poison the response type so a reply that never lands is never
	; mistaken for an ACK
	mov word [virtio_mem_resp], 0xFFFF

	; Available ring: ring[idx % queue size] = 0 (descriptor chain head)
	mov rdi, virtio_mem_avail
	movzx eax, word [virtio_mem_availindex]
	and eax, VIRTIO_MEM_QUEUE_SIZE-1
	mov word [rdi+4+rax*2], 0

	; Increment first, then publish the new idx
	inc word [virtio_mem_availindex]
	mov ax, VIRTQ_AVAIL_F_NO_INTERRUPT
	mov [rdi], ax			; flags: suppress interrupt, this is polled
	mov ax, [virtio_mem_availindex]
	mov [rdi+2], ax			; avail_ring.idx = post-increment value

	; Notify the queue
	xor eax, eax
	mov [rsi+VIRTIO_MMIO_QUEUE_NOTIFY], eax

	; Wait for used_ring.idx to reach availindex
	mov rdi, virtio_mem_used
	mov bx, [virtio_mem_availindex]
virtio_mem_request_wait:
	; TODO - Add a timeout (same caveat as the virtio-blk driver)
	pause
	mov ax, [rdi+2]
	cmp ax, bx
	jne virtio_mem_request_wait

	; Acknowledge anything the device flagged (a config change from a
	; host-side PATCH, for instance) so the line doesn't stay asserted
	mov eax, [rsi+VIRTIO_MMIO_INT_STATUS]
	test eax, eax
	jz virtio_mem_request_done
	mov [rsi+VIRTIO_MMIO_INT_ACK], eax

virtio_mem_request_done:
	pop rax
	pop rbx
	pop rdi
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; virtio_mem_cfg64 -- Read a 64-bit field from the device config space
; IN:	RSI = Device MMIO base
;	ECX = Field offset within the config space
; OUT:	RAX = Value
;	All other registers preserved
; Note:	The virtio-mmio spec only permits 32-bit accesses to config fields, so
;	64-bit fields are read as two halves
virtio_mem_cfg64:
	push rbx
	mov eax, [rsi+rcx+VIRTIO_MMIO_CONFIG_SPACE+4]
	shl rax, 32
	mov ebx, [rsi+rcx+VIRTIO_MMIO_CONFIG_SPACE]
	or rax, rbx
	pop rbx
	ret
; -----------------------------------------------------------------------------


; Variables
virtio_mem_availindex:	dw 0
virtio_mem_waited:	db 0		; Set once virtio_mem_grow has waited for the host's first budget
virtio_mem_pde_next:	dd 0		; Index of the next free entry in the high page directory (sys_pdh)
virtio_mem_block_size:	dq 0		; Bytes per block, from the config space
virtio_mem_addr:	dq 0		; Guest-physical start of the device's region, from the config space

; Virtqueue and buffer layout inside os_mem_mem (4 KiB, see sysvar.asm)
VIRTIO_MEM_QUEUE_SIZE			equ 2	; Descriptors per queue (power of two). One request is in flight at a time
VIRTIO_MEM_PDE_MAX			equ 65536 ; Entries in the high page directory (sys_pdh is 512 KiB / 8 bytes = 128 GiB of 2 MiB pages)
VIRTIO_MEM_BUDGET_WAIT_NS		equ 2000000000 ; How long the first virtio_mem_grow waits for the host to publish a budget (2 s)
virtio_mem_desc				equ os_mem_mem + 0x000	; Descriptor table (16 bytes per descriptor)
virtio_mem_avail			equ os_mem_mem + 0x100	; Available ring
virtio_mem_used				equ os_mem_mem + 0x200	; Used ring
virtio_mem_req				equ os_mem_mem + 0x300	; struct virtio_mem_req
virtio_mem_resp				equ os_mem_mem + 0x340	; struct virtio_mem_resp

; Virtqueue constants shared with the other virtio drivers but not defined there
VIRTQ_AVAIL_F_NO_INTERRUPT		equ 1
VIRTIO_F_VERSION_1			equ 32	; Transport feature bit: modern (non-legacy) device

; VIRTIO MEM Config space (offsets from VIRTIO_MMIO_CONFIG_SPACE)
VIRTIO_MEM_BLOCK_SIZE			equ 0x00 ; 64-bit Block size and alignment
VIRTIO_MEM_NODE_ID			equ 0x08 ; 16-bit NUMA node (only with VIRTIO_MEM_F_ACPI_PXM)
VIRTIO_MEM_ADDR				equ 0x10 ; 64-bit Guest-physical start of the region
VIRTIO_MEM_REGION_SIZE			equ 0x18 ; 64-bit Size of the region
VIRTIO_MEM_USABLE_REGION_SIZE		equ 0x20 ; 64-bit Currently usable prefix of the region
VIRTIO_MEM_PLUGGED_SIZE			equ 0x28 ; 64-bit Total plugged so far
VIRTIO_MEM_REQUESTED_SIZE		equ 0x30 ; 64-bit Amount the host wants plugged (the plug ceiling)

; VIRTIO_DEVICEFEATURES bits
VIRTIO_MEM_F_ACPI_PXM			equ 0 ; node_id is valid
VIRTIO_MEM_F_UNPLUGGED_INACCESSIBLE	equ 1 ; Unplugged blocks must never be touched
VIRTIO_MEM_F_PERSISTENT_SUSPEND		equ 2 ; Plugged memory survives suspend

; VIRTIO MEM Request types (struct virtio_mem_req, 24 bytes)
VIRTIO_MEM_REQ_PLUG			equ 0
VIRTIO_MEM_REQ_UNPLUG			equ 1
VIRTIO_MEM_REQ_UNPLUG_ALL		equ 2
VIRTIO_MEM_REQ_STATE			equ 3
VIRTIO_MEM_REQ_SIZE			equ 24

; VIRTIO MEM Response types (struct virtio_mem_resp, 10 bytes)
VIRTIO_MEM_RESP_ACK			equ 0
VIRTIO_MEM_RESP_NACK			equ 1
VIRTIO_MEM_RESP_BUSY			equ 2
VIRTIO_MEM_RESP_ERROR			equ 3
VIRTIO_MEM_RESP_SIZE			equ 10


; =============================================================================
; EOF
