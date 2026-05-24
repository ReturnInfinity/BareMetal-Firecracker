; =============================================================================
; BareMetal Firecracker Init
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; This init code is for the BareMetal Exokernel.
;
; Firecracker builds a Linux-style `boot_params` structure in memory. The
; address of the structure is passed in RSI.
;
; This code will do the following:
; - Parse the command line - will look something like "console=ttyS0 reboot=k panic=1 pci=off pci=off root=/dev/vda rw virtio_mmio.device=4K@0xc0001000:5 virtio_mmio.device=4K@0xc0002000:6"
; - Parse the E820 memory map
; - Install the GDT, IDT, and PML4 that BareMetal expects
; - Build the "Pure64"-style info map that BareMetal expects
; - Copy kernel copy 'stub' to 0x6000
; - Start execution at 0x6000
; - Copy kernel and its payload to 0x100000
; - Start execution at 0x100000
;
; Build:
; nasm -f elf64 init.asm -o ../baremetal.o
; objcopy --input-target binary --output-target elf64-x86-64 --binary-architecture i386:x86-64 --rename-section .data=.kernel PAYLOAD.file kernel_sys.o
; ld -m elf_x86_64 -nostdlib -z max-page-size=0x1000 -T baremetal.ld -o baremetal.elf baremetal.o kernel_sys.o
; =============================================================================

BITS 64

; A few Linux boot_params offsets that are useful to inspect.
; These are standard x86 boot protocol offsets inside struct boot_params.
; With Firecracker most of the boot_params fields are unused.
; https://github.com/torvalds/linux/blob/master/arch/x86/include/uapi/asm/bootparam.h#L116
%define BP_HDR_RSDP_ADDR	0x0070
%define BP_HDR_BOOT_FLAG	0x01FE
%define BP_HDR_HEADER		0x0202
%define BP_HDR_TYPE_OF_LOADER	0x0210
%define BP_HDR_LOADFLAGS	0x0211
%define BP_HDR_CMD_LINE_PTR	0x0228	; 32-bit pointer
%define BP_EXT_CMD_LINE_PTR	0x00C8	; 32-bit pointer
%define BP_E820_ENTRIES		0x01E8	; 8-bit - Number of E820 memory map entries (starts at 0x2D0)
%define BP_E820_TABLE		0x02D0	; E820 memory map

global startup_64

section .text align=16

startup_64:
	cli				; Disable interrupts
	cld				; Clear direction flag

	; Set a new stack
	; Firecracker sets RSP and RBP to 0x8FF0
	; We will set it to 0x6FF0. 0x6000-0x6FFF is for PVH info page
	mov eax, 0x6FF0
	mov esp, eax		; Set the stack pointer
	mov ebp, eax

	; Check for hypervisor presence
	mov eax, 1
	cpuid
	bt ecx, 31			; HV - hypervisor present
	jnc error			; If bit is clear then jump to error

	call init_timer			; Configure the timer

	; Gather T0
	call kvm_get_usec		; Gather microseconds since powerup
	mov [t0], rax

	; Check if boot_params pointer is set to a value other than 0
	cmp esi, 0
	je error

	; Check the address of the boot_params data
	cmp esi, 0x7000			; Firecracker source hardcodes this
	je good_boot			; Verify
	mov eax, esi			; If not, dump the address and shut down
	call debug_dump_eax
	jmp shutdown
good_boot:

	; Save Linux boot_params pointer from ESI
	mov edi, boot_params_ptr
	mov [edi], esi

%ifdef DEBUG
	; Display banner
	mov esi, msg_banner
	call debug_msg
	mov esi, msg_banner_start
	call debug_msg
%endif

	; Display debug info
;	call init_debug

	; Copy cmd_line_ptr data to somewhere else just in case the kernel wants to see it
	; 0x20000 is used later on for the PD High table
	mov edi, boot_params_ptr
	mov ebx, [edi]
	mov esi, [ebx + BP_HDR_CMD_LINE_PTR]
	mov edi, 0x5A00
	mov ecx, 256
	rep movsb
	; Clear the old cmdline data memory as the PD high table is built there
	mov edi, boot_params_ptr
	mov ebx, [edi]
	mov edi, [ebx + BP_HDR_CMD_LINE_PTR]
	xor eax, eax
	mov ecx, 256/8
	rep stosq

	; Parse the Virtio MMIO devices provided in the cmdline
	; cmd_line_ptr: 00020000
	; ext_cmd_line_ptr: 00000000
	; cmdline: "console=ttyS0 reboot=k panic=1 pci=off pci=off root=/dev/vda rw virtio_mmio.device=4K@0xc0001000:5 virtio_mmio.device=4K@0xc0002000:6"
	; Ex : virtio_mmio.device=4K@0xc0001000:5
	; Device has 4KB of MMIO, Base is 0xc0001000, IRQ is 5
	; Build a table in the "Pure64" data space at 0x5800
	; TODO Parse it (in the meantime write values manually)
	mov edi, 0x5800
	mov eax, 0xc0001000
	stosd
	mov eax, 5
	stosd
	mov eax, 0xc0002000
	stosd
	mov eax, 6
	stosd
	mov eax, 0xffffffff
	stosd
	stosd

; Start of system init

	; Mask all PIC interrupts
	mov al, 0xFF
	out 0x21, al
	out 0xA1, al

	; Initialize and remap PIC IRQ's
	; ICW1
	mov al, 0x11			; Initialize PIC 1, init (bit 4) and ICW4 (bit 0)
	out 0x20, al
	mov al, 0x11			; Initialize PIC 2, init (bit 4) and ICW4 (bit 0)
	out 0xA0, al
	; ICW2
	mov al, 0x20			; IRQ 0-7: interrupts 20h-27h
	out 0x21, al
	mov al, 0x28			; IRQ 8-15: interrupts 28h-2Fh
	out 0xA1, al
	; ICW3
	mov al, 4
	out 0x21, al
	mov al, 2
	out 0xA1, al
	; ICW4
	mov al, 1
	out 0x21, al
	mov al, 1
	out 0xA1, al

	; Disable PIT
	mov al, 0x30			; Channel 0 (7:6), Access Mode lo/hi (5:4), Mode 0 (3:1), Binary (0)
	out 0x43, al
	mov al, 0x00
	out 0x40, al

	; Copy the GDT to its final location in memory at 0x1000
	mov esi, gdt64
	mov edi, 0x00001000		; GDT address
	mov ecx, (gdt64_end - gdt64)
	rep movsb			; Copy it to final location

; Create the Page Map Level 4 Entries (PML4E)
; PML4 is stored at 0x0000000000002000, create the first entry there
; A single PML4 entry can map 512GiB
; A single PML4 entry is 8 bytes in length

	mov edi, 0x00002000		; Create a PML4 entry for physical memory
	mov eax, 0x00003003		; Bits 0 (P), 1 (R/W), location of low PDP (4KiB aligned)
	stosq
	mov edi, 0x00002800		; Create a PML4 entry for higher half (starting at 0xFFFF800000000000)
	mov eax, 0x00004003		; Bits 0 (P), 1 (R/W), location of high PDP (4KiB aligned)
	stosq

; 2MiB Pages
; Create the Low Page-Directory-Pointer-Table Entries (PDPTE)
; PDPTE starts at 0x0000000000003000, create the first entry there
; A single PDPTE can map 1GiB
; A single PDPTE is 8 bytes in length
; A PDPTE points to 4KiB of memory which contains 512 PDEs
; FIXME - This will completely fill the 64K set for the low PDE (only 16GiB identity mapped)

	mov ecx, 16			; number of PDPE's to make.. each PDPE maps 1GiB of physical memory
	mov edi, 0x00003000		; location of low PDPE
	mov eax, 0x00010003		; Bits 0 (P), 1 (R/W), location of first low PD (4KiB aligned)
pdpte_low:
	stosq
	add rax, 0x00001000		; 4KiB later (512 records x 8 bytes)
	dec ecx
	jnz pdpte_low

; Create the Low Page-Directory Entries (PDE)
; A single PDE can map 2MiB of RAM
; A single PDE is 8 bytes in length

	mov ecx, 2048			; Create 2048 2MiB page maps
	mov edi, 0x00010000		; Location of first PDE
	mov eax, 0x00000083		; Bits 0 (P), 1 (R/W), and 7 (PS) set
pde_low:				; Create a 2MiB page
	stosq
	add rax, 0x00200000		; Increment by 2MiB
	dec ecx
	jnz pde_low

	; Load the GDT
	lgdt [GDTR64]

	; Point cr3 at PML4
	mov eax, 0x00002008		; Write-thru enabled (Bit 3)
	mov cr3, rax

	; Set segments based on new GDT
	; TODO Is this needed?
	mov ax, 0x10
	mov ds, ax
	mov es, ax
	mov ss, ax
	mov fs, ax
	mov gs, ax

	; Set CS with a far return
	push SYS64_CODE_SEL
	push clearcs64
	retfq
clearcs64:

	lgdt [GDTR64]			; Reload the GDT

	; Build the IDT at 0x0000
	xor edi, edi 			; create the 64-bit IDT (at linear address 0x0000000000000000)

	mov ecx, 32
make_exception_gates: 			; make gates for exception handlers
	mov eax, exception_gate
	push rax			; save the exception gate to the stack for later use
	stosw				; store the low word (15:0) of the address
	mov ax, SYS64_CODE_SEL
	stosw				; store the segment selector
	mov ax, 0x8E00
	stosw				; store exception gate marker
	pop rax				; get the exception gate back
	shr rax, 16
	stosw				; store the high word (31:16) of the address
	shr rax, 16
	stosd				; store the extra high dword (63:32) of the address.
	xor eax, eax
	stosd				; reserved
	dec ecx
	jnz make_exception_gates

	mov ecx, 256-32
make_interrupt_gates: 			; make gates for the other interrupts
	mov eax, interrupt_gate
	push rax			; save the interrupt gate to the stack for later use
	stosw				; store the low word (15:0) of the address
	mov ax, SYS64_CODE_SEL
	stosw				; store the segment selector
	mov ax, 0x8F00
	stosw				; store interrupt gate marker
	pop rax				; get the interrupt gate back
	shr rax, 16
	stosw				; store the high word (31:16) of the address
	shr rax, 16
	stosd				; store the extra high dword (63:32) of the address.
	xor eax, eax
	stosd				; reserved
	dec ecx
	jnz make_interrupt_gates

	; Set up the exception gates for all of the CPU exceptions
	; The following code depends on:
	; - Exception gates being below 16MB
	; - Each exception_gate_XX being exactly 4 bytes apart
	mov eax, exception_gate_00	; Address of first handler
	xor edi, edi			; Clear EDI as IDT starts at 0x0000
	mov cl, 22			; 22 exception gates (0x00-0x15)
set_exception_gate:
	mov [rdi], ax			; Patch low word of handler address in IDT entry
	add edi, 16			; Advance to next IDT entry (16 bytes each)
	add eax, 24			; Advance to next gate handler (24 bytes each)
	dec cl
	jnz set_exception_gate

	lidt [IDTR64]			; load IDT register

; Parse the E820 memory map
	mov edi, boot_params_ptr
	mov esi, [edi]
	xor ecx, ecx
	mov cl, [esi + BP_E820_ENTRIES]
	add esi, BP_E820_TABLE

memmap:
; Stage 1 - Process the E820 memory map to find all possible 2MiB pages that are free to use
; Build an available memory map at 0x5900
	xor ecx, ecx
	xor ebx, ebx			; Running counter of available MiBs
	mov edi, 0x5900
memmap_nextentry:
	add esi, 16			; Skip ESI to type marker
	mov eax, [esi]			; Load the 32-bit type marker
	cmp eax, 0			; End of the list?
	je memmap_end820
	cmp eax, 1			; Is it marked as free?
	je memmap_processfree
	add esi, 4			; Skip ESI to start of next entry
	jmp memmap_nextentry
memmap_processfree:
	; TODO Check ACPI 3.0 Extended Attributes - Bit 0 should be set
	sub esi, 16
	mov rax, [rsi]			; Physical start address
	add esi, 8
	mov rcx, [rsi]			; Physical length
	add esi, 12
	shr rcx, 20			; Convert bytes to MiB
	cmp rcx, 0			; Do we have at least 1 page?
	je memmap_nextentry
	stosq
	mov rax, rcx
	stosq
	add ebx, ecx
	jmp memmap_nextentry
memmap_end820:
	add ebx, 1			; Add for first 1MiB

; Stage 2 - Sanitize the records
	mov esi, 0x5900
memmap_sani:
	mov rax, [rsi]
	cmp rax, 0
	je memmap_saniend
	bt rax, 20
	jc memmap_itsodd
	add esi, 16
	jmp memmap_sani
memmap_itsodd:
	add rax, 0x100000
	mov [rsi], rax
	mov rax, [rsi+8]
	sub rax, 1
	mov [rsi+8], rax
	add esi, 16
	jmp memmap_sani
memmap_saniend:
	mov dword [p_mem_amount], ebx
	mov ecx, ebx
	xor eax, eax
	stosq
	stosq

	; Check if VM wasn't given at least 4MiB total
	; If the app runs in kernel memory (the first 2 MiB) then this check isn't needed
	cmp ecx, 4
	jb error

; Create the High Page-Directory-Pointer-Table Entries (PDPTE)
; High PDPTE is stored at 0x0000000000004000, create the first entry there
; A single PDPTE can map 1GiB with 2MiB pages
; A single PDPTE is 8 bytes in length
	shr ecx, 10			; MBs -> GBs
	add rcx, 1			; Add 1. This is the number of PDPE's to make
	mov edi, 0x00004000		; location of high PDPE
	mov eax, 0x00020003		; location of first high PD. Bits 0 (P) and 1 (R/W) set
create_pdpe_high:
	stosq
	add rax, 0x00001000		; 4K later (512 records x 8 bytes)
	dec ecx
	jnz create_pdpe_high

; Create the High Page-Directory Entries (PDE).
; A single PDE can map 2MiB of RAM
; A single PDE is 8 bytes in length
	mov esi, 0x00005900		; Location of the available memory map
	mov edi, 0x00020000		; Location of first PDE
pde_next_range:
	lodsq				; Load the base
	xchg rax, rcx
	lodsq				; Load the length
	xchg rax, rcx
	cmp rax, 0			; Check if at end of records
	je pde_end			; Bail out if so
	shr ecx, 1			; Quick divide by 2 for 2 MB pages
	add rax, 0x00000083		; Bits 0 (P), 1 (R/W), and 7 (PS) set
pde_high:				; Create a 2MiB page
	stosq
	add rax, 0x00200000		; Increment by 2MiB
	dec ecx
	jnz pde_high
	jmp pde_next_range
pde_end:

; Build the InfoMap
	xor edi, edi
	mov edi, 0x5000

	mov rax, [t0]
	mov edi, 0x5050
	stosq

	; Read APIC Address from MSR and enable it (if not done so already)
	mov ecx, 0x01B			; IA32_APIC_BASE
	rdmsr				; Returns APIC in EDX:EAX
	bts eax, 11			; EN - xAPIC global enable
	wrmsr
	and eax, 0xFFFFF000		; Clear lower 12 bits
	shl rdx, 32			; Shift lower 32 bits to upper 32 bits
	add rax, rdx
	mov edi, 0x5060
	stosq

	; Hardcode IO-APIC address as seen in Firecracker source code (layout.rs)
	mov eax, 0xFEC00000
	mov edi, 0x5604
	stosd

	; Gather T1
	call kvm_get_usec
	mov [t1], rax

	mov [t1], rax
	mov edi, 0x5058
	stosq

	mov eax, 1
	mov edi, 0x5012
	stosw
	stosw

	mov edi, 0x5020
	mov eax, [p_mem_amount]
	stosd

	mov ax, 1
	mov edi, 0x5090
	stosw

	mov al, 'F'
	mov edi, 0x50E2
	stosb

	; Dump ticks elapsed
;	mov rbx, [t0]
;	mov rax, [t1]
;	sub rax, rbx		; RAX = RAX - RBX
;	call debug_dump_rax
;	call debug_newline

	; Copy stub to some other memory address
	mov rsi, stub
	mov rdi, 0x6000
	mov rcx, 32
	rep movsb


;	mov esi, 0x5000
;	mov ecx, 4096
;	nb:
;	lodsb
;	call debug_dump_al
;	dec ecx
;	jnz nb

%ifdef DEBUG
	; Output shutdown message
	mov esi, msg_banner_stop
	call debug_msg
	mov esi, msg_banner
	call debug_msg
%endif

	; jump to stub
	mov eax, 0x6000
	jmp rax


;------------------------------------------------------------------------------
; shutdown - Stop a Firecracker VM
;------------------------------------------------------------------------------
shutdown:
	; Output shutdown message
	mov esi, msg_banner_stop
	call debug_msg
	mov esi, msg_banner
	call debug_msg
	; Keyboard reset method
	mov al, 0xFE
	out 0x64, al
	; Execution should never reach the code below
shutdown_hang:
	hlt
	jmp shutdown_hang
;------------------------------------------------------------------------------


;------------------------------------------------------------------------------
error:
	mov esi, msg_error
	call debug_msg		; Display an error message
	jmp shutdown		; Shut down
;------------------------------------------------------------------------------


;------------------------------------------------------------------------------
; This code gets copied to 0x6000 and init jmps to it
align 16
stub:
	; Move kernel and its payload to 0x100000
	mov rsi, 0x101000	; Wherever the kernel starts
	mov rdi, 0x100000
	mov rcx, 32768/8	; Move 32KiB
	rep movsq
	; stub jumps to kernel
	mov eax, 0x100000
	jmp rax			; Jump to BareMetal kernel
;------------------------------------------------------------------------------


%include "interrupt.asm"
%include "timer.asm"
%include "debug.asm"

; x86-64 structures
sys_idt:		equ 0x0000000000000000	; 0x000000 -> 0x000FFF	4K Interrupt descriptor table
sys_gdt:		equ 0x0000000000001000	; 0x001000 -> 0x001FFF	4K Global descriptor table
sys_pml4:		equ 0x0000000000002000	; 0x002000 -> 0x002FFF	4K PML4 table
sys_pdpl:		equ 0x0000000000003000	; 0x003000 -> 0x003FFF	4K PDP table low
sys_pdph:		equ 0x0000000000004000	; 0x004000 -> 0x004FFF	4K PDP table high

SystemVariables:	equ 0x0000000000005800

; DQ - Starting at offset 0, increments by 0x8
p_LocalAPICAddress:	equ SystemVariables + 0x10	; Address of the Local APIC (xAPIC)
sys_timer:		equ SystemVariables + 0x30

; DD - Starting at offset 0x80, increments by 4
p_BSP:			equ SystemVariables + 0x80
p_mem_amount:		equ SystemVariables + 0x84	; in MiB

; DW - Starting at offset 0x100, increments by 2
p_cpu_speed:		equ SystemVariables + 0x100
p_cpu_activated:	equ SystemVariables + 0x102
p_cpu_detected:		equ SystemVariables + 0x104

; DB - Starting at offset 0x180, increments by 1
p_IOAPICCount:		equ SystemVariables + 0x180
p_BootMode:		equ SystemVariables + 0x181	; 'U' for UEFI, otherwise BIOS
p_IOAPICIntSourceC:	equ SystemVariables + 0x182

p_BootDisk:		equ SystemVariables + 0x185	; 'F' for Floppy drive
p_1GPages:		equ SystemVariables + 0x186	; 1 if 1GB pages are supported

p_timer:		equ SystemVariables + 0x1000	; This overwrites the memory details from firmware

t0: dq 0
t1: dq 0

section .rodata align=16
msg_banner:		db "============================================================", 13, 10, 0
msg_banner_start:	db "BareMetal Init Start", 13, 10, 0
msg_banner_stop:	db "BareMetal Init Stop", 13, 10, 0
msg_error:		db "ERROR", 13, 10, 0
msg_newline:		db 13, 10, 0
msg_space:		db " ", 0
msg_boot_flag:		db "boot_flag: ", 0
msg_header:		db "header: ", 0
msg_e820_entries:	db "e820_entries: ", 0
msg_rsdp:		db "rsdp: ", 0
msg_cmdline_ptr:	db "cmd_line_ptr: ", 0
msg_ext_cmdline_ptr:	db "ext_cmd_line_ptr: ", 0
msg_cmdline:		db "cmdline: ", 0
msg_cmdline_none:	db "cmdline: <none>", 13, 10, 0

section .data align=16

align 16
GDTR64:					; Global Descriptors Table Register
dw gdt64_end - gdt64 - 1		; limit of GDT (size minus one)
dq 0x0000000000001000			; linear address of GDT

gdt64:					; This structure is copied to 0x0000000000001000
SYS64_NULL_SEL equ $-gdt64		; Null Segment
dq 0x0000000000000000
SYS64_CODE_SEL equ $-gdt64		; Code segment, read/execute, nonconforming
dq 0x00209A0000000000			; 53 Long mode code, 47 Present, 44 Code/Data, 43 Executable, 41 Readable
SYS64_DATA_SEL equ $-gdt64		; Data segment, read/write, expand down
dq 0x0000920000000000			; 47 Present, 44 Code/Data, 41 Writable
gdt64_end:

IDTR64:					; Interrupt Descriptor Table Register
dw 256*16-1				; limit of IDT (size minus one) (4096 bytes - 1)
dq 0x0000000000000000			; linear address of IDT

boot_params_ptr:
	dd 0


section .bss align=16


; =============================================================================
; EOF
