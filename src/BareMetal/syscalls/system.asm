; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; System Functions
; =============================================================================


; -----------------------------------------------------------------------------
; b_system - Call system functions
; IN:	RCX = Function
;	RAX = Variable 1
;	RDX = Variable 2
; OUT:	RAX = Result
;	All other registers preserved
b_system:
	cmp rcx, 0x80
	jae b_system_end

; Use CX register as an index to the function table
; To save memory, the functions are placed in 16-bit frames
	push rcx
	lea ecx, [b_system_table+ecx*2]	; extract function from table by index
	mov cx, [ecx]			; limit jump to 16-bit
	call rcx			; call function
	pop rcx

b_system_end:
	ret

; Basic

b_system_timecounter:
	call [sys_timer]
	ret

b_system_free_memory:
	mov eax, [os_MemAmount]
	ret

b_system_wallclock:
	call kvm_get_walltime
	ret

; Ask for RAX more MiB of app RAM (hot-plugged via virtio-mem and appended
; to the app's window). Returns the new total in MiB - the same figure
; b_system_free_memory reports - which is unchanged if nothing could be added.
b_system_grow_memory:
	call virtio_mem_grow
	ret

; CPU
; N/A

b_system_tsc:
	call b_tsc
	ret

; Video
; N/A

; Network

b_system_net_status:
	call b_net_status
	ret

b_system_net_config:
	call b_net_config
	ret

; Bus
; N/A

; Misc

; Ideally sti/cli would be used here - if justs sets/clears IF (bit 9) of RFLAGS.
; However, int_syscall's iretq just restores the previous value of RFLAGS
; More stack shenanigans needed...
;
; [rsp+48] depends on the exact call depth from the trap frame to here:
; int_syscall: push r10 (+8)
; call [r10] into b_system (+8)
; b_system: push rcx (+8)
; call rcx into this routine (+8)
; = 32 bytes
; Plus the CPU's own RIP/CS/RFLAGS/RSP/SS frame, where RFLAGS sits at +16.
; If that call chain changes, this offset must be updated to match.
b_system_irq_enable:
	or qword [rsp+48], 0x200	; Set IF in the trap frame's saved RFLAGS
	ret

b_system_irq_disable:
	and qword [rsp+48], ~0x200	; Clear IF in the trap frame's saved RFLAGS
	ret

b_system_stdout_get:
	mov rax, qword [0x100018]
	ret

b_system_stdout_set:
	mov qword [0x100018], rax
	ret

b_system_callback_timer:
	mov qword [os_TimerCallback], rax
	ret

b_system_callback_network:
	ret

b_system_callback_keyboard:
	ret

b_system_timer_set:
	call os_apic_timer_set
	ret

b_system_debug_dump_mem:
	push rsi
	mov rsi, rax
	mov rcx, rdx
	call os_debug_dump_mem
	pop rsi
	ret

b_system_debug_dump_rax:
	call os_debug_dump_rax
	ret

b_system_delay:
	call [sys_delay]
	ret

b_system_sleep:
	call b_sleep
	ret

b_system_sleep_io:
	call b_sleep_io
	ret

b_system_reboot:
	call reboot

b_system_shutdown:
; 	; Keyboard reset method for Firecracker
	mov al, 0x0FE
	out 0x64, al
	; Execution should never reach the code below
	jmp $
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; b_delay -- Delay by X microseconds
; IN:	RAX = Time microseconds
; OUT:	All registers preserved
; Note:	There are 1,000,000 microseconds in a second
;	There are 1,000 milliseconds in a second
b_delay:
	call timer_delay
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; b_tsc -- Read the Time-Stamp Counter and store in RAX
; IN:	Nothing
; OUT:	RAX = Current Time-Stamp Counter value
;	All other registers preserved
b_tsc:
	push rdx
	rdtsc				; Reads the TSC into EDX:EAX
	shl rdx, 32			; Shift the low 32-bits to the high 32-bits
	or rax, rdx			; Combine RAX and RDX
	pop rdx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; b_sleep -- Sleep for X nanoseconds
; IN:	RAX = Number of nanoseconds
; OUT:	Nothing
;	All registers preserved
; Note:	Tickless - the CPU halts until the deadline (measured with the KVM
;	clock). If no periodic timer is running, a one-shot LAPIC timer is armed
;	for the remaining time so the CPU wakes once, rather than on every tick
;	of a free-running periodic timer.
b_sleep:
	push rax
	push rdx
	xor edx, edx			; Sleep the full duration
	call os_sleep
	pop rdx
	pop rax
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; b_sleep_io -- Sleep for up to X nanoseconds, or until an I/O interrupt
; IN:	RAX = Maximum number of nanoseconds
; OUT:	RAX = 1 if an I/O interrupt (network, keyboard, serial) ended the
;	sleep, 0 if the full duration passed
;	All other registers preserved
; Note:	Lets an app wait for input without polling. The I/O interrupt
;	handlers set os_io_wake, and only this call clears it, so an
;	interrupt that lands after the app last checked for input (but before
;	this call) still ends the next sleep right away - no wakeup is lost.
;	The flip side is the odd spurious early return, which callers must
;	treat as "check again".
b_sleep_io:
	push rdx
	mov edx, 1			; Return early on an I/O interrupt
	call os_sleep
	pop rdx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_sleep -- Shared body of b_sleep and b_sleep_io
; IN:	RAX = Number of nanoseconds
;	RDX = 1 to return early once os_io_wake is set, 0 to ignore it
; OUT:	RAX = 1 if os_io_wake ended the sleep, 0 otherwise
;	All other registers preserved
os_sleep:
	push rbx
	push rcx
	push rdx
	push rsi
	pushfq

	mov rsi, rdx			; RSI = I/O wake mode
	xor ebx, ebx			; RBX = result if we return right away
	test rax, rax
	jz os_sleep_done
	mov rbx, rax
	call [sys_timer]		; RAX = nanoseconds since boot
	add rbx, rax			; RBX = deadline in nanoseconds

os_sleep_snooze:
	cli				; No interrupt may land between arming and HLT
	test rsi, rsi
	jz os_sleep_check_time
	cmp qword [os_io_wake], 0	; Did an I/O interrupt arrive?
	jne os_sleep_io_woke
os_sleep_check_time:
	call [sys_timer]
	cmp rax, rbx			; Reached (or passed) the deadline?
	jae os_sleep_timed_out

	; If an app enabled a periodic timer then its tick will wake us
	cmp qword [os_apic_timer_period], 0
	jne os_sleep_halt

	; Arm a one-shot LAPIC timer for the remaining time
	; APIC ticks = (remaining_ns * ticks_per_ms) / 1,000,000
	mov rcx, rbx
	sub rcx, rax			; RCX = remaining nanoseconds
	mov rax, 1000000000
	cmp rcx, rax			; Cap a single wait at 1 second so the math
	jbe os_sleep_arm		; below can't overflow - we re-arm on wake
	mov rcx, rax
os_sleep_arm:
	mov rax, rcx
	mul qword [os_apic_timer_freq]	; RDX:RAX = remaining_ns * ticks_per_ms
	mov rcx, 1000000
	div rcx				; RAX = remaining LAPIC timer ticks
	test rax, rax
	jnz os_sleep_arm_count
	inc rax				; Always wait at least 1 tick
os_sleep_arm_count:
	push rax
	mov ecx, APIC_LVT_TMR
	mov eax, APIC_LVT_ONESHOT | TIMER_VECTOR
	call os_apic_write
	pop rax
	mov ecx, APIC_TMRINITCNT
	call os_apic_write

os_sleep_halt:
	sti				; STI's interrupt shadow covers the HLT, so a
	hlt				; pending interrupt can't slip in before it
	jmp os_sleep_snooze

os_sleep_io_woke:
	mov qword [os_io_wake], 0	; Consumed - the caller will go look
	mov ebx, 1
	jmp os_sleep_finish

os_sleep_timed_out:
	xor ebx, ebx

os_sleep_finish:
	; Cancel a one-shot that may still be pending (woken by another IRQ)
	cmp qword [os_apic_timer_period], 0
	jne os_sleep_done
	mov ecx, APIC_TMRINITCNT
	xor eax, eax
	call os_apic_write

os_sleep_done:
	mov rax, rbx
	popfq				; Restore the caller's interrupt flag
	pop rsi
	pop rdx
	pop rcx
	pop rbx
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; reboot -- Reboot the computer
reboot:
	mov al, PS2_RESET_CPU
	call ps2_send_cmd
	jmp reboot
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_virt_to_phys -- Function to convert a virtual address to a physical address
; IN:	RAX = Virtual Memory Address
; OUT:	RAX = Physical Memory Address
;	All other registers preserved
; NOTE: BareMetal uses two ranges of memory. One physical 1-to-1 map and one virtual
;	range for free memory
os_virt_to_phys:
	push r15
	push rbx

	mov r15, 0xFFFF800000000000	; Starting address of the higher half
	cmp rax, r15			; Check if RAX is in the upper canonical range
	jb os_virt_to_phys_done		; If not, it is already a physical address - bail out
	mov rbx, rax			; Save RAX
	and rbx, 0x1FFFFF		; Save the low 20 bits
	mov r15, 0x7FFFFFFFFFFF
	and rax, r15
	mov r15, sys_pdh		; Location of virtual memory PDs
	shr rax, 21			; Convert 2MB page to entry
	shl rax, 3
	add r15, rax
	mov rax, [r15]			; Load the entry into RAX
	shr rax, 8			; Clear the low 8 bits
	shl rax, 8
	add rax, rbx

os_virt_to_phys_done:
	pop rbx
	pop r15
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; os_stub -- A function that just returns
b_user:
os_stub:
none:
	ret
; -----------------------------------------------------------------------------


; -----------------------------------------------------------------------------
; System function index table
b_system_table:
; Basic
	dw b_system_timecounter		; 0x00
	dw b_system_free_memory		; 0x01
	dw b_system_wallclock		; 0x02
	dw b_system_grow_memory		; 0x03
	dw none				; 0x04
	dw none				; 0x05
	dw none				; 0x06
	dw none				; 0x07
	dw none				; 0x08
	dw none				; 0x09
	dw none				; 0x0A
	dw none				; 0x0B
	dw none				; 0x0C
	dw none				; 0x0D
	dw none				; 0x0E
	dw none				; 0x0F

; CPU
	dw none				; 0x10
	dw none				; 0x11
	dw none				; 0x12
	dw none				; 0x13
	dw none				; 0x14
	dw none				; 0x15
	dw none				; 0x16
	dw none				; 0x17
	dw none				; 0x18
	dw none				; 0x19
	dw none				; 0x1A
	dw none				; 0x1B
	dw none				; 0x1C
	dw none				; 0x1D
	dw none				; 0x1E
	dw b_system_tsc			; 0x1F

; Video
	dw none				; 0x20
	dw none				; 0x21
	dw none				; 0x22
	dw none				; 0x23
	dw none				; 0x24
	dw none				; 0x25
	dw none				; 0x26
	dw none				; 0x27
	dw none				; 0x28
	dw none				; 0x29
	dw none				; 0x2A
	dw none				; 0x2B
	dw none				; 0x2C
	dw none				; 0x2D
	dw none				; 0x2E
	dw none				; 0x2F

; Network
	dw b_system_net_status		; 0x30
	dw b_system_net_config		; 0x31
	dw none				; 0x32
	dw none				; 0x33
	dw none				; 0x34
	dw none				; 0x35
	dw none				; 0x36
	dw none				; 0x37
	dw none				; 0x38
	dw none				; 0x39
	dw none				; 0x3A
	dw none				; 0x3B
	dw none				; 0x3C
	dw none				; 0x3D
	dw none				; 0x3E
	dw none				; 0x3F

; Storage
	dw none				; 0x40
	dw none				; 0x41
	dw none				; 0x42
	dw none				; 0x43
	dw none				; 0x44
	dw none				; 0x45
	dw none				; 0x46
	dw none				; 0x47
	dw none				; 0x48
	dw none				; 0x49
	dw none				; 0x4A
	dw none				; 0x4B
	dw none				; 0x4C
	dw none				; 0x4D
	dw none				; 0x4E
	dw none				; 0x4F

; Misc
	dw b_system_irq_enable		; 0x50
	dw b_system_irq_disable		; 0x51
	dw b_system_stdout_set		; 0x52
	dw b_system_stdout_get		; 0x53
	dw none				; 0x54
	dw none				; 0x55
	dw none				; 0x56
	dw none				; 0x57
	dw none				; 0x58
	dw none				; 0x59
	dw none				; 0x5A
	dw none				; 0x5B
	dw none				; 0x5C
	dw none				; 0x5D
	dw none				; 0x5E
	dw none				; 0x5F
	dw b_system_callback_timer	; 0x60
	dw b_system_callback_network	; 0x61
	dw b_system_callback_keyboard	; 0x62
	dw none				; 0x63
	dw none				; 0x64
	dw none				; 0x65
	dw none				; 0x66
	dw none				; 0x67
	dw b_system_timer_set		; 0x68
	dw none				; 0x69
	dw none				; 0x6A
	dw none				; 0x6B
	dw none				; 0x6C
	dw none				; 0x6D
	dw none				; 0x6E
	dw none				; 0x6F

; Misc
	dw b_system_debug_dump_mem	; 0x70
	dw b_system_debug_dump_rax	; 0x71
	dw b_system_delay		; 0x72
	dw b_system_sleep		; 0x73
	dw b_system_sleep_io		; 0x74
	dw none				; 0x75
	dw none				; 0x76
	dw none				; 0x77
	dw none				; 0x78
	dw none				; 0x79
	dw none				; 0x7A
	dw none				; 0x7B
	dw none				; 0x7C
	dw none				; 0x7D
	dw b_system_reboot		; 0x7E
	dw b_system_shutdown		; 0x7F
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
