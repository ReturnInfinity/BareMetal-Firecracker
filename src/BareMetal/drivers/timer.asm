; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Timer Functions
; =============================================================================


; -----------------------------------------------------------------------------
; os_timer_init -- Initialize timer
os_timer_init:
	; Check for hypervisor presence
;	mov eax, 1
;	cpuid
;	bt ecx, 31			; HV - hypervisor present
;	jnc os_timer_init_error		; If bit is clear then jump to phys init
;
;	; Check for hypervisor type
;	mov eax, 0x40000000
;	cpuid
;	cmp ebx, 0x4B4D564B		; KMVK - KVM
;	jne os_timer_init_error		; KVM detected? Then initialize KVM timer

	; Initialize the KVM timer
	call init_timer_kvm
	mov qword [sys_timer], kvm_ns
	mov qword [sys_delay], kvm_delay
	jmp os_timer_init_done

os_timer_init_error:
	jmp $				; Spin forever as there was no timer source

os_timer_init_done:
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; init_timer_kvm - Initialize the KVM timer
init_timer_kvm:
	; Check hypervisor feature bits
	mov eax, 0x40000001
	cpuid
	bt eax, 3
	jc init_timer_kvm_clocksource2
	bt eax, 0
	jc init_timer_kvm_clocksource
	jmp $

init_timer_kvm_clocksource2:
	mov ecx, MSR_KVM_SYSTEM_TIME_NEW
	jmp init_timer_kvm_configure

init_timer_kvm_clocksource:
	mov ecx, MSR_KVM_SYSTEM_TIME

init_timer_kvm_configure:
	xor edx, edx
	mov eax, kvm_timer		; Memory address for structure
	bts eax, 0			; Enable bit
	wrmsr

	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; kvm_get_usec -- Returns # of microseconds elapsed since guest start
; IN:	Nothing
; OUT:	RAX = microseconds elapsed since start
;	All other registers preserved
kvm_get_usec:
	push r10
	push r9
	push rdi
	push rdx
	push rcx
	push rbx

	mov rdi, kvm_timer
kvm_get_usec_wait:
	mov r10d, [rdi]			; Get 32-bit version
	test r10d, 1			; Check if version is odd (update in progress)
	jnz kvm_get_usec_wait		; If so, retry

	lfence

	rdtsc				; Read CPU TSC into EDX:EAX
	shl rdx, 32
	or rax, rdx			; Combine EDX:EAX into RAX
	mov r9, rax			; Save the 64-bit TSC value

	; Load KVM timer data
	mov rax, [rdi+0x08]		; 64-bit tsc_timestamp
	mov rbx, [rdi+0x10]		; 64-bit system_time
	mov ecx, [rdi+0x18]		; 32-bit tsc_to_system_mul
	push rcx			; Save tsc_to_system_mul to stack
	xor ecx, ecx
	mov cl, [rdi+0x1C]		; 8-bit tsc_shift

	; Calculate timer delta (CPU TSC - tsc_timestamp)
	sub r9, rax
	mov rax, r9

	; Apply tsc_shift
	cmp cl, 0
	jl kvm_get_usec_shift_right	; Signed comparison
	shl rax, cl
	jmp kvm_get_usec_shift_done
kvm_get_usec_shift_right:
	neg cl				; Ex: 0xFF = tsc shift of -1
	shr rax, cl
kvm_get_usec_shift_done:

	pop rcx				; Restore tsc_to_system_mul

	; Calculate nanoseconds as (delta * mul) >> 32
	mul rcx				; RDX:RAX = RAX * RCX
	shl rdx, 32
	shr rax, 32
	or rax, rdx

	; Add system time to nanoseconds
	add rax, rbx

	; Recheck struct version
	lfence
	mov ecx, [rdi]			; Load 32-bit version
	cmp r10d, ecx			; Compare to first version read
	jne kvm_get_usec_wait		; If not equal then an update occured, restart

	; Convert nanoseconds to microseconds
	xor edx, edx
	mov ecx, 1000
	div rcx

	pop rbx
	pop rcx
	pop rdx
	pop rdi
	pop r9
	pop r10
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; kvm_ns -- Returns # of nanoseconds elapsed since guest start
; IN:	Nothing
; OUT:	RAX = nanoseconds elapsed since start
;	All other registers preserved
kvm_ns:
	push r10
	push r9
	push rdi
	push rdx
	push rcx
	push rbx

	mov rdi, kvm_timer
kvm_ns_wait:
	mov r10d, [rdi]			; Get 32-bit version
	test r10d, 1			; Check if version is odd (update in progress)
	jnz kvm_ns_wait			; If so, retry

	lfence

	rdtsc				; Read CPU TSC into EDX:EAX
	shl rdx, 32
	or rax, rdx			; Combine EDX:EAX into RAX
	mov r9, rax			; Save the 64-bit TSC value

	; Load KVM timer data
	mov rax, [rdi+0x08]		; 64-bit tsc_timestamp
	mov rbx, [rdi+0x10]		; 64-bit system_time
	mov ecx, [rdi+0x18]		; 32-bit tsc_to_system_mul
	push rcx			; Save tsc_to_system_mul to stack
	xor ecx, ecx
	mov cl, [rdi+0x1C]		; 8-bit tsc_shift

	; Calculate timer delta (CPU TSC - tsc_timestamp)
	sub r9, rax
	mov rax, r9

	; Apply tsc_shift
	cmp cl, 0
	jl kvm_ns_shift_right	; Signed comparison
	shl rax, cl
	jmp kvm_ns_shift_done
kvm_ns_shift_right:
	neg cl				; Ex: 0xFF = tsc shift of -1
	shr rax, cl
kvm_ns_shift_done:

	pop rcx				; Restore tsc_to_system_mul

	; Calculate nanoseconds as (delta * mul) >> 32
	mul rcx				; RDX:RAX = RAX * RCX
	shl rdx, 32
	shr rax, 32
	or rax, rdx

	; Add system time to nanoseconds
	add rax, rbx

	; Recheck struct version
	lfence
	mov ecx, [rdi]			; Load 32-bit version
	cmp r10d, ecx			; Compare to first version read
	jne kvm_ns_wait			; If not equal then an update occured, restart

	pop rbx
	pop rcx
	pop rdx
	pop rdi
	pop r9
	pop r10
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; kvm_delay -- Delay by X microseconds
; IN:	RAX = Time microseconds
; OUT:	All registers preserved
; Note:	There are 1,000,000 microseconds in a second
;	There are 1,000 milliseconds in a second
kvm_delay:
	push rdx
	push rcx
	push rbx
	push rax

	; Multiply time by 1000 to convert to nanoseconds
	mov ecx, 1000
	mul rcx				; RDX:RAX = RAX * RCX

	mov rbx, rax			; Store delay in RBX
	call kvm_ns
	add rbx, rax			; Add elapsed time
kvm_delay_wait:
	call kvm_ns
	cmp rax, rbx
	jb kvm_delay_wait

	pop rax
	pop rbx
	pop rcx
	pop rdx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; timer_delay -- Delay by X microseconds
; IN:	RAX = Time microseconds
; OUT:	All registers preserved
; Note:	There are 1,000,000 microseconds in a second
;	There are 1,000 milliseconds in a second
timer_delay:
	push rax

	call [sys_delay]

	pop rax
	ret
; -----------------------------------------------------------------------------


; MSRs
MSR_KVM_SYSTEM_TIME_NEW	equ 0x4B564D01
MSR_KVM_SYSTEM_TIME	equ 0x00000012

; KVM pvclock structure
pvclock_version		equ 0x00 ; 32-bit
pvclock_tsc_timestamp	equ 0x08 ; 64-bit
pvclock_system_time	equ 0x10 ; 64-bit
pvclock_tsc_system_mul	equ 0x18 ; 32-bit
pvclock_tsc_shift	equ 0x1C ; 8-bit
pvclock_flags		equ 0x1D ; 8-bit


; =============================================================================
; EOF
