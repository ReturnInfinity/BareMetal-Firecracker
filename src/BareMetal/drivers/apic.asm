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
	; Switch to x2APIC (MSR-based register access) if the CPU supports it.
	mov eax, 1
	cpuid
	bt ecx, 21			; Check x2APIC support bit
	jnc os_apic_no_x2apic		; Not enabled? Bail out to regular APIC
	mov ecx, IA32_APIC_BASE
	rdmsr
	bts eax, 10			; Set EXTD - switch from xAPIC to x2APIC
	wrmsr
	mov byte [os_apic_x2apic], 1	; Set system flag
os_apic_no_x2apic:

	mov ecx, APIC_VER
	call os_apic_read
	mov [os_apic_ver], eax

	; Software-enable the APIC and configure spurious vector
	mov ecx, APIC_SPURIOUS
	call os_apic_read
	or eax, 0x1FF		; bit 8 = SW enable, bits 7:0 = 0xFF spurious vector
	call os_apic_write

	; Create the IDT entry for the timer interrupt
	mov edi, TIMER_VECTOR
	mov eax, int_apic_timer
	call create_gate

	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_apic_read -- Read from a register in the APIC/x2APIC
;  IN:	ECX = Register to read
; OUT:	RAX = Register value
;	All other registers preserved
os_apic_read:
	cmp byte [os_apic_x2apic], 0
	jne os_apic_read_x2apic
	mov rax, [os_LocalAPICAddress]
	mov eax, [rax + rcx]
	ret

os_apic_read_x2apic:
	push rdx
	push rcx
	shr ecx, 4
	add ecx, 0x800			; x2APIC MSR = 0x800 + (xAPIC register offset >> 4)
	rdmsr
	pop rcx
	pop rdx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_apic_write -- Write to a register in the APIC/x2APIC
;  IN:	ECX = Register to write
;	RAX = Value to write
; OUT:	All registers preserved
os_apic_write:
	cmp byte [os_apic_x2apic], 0
	jne os_apic_write_x2apic
	push rcx
	add rcx, [os_LocalAPICAddress]
	mov [rcx], eax
	pop rcx
	ret

os_apic_write_x2apic:
	push rdx
	push rcx
	shr ecx, 4
	add ecx, 0x800			; x2APIC MSR = 0x800 + (xAPIC register offset >> 4)
	xor edx, edx			; Every register used here is 32-bit - upper half must be 0
	wrmsr
	pop rcx
	pop rdx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_apic_timer_calibrate -- Measure the LAPIC timer frequency against the KVM clock
;  IN:	Nothing
; OUT:	os_apic_timer_freq set to the number of LAPIC timer ticks per millisecond
;	All registers preserved
; Note:	os_clock_init_kvm must have run first so kvm_delay is available.
;	The TIMER_VECTOR IDT gate must already be installed (see os_apic_init).
os_apic_timer_calibrate:
	push rdx
	push rcx
	push rbx
	push rax

	; Run the timer at full speed (divide by 1) for the best resolution
	mov ecx, APIC_TMRDIV
	mov eax, APIC_TMRDIV_1
	call os_apic_write

	; Mask the LVT Timer entry and leave it in one-shot mode while we measure
	mov ecx, APIC_LVT_TMR
	mov eax, APIC_LVT_MASKED | TIMER_VECTOR
	call os_apic_write

	; Start counting down from the maximum value
	mov ecx, APIC_TMRINITCNT
	mov eax, 0xFFFFFFFF
	call os_apic_write

	; Let it run for 1ms, timed via the calibrated KVM/TSC clock
	mov rax, 1000000		; 1,000,000 ns = 1ms
	call kvm_delay

	; See how far the counter dropped in that time
	mov ecx, APIC_TMRCURRCNT
	call os_apic_read
	mov ebx, 0xFFFFFFFF
	sub ebx, eax

	; Stop the timer
	xor eax, eax
	mov ecx, APIC_TMRINITCNT
	call os_apic_write

	mov [os_apic_timer_freq], rbx	; Save resulting value

	pop rax
	pop rbx
	pop rcx
	pop rdx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_apic_timer_set -- Configure the LAPIC timer to fire a periodic interrupt (TIMER_VECTOR)
;  IN:	RAX = Period in nanoseconds between interrupts, 0 to disable
; OUT:	All other registers preserved
; Note:	os_apic_timer_calibrate must have run first to set os_apic_timer_freq
os_apic_timer_set:
	push rdx
	push rcx
	push rbx

	mov [os_apic_timer_period], rax	; Save the period value

	test rax, rax
	jz os_apic_timer_set_clear

	; APIC ticks = (period_ns * ticks_per_ms) / 1,000,000
	mul qword [os_apic_timer_freq]	; RDX:RAX = period_ns * ticks_per_ms
	mov rcx, 1000000
	div rcx				; RAX = period in LAPIC timer ticks
	mov ebx, eax			; RBX = initial count in ticks

	; Set the LVT Timer to periodic mode, unmasked, on the timer vector
	mov ecx, APIC_LVT_TMR
	mov eax, APIC_LVT_PERIODIC | TIMER_VECTOR
	call os_apic_write

	; Arm the counter - hardware reloads and repeats automatically from here
	mov ecx, APIC_TMRINITCNT
	mov eax, ebx
	call os_apic_write

os_apic_timer_set_done:
	pop rbx
	pop rcx
	pop rdx
	ret

os_apic_timer_set_clear:
	mov ecx, APIC_TMRINITCNT
	call os_apic_write		; Writing 0 to the initial count halts the periodic countdown
	jmp os_apic_timer_set_done
; -----------------------------------------------------------------------------


; MSRs
IA32_APIC_BASE	equ 0x01B		; Bit 10 = EXTD (x2APIC), Bit 11 = APIC Global Enable

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
APIC_LVT_ONESHOT	equ 0x00000	; 00b - One-Shot mode
APIC_LVT_PERIODIC	equ 0x20000	; 01b - Periodic mode
APIC_LVT_TSCDEADLINE	equ 0x40000	; 10b - TSC-Deadline mode (newer systems)

; LVT Mask bit (bit 16 of APIC_LVT_TMR and other LVT entries)
APIC_LVT_MASKED		equ 0x10000

; Divide Configuration Register value (APIC_TMRDIV)
APIC_TMRDIV_1		equ 0xB		; Divide by 1 (maximum resolution) - bits [3,1,0]=111, bit 2 reserved as 0


; =============================================================================
; EOF
