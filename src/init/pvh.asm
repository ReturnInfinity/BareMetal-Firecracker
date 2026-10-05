; =============================================================================
; BareMetal Firecracker Init
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; PVH boot entry
;
; The Xen PVH boot ABI is how QEMU (-kernel with -M microvm or pc/q35) boots an
; uncompressed ELF, and Firecracker uses it too whenever the ELF carries the
; XEN_ELFNOTE_PHYS32_ENTRY note below. The VMM enters startup_pvh in 32-bit
; protected mode with paging off, flat segments, and EBX pointing at a
; struct hvm_start_info.
;
; This stub converts hvm_start_info into the Linux boot_params fields that
; startup_64 reads (cmdline, RSDP, E820 map), builds a temporary identity map
; of the first 1GiB, enters long mode, and jumps to startup_64 with RSI
; pointing at the converted boot_params -- the same state Firecracker's Linux
; boot path hands over, so the rest of init is shared by both boot paths.
;
; https://xenbits.xen.org/docs/unstable/misc/pvh.html
; https://github.com/xen-project/xen/blob/master/xen/include/public/arch-x86/hvm/start_info.h
; =============================================================================

%define XEN_ELFNOTE_PHYS32_ENTRY	18

; struct hvm_start_info offsets
%define HVM_START_MAGIC		0x336EC578
%define HVM_MAGIC		0x00	; 32-bit - HVM_START_MAGIC
%define HVM_VERSION		0x04	; 32-bit - memmap fields exist from version 1
%define HVM_CMDLINE_PADDR	0x18	; 64-bit
%define HVM_RSDP_PADDR		0x20	; 64-bit
%define HVM_MEMMAP_PADDR	0x28	; 64-bit - array of hvm_memmap_table_entry
%define HVM_MEMMAP_ENTRIES	0x30	; 32-bit
; struct hvm_memmap_table_entry is 24 bytes: addr (64), size (64), type (32), reserved (32)
; An E820 entry is the same minus the reserved field (20 bytes)

; Memory used only until startup_64 switches to its own tables. The VMM's
; data lives elsewhere: Firecracker puts hvm_start_info at 0x6000, its memmap
; at 0x7000, and the cmdline at 0x20000
PVH_PD			equ 0xC000	; 512 2MiB entries - identity maps the first 1GiB
PVH_BOOT_PARAMS		equ 0xD000	; Converted boot_params handed to startup_64
PVH_PML4		equ 0xE000
PVH_PDPT		equ 0xF000
E820_MAX		equ 128		; boot_params has room for 128 E820 entries

section .note.Xen note alloc noexec nowrite align=4
	dd 4				; n_namesz
	dd 8				; n_descsz
	dd XEN_ELFNOTE_PHYS32_ENTRY	; n_type
	db "Xen", 0
	dq startup_pvh			; Physical 32-bit entry point

section .text

BITS 32

startup_pvh:
	cli
	cld

	lgdt [pvh_gdtr]			; Our GDT, the VMM's may be gone once we write low memory

	cmp dword [ebx + HVM_MAGIC], HVM_START_MAGIC
	jne pvh_error
	cmp dword [ebx + HVM_VERSION], 1	; Need the memmap fields
	jb pvh_error

	; Build boot_params
	mov edi, PVH_BOOT_PARAMS
	xor eax, eax
	mov ecx, 4096/4
	rep stosd
	mov edi, PVH_BOOT_PARAMS
	mov eax, [ebx + HVM_CMDLINE_PADDR]
	mov [edi + BP_HDR_CMD_LINE_PTR], eax
	mov eax, [ebx + HVM_RSDP_PADDR]
	mov [edi + BP_HDR_RSDP_ADDR], eax
	mov eax, [ebx + HVM_RSDP_PADDR + 4]
	mov [edi + BP_HDR_RSDP_ADDR + 4], eax

	; Convert the memmap to E820. The zeroed entry after the last one
	; terminates the list for startup_64
	mov esi, [ebx + HVM_MEMMAP_PADDR]
	mov ecx, [ebx + HVM_MEMMAP_ENTRIES]
	cmp ecx, E820_MAX
	jbe pvh_e820_count
	mov ecx, E820_MAX - 1
pvh_e820_count:
	mov [edi + BP_E820_ENTRIES], cl
	add edi, BP_E820_TABLE
	jecxz pvh_e820_done
pvh_e820_next:
	movsd				; addr
	movsd
	movsd				; size
	movsd
	movsd				; type
	add esi, 4			; Skip reserved
	loop pvh_e820_next
pvh_e820_done:

	; Identity map the first 1GiB with 2MiB pages
	mov edi, PVH_PML4
	xor eax, eax
	mov ecx, 8192/4			; Clear PML4 and PDPT
	rep stosd
	mov dword [PVH_PML4], PVH_PDPT | 3	; Bits 0 (P), 1 (R/W)
	mov dword [PVH_PDPT], PVH_PD | 3
	mov edi, PVH_PD
	mov eax, 0x00000083		; Bits 0 (P), 1 (R/W), and 7 (PS) set
	xor edx, edx
	mov ecx, 512
pvh_pde:
	mov [edi], eax
	mov [edi + 4], edx
	add eax, 0x00200000
	add edi, 8
	loop pvh_pde

	; Enter long mode
	mov eax, cr4
	bts eax, 5			; PAE
	mov cr4, eax
	mov eax, PVH_PML4
	mov cr3, eax
	mov ecx, 0xC0000080		; IA32_EFER
	rdmsr
	bts eax, 8			; LME
	wrmsr
	mov eax, cr0
	or eax, 0x80000001		; PG, PE
	mov cr0, eax
	jmp SYS64_CODE_SEL:pvh_long

pvh_error:
	; Keyboard reset method (Firecracker), otherwise hang
	mov al, 0xFE
	out 0x64, al
pvh_hang:
	hlt
	jmp pvh_hang

BITS 64

pvh_long:
	mov eax, SYS64_DATA_SEL
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov fs, ax
	mov gs, ax
	mov esi, PVH_BOOT_PARAMS
	jmp startup_64

section .data

pvh_gdtr:				; Uses the init GDT at its load address
dw gdt64_end - gdt64 - 1
dd gdt64

section .text

; =============================================================================
; EOF
