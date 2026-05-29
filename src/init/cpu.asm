; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; CPU initialization
; =============================================================================


; -----------------------------------------------------------------------------
init_cpu:
	; Flush Cache
	wbinvd

	; Flush TLB
	mov rax, cr3
	mov cr3, rax

; On system power-up/reset the PAT is configured as WB, WT, UC-, UC, WB, WT, UC-, UC for entries 0-7
; PA0-3 are left at system default
; PA4-7 are reconfigured to enable WP and WC
; The following table is used to set a mapped page to a specific PAT
; PAT = Bit 12, PCD = Bit 4, PWT = Bit 3
;	PAT	PCD	PWT	PAT Entry	Type
;	0	0	0	PAT0		WB
;	0	0	1	PAT1		WT
;	0	1	0	PAT2		UC-
;	0	1	1	PAT3		UC
;	1	0	0	PAT4		WP
;	1	0	1	PAT5		WC
;	1	1	0	PAT6		UC
;	1	1	1	PAT7		UC
	mov edx, 0x00000105		; PA7 UC (00), PA6 UC (00), PA5 WC (01), PA4 WP (05)
	mov eax, 0x00070406		; PA3 UC (00), PA2 UC- (07), PA1 WT (04), PA0 WB (06)
	mov ecx, IA32_PAT
	wrmsr

	; Enable Cache
	mov rax, cr0
	btr rax, 29			; Clear No Write Thru (Bit 29)
	btr rax, 30			; Clear CD (Bit 30)
	mov cr0, rax

	; Enable Floating Point
	mov rax, cr0
	bts rax, 1			; Set Monitor co-processor (Bit 1)
	btr rax, 2			; Clear Emulation (Bit 2)
	mov cr0, rax

	; Enable SSE
	mov rax, cr4
	bts rax, 9			; Set Operating System Support for FXSAVE and FXSTOR instructions (Bit 9)
	bts rax, 10			; Set Operating System Support for Unmasked SIMD Floating-Point Exceptions (Bit 10)
	mov cr4, rax

	; Enable Math Co-processor
	finit

	; Enable AVX-1 and AVX-2
	mov eax, 1			; CPUID Feature information 1
	cpuid				; Sets info in ECX and EDX
	bt ecx, 28			; AVX-1 is supported if bit 28 is set in ECX
					; AVX-2 is supported if bit 5 is set in EBX on CPUID (EAX=7, ECX=0)
	jnc avx_not_supported		; Skip activating AVX if not supported
avx_supported:
	mov rax, cr4
	bts rax, 18			; Enable OSXSAVE (Bit 18)
	mov cr4, rax
	xor ecx, ecx			; Set load XCR0
	xgetbv				; Load XCR0 register
	bts rax, 0			; Set X87 enable (Bit 0)
	bts rax, 1			; Set SSE enable (Bit 1)
	bts rax, 2			; Set AVX enable (Bit 2)
	xsetbv				; Save XCR0 register
avx_not_supported:

	; Enable AVX-512
	mov eax, 7			; CPUID Feature information 7
	xor ecx, ecx			; Extended Features 0
	cpuid				; Sets info in EBX, ECX, and EDX
	bt ebx, 16			; AVX-512 is supported if bit 16 is set in EBX
	jnc avx512_not_supported
avx512_supported:
	xor ecx, ecx			; Set load XCR0
	xgetbv				; Load XCR0 register
	bts rax, 5			; Set OPMASK (Bit 5)
	bts rax, 6			; Set ZMM_Hi256 (Bit 6)
	bts rax, 7			; Set Hi16_ZMM (Bit 7)
	xsetbv				; Save XCR0 register
avx512_not_supported:

	ret
; -----------------------------------------------------------------------------


; MSR List
IA32_APIC_BASE		equ 0x01B
IA32_MTRRCAP		equ 0x0FE
IA32_MISC_ENABLE	equ 0x1A0
IA32_MTRR_PHYSBASE0	equ 0x200
IA32_MTRR_PHYSMASK0	equ 0x201
IA32_MTRR_PHYSBASE1	equ 0x202
IA32_MTRR_PHYSMASK1	equ 0x203
IA32_PAT		equ 0x277
IA32_MTRR_DEF_TYPE	equ 0x2FF

; APIC Register list
; 0x000 - 0x010 are Reserved
APIC_ID		equ 0x020		; ID Register
APIC_VER	equ 0x030		; Version Register
; 0x040 - 0x070 are Reserved
APIC_TPR	equ 0x080		; Task Priority Register
APIC_APR	equ 0x090		; Arbitration Priority Register
APIC_PPR	equ 0x0A0		; Processor Priority Register
APIC_EOI	equ 0x0B0		; End Of Interrupt
APIC_RRD	equ 0x0C0		; Remote Read Register
APIC_LDR	equ 0x0D0		; Logical Destination Register
APIC_DFR	equ 0x0E0		; Destination Format Register
APIC_SPURIOUS	equ 0x0F0		; Spurious Interrupt Vector Register
APIC_ISR	equ 0x100		; In-Service Register (Starting Address)
APIC_TMR	equ 0x180		; Trigger Mode Register (Starting Address)
APIC_IRR	equ 0x200		; Interrupt Request Register (Starting Address)
APIC_ESR	equ 0x280		; Error Status Register
; 0x290 - 0x2E0 are Reserved
APIC_ICRL	equ 0x300		; Interrupt Command Register (low 32 bits)
APIC_ICRH	equ 0x310		; Interrupt Command Register (high 32 bits)
APIC_LVT_TMR	equ 0x320		; LVT Timer Register
APIC_LVT_TSR	equ 0x330		; LVT Thermal Sensor Register
APIC_LVT_PERF	equ 0x340		; LVT Performance Monitoring Counters Register
APIC_LVT_LINT0	equ 0x350		; LVT LINT0 Register
APIC_LVT_LINT1	equ 0x360		; LVT LINT1 Register
APIC_LVT_ERR	equ 0x370		; LVT Error Register
APIC_TMRINITCNT	equ 0x380		; Initial Count Register (for Timer)
APIC_TMRCURRCNT	equ 0x390		; Current Count Register (for Timer)
; 0x3A0 - 0x3D0 are Reserved
APIC_TMR_DIV	equ 0x3E0		; Divide Configuration Register (for Timer)
; 0x3F0 is Reserved


; =============================================================================
; EOF
