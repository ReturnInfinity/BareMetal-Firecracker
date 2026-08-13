; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Version 1.0
; =============================================================================

; Kernel functions
b_input			equ 0x0000000000100010	; Scans keyboard for input. OUT: AL = 0 if no key pressed, otherwise ASCII code
b_output		equ 0x0000000000100018	; Displays a number of characters. IN: RSI = Memory address of message, RCX = number of characters

b_net_tx		equ 0x0000000000100020	; Transmit a packet via a network interface. IN: RSI = Memory address of where packet is stored, RCX = Length of packet, RDX = Device
b_net_rx		equ 0x0000000000100028	; Polls the network interface for received packet. IN: RDX = Device. OUT: RDI = Memory address of where packet was stored, RCX = Length of packet

b_nvs_read		equ 0x0000000000100030	; Read data from a non-volatile storage device. IN: RAX = Starting sector, RCX = Number of sectors to read, RDX = Device, RDI = Memory address to store data
b_nvs_write		equ 0x0000000000100038	; Write data to a non-volatile storage device. IN: RAX = Starting sector, RCX = Number of sectors to write, RDX = Device, RSI = Memory address of data to store

b_system		equ 0x0000000000100040	; Configure system. IN: RCX = Function, RAX = Variable 1, RDX = Variable 2. OUT: RAX = Result


; Index for b_system calls
TIMECOUNTER		equ 0x00	; Return # of nanoseconds elapsed since startup
FREE_MEMORY		equ 0x01
WALLCLOCK		equ 0x02
TSC			equ 0x1F
NET_STATUS		equ 0x30
NET_CONFIG		equ 0x31
BUS_READ		equ 0x50
BUS_WRITE		equ 0x51
STDOUT_SET		equ 0x52
STDOUT_GET		equ 0x53
CALLBACK_TIMER		equ 0x60	; Configure timer interrupt callback
CALLBACK_NETWORK	equ 0x61
CALLBACK_KEYBOARD	equ 0x62
TIMER_SET		equ 0x68	; Configure timer to execute every X nanoseconds
DUMP_MEM		equ 0x70
DUMP_RAX		equ 0x71
DELAY			equ 0x72	; Delay by # microseconds
SLEEP			equ 0x73	; Sleep by # nanoseconds
RESET			equ 0x7D
REBOOT			equ 0x7E
SHUTDOWN		equ 0x7F


; =============================================================================
; EOF
