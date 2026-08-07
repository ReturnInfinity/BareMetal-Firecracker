; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; APIC Functions
; =============================================================================


; -----------------------------------------------------------------------------
; os_apic_init -- Initialize the APIC
;  IN:	Nothing
; OUT:	Nothing
;	All other registers preserved
os_apic_init:
	mov ecx, APIC_VER
	call os_apic_read
	mov [os_apic_ver], eax

	; Software-enable the APIC and configure spurious vector
	mov ecx, APIC_SPURIOUS
	call os_apic_read
	or eax, 0x1FF		; bit 8 = SW enable, bits 7:0 = 0xFF spurious vector
	call os_apic_write

	; Configure the LAPIC timer for TSC-deadline interrupts
	call os_apic_init_timer
	;TODO - check result - set flag as needed

	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_apic_read -- Read from a register in the APIC
;  IN:	ECX = Register to read
; OUT:	RAX = Register value
;	All other registers preserved
os_apic_read:
	mov rax, [os_LocalAPICAddress]
	mov eax, [rax + rcx]
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_apic_write -- Write to a register in the APIC/x2APIC
;  IN:	ECX = Register to write
;	RAX = Value to write
; OUT:	All registers preserved
os_apic_write:
	push rcx
	add rcx, [os_LocalAPICAddress]
	mov [rcx], eax
	pop rcx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_apic_init_timer -- Configure the LAPIC timer to fire one-shot interrupts via TSC-deadline mode
;  IN:	Nothing
; OUT:	CF set if the CPU doesn't support TSC-deadline mode (LAPIC timer left unconfigured)
os_apic_init_timer:
	; Check CPUID flags
	mov eax, 1
	cpuid
	bt ecx, 24			; CPUID.01H:ECX.TSC_Deadline [bit 24]
	jnc os_apic_init_timer_unsupported

	; Create the IDT entry for the timer interrupt
	mov edi, TIMER_VECTOR
	mov eax, int_apic_timer
	call create_gate

	; Switch the LVT Timer entry to TSC-deadline mode, unmasked, on our vector
	mov ecx, APIC_LVT_TMR
	mov eax, APIC_LVT_TSCDEADLINE | TIMER_VECTOR
	call os_apic_write

	; SDM Vol. 3A 10.5.4.1: a serializing/fencing instruction is required between enabling
	; TSC-deadline mode in the LVT and the first WRMSR to IA32_TSC_DEADLINE
	mfence

	clc				; Clear carry flag
	ret

os_apic_init_timer_unsupported:
	stc				; Set carry flag
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_apic_timer_set -- Fire the LAPIC timer interrupt (TIMER_VECTOR) after a delay
;  IN:	RAX = Delay in nanoseconds from now
; OUT:	All registers preserved
; Note:	Needs os_apic_timer_init to complete as well as init_timer_kvm to have configured the kvm_timer
;	(the ns-to-TSC ticks conversion reuses the KVM scale)
; TODO: Add checks for those items
os_apic_timer_set:
	push rdx
	push rcx
	push rbx
	push r10
	push r9
	push rdi

	mov rbx, rax			; RBX = requested delay in nanoseconds

	mov rdi, kvm_timer
os_apic_timer_set_wait:
	mov r10d, [rdi]			; Get 32-bit version
	test r10d, 1			; Check if version is odd (update in progress)
	jnz os_apic_timer_set_wait	; If so, retry

	lfence

	mov ecx, [rdi+pvclock_tsc_system_mul]
	xor r9d, r9d
	mov r9b, [rdi+pvclock_tsc_shift]

	; Convert the nanosecond delay to a raw TSC tick delta - the inverse of the scaling
	; kvm_ns applies: raw_ticks = (ns << 32) / tsc_to_system_mul, then un-apply tsc_shift
	mov rax, rbx
	mov rdx, rax
	shr rdx, 32
	shl rax, 32
	div rcx				; RAX = (ns << 32) / mul

	mov cl, r9b
	cmp cl, 0
	jl os_apic_timer_set_shift_left	; Signed comparison
	shr rax, cl
	jmp os_apic_timer_set_shift_done
os_apic_timer_set_shift_left:
	neg cl				; Ex: 0xFF = tsc shift of -1
	shl rax, cl
os_apic_timer_set_shift_done:
	mov rbx, rax			; RBX = delay in raw TSC ticks

	; Recheck struct version so mul/shift were read consistently
	lfence
	mov r9d, [rdi]			; Load 32-bit version
	cmp r10d, r9d			; Compare to first version read
	jne os_apic_timer_set_wait	; If not equal then an update occured, restart

	rdtsc				; Read CPU TSC into EDX:EAX
	shl rdx, 32
	or rax, rdx			; RAX = current 64-bit TSC
	add rax, rbx			; RAX = target TSC deadline

	mov rdx, rax
	shr rdx, 32			; EDX:EAX = target deadline for WRMSR
	mov ecx, MSR_IA32_TSC_DEADLINE
	wrmsr

	pop rdi
	pop r9
	pop r10
	pop rbx
	pop rcx
	pop rdx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_apic_timer_clear -- Clear a pending LAPIC timer interrupt set by os_apic_timer_set
;  IN:	Nothing
; OUT:	All registers preserved
os_apic_timer_clear:
	push rdx
	push rcx
	push rax

	xor eax, eax
	xor edx, edx
	mov ecx, MSR_IA32_TSC_DEADLINE
	wrmsr				; Writing 0 disarms the TSC-deadline timer

	pop rax
	pop rcx
	pop rdx
	ret
; -----------------------------------------------------------------------------


; Register list
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
APIC_TMRDIV	equ 0x3E0		; Divide Configuration Register (for Timer)
; 0x3F0 is Reserved

; LVT Timer mode bits (bits 18:17 of APIC_LVT_TMR)
APIC_LVT_TSCDEADLINE	equ 0x40000	; 10b - TSC-Deadline mode

; MSRs
MSR_IA32_TSC_DEADLINE	equ 0x6E0


; =============================================================================
; EOF
