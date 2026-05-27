; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; System Variables
; =============================================================================


; Strings
newline:		db 13, 10, 0
space:			db ' ', 0
system_status_header:	db 'BareMetal v1.0.0', 0
msg_baremetal:		db 13, 10, '[ BareMetal ]', 0
msg_64:			db 13, 10, '64', 0
msg_bus:		db 13, 10, 'bus', 0
msg_nvs:		db 13, 10, 'nvs', 0
msg_net:		db 13, 10, 'net', 0
msg_ok:			db ' ok', 0
msg_ready:		db 13, 10, 'system ready', 13, 10, 13, 10, 0
msg_banner:		db "============================================================", 13, 10, 0

; Memory addresses

; x86-64 structures
sys_idt:		equ 0x0000000000000000	; 0x000000 -> 0x000FFF	4K Interrupt descriptor table
sys_gdt:		equ 0x0000000000001000	; 0x001000 -> 0x001FFF	4K Global descriptor table
sys_pml4:		equ 0x0000000000002000	; 0x002000 -> 0x002FFF	4K PML4 table
sys_pdpl:		equ 0x0000000000003000	; 0x003000 -> 0x003FFF	4K PDP table low
sys_pdph:		equ 0x0000000000004000	; 0x004000 -> 0x004FFF	4K PDP table high
sys_Pure64:		equ 0x0000000000005000	; 0x005000 -> 0x007FFF	12K Pure64 system data

						; 0x008000 -> 0x00FFFF	32K Free

sys_pdl:		equ 0x0000000000010000	; 0x010000 -> 0x01FFFF	64K Page directory low (Maps up to 16GB of 2MiB pages or 8TB of 1GiB pages)
sys_pdh:		equ 0x0000000000020000	; 0x020000 -> 0x09FFFF	512K Page directory high (Maps up to 128GB)

sys_ROM:		equ 0x00000000000A0000	; 0x0A0000 -> 0x0FFFFF	384K System ROM/Video

; Kernel memory
os_KernelStart:		equ 0x0000000000100000	; 0x100000 -> 0x10FFFF	64K Kernel
os_SystemVariables:	equ 0x0000000000110000	; 0x110000 -> 0x11FFFF	64K System Variables

; System memory

; Non-volatile Storage memory
os_nvs_mem:		equ 0x0000000000120000	; 0x120000 -> 0x12FFFF	64K NVS structures (only uses 12KiB)

; Network memory
os_net_mem:		equ 0x0000000000130000	; 0x130000 -> 0x13FFFF	64K Network descriptors
os_rx_desc:		equ 0x0000000000130000	; 0x130000 -> 0x137FFF	32K Ethernet receive descriptors (only uses 12KiB)
os_tx_desc:		equ 0x0000000000138000	; 0x138000 -> 0x13FFFF	32K Ethernet transmit descriptors (only uses 12KiB)
os_rx_buffer:		equ 0x0000000000140000	; 0x140000 -> 0x1C0000	512K Ethernet receive buffer (256 packets, 2048 bytes each)

						; 0x1C0000 -> 0x1DFFFF	128K Free

						; 0x1E0000 -> 0x1EFFFF	64K Monitor (free if not used)

; App
app_start:		equ 0xFFFF800000000000	; Location of application memory


; System Variables

; DQ - Starting at offset 0, increments by 8
os_LocalAPICAddress:	equ os_SystemVariables + 0x0000
os_IOAPICAddress:	equ os_SystemVariables + 0x0008
os_SysConfEn:		equ os_SystemVariables + 0x0010	; Enabled bits: 0=PS/2 Keyboard, 2=Serial, 4=HPET, 5=xHCI
os_StackBase:		equ os_SystemVariables + 0x0020
os_PacketBase:		equ os_SystemVariables + 0x0028
os_boot_time:		equ os_SystemVariables + 0x0030
sys_timer:		equ os_SystemVariables + 0x0040
sys_delay:		equ os_SystemVariables + 0x0048
os_NetworkCallback:	equ os_SystemVariables + 0x0060
os_KeyboardCallback:	equ os_SystemVariables + 0x0068
os_ClockCallback:	equ os_SystemVariables + 0x0070
os_virtionet_base:	equ os_SystemVariables + 0x00A0
os_virtioblk_base:	equ os_SystemVariables + 0x00A8
os_nvs_io:		equ os_SystemVariables + 0x00B0
os_nvs_id:		equ os_SystemVariables + 0x00B8

; DD - Starting at offset 256, increments by 4
os_MemAmount:		equ os_SystemVariables + 0x0104	; in MiB
virtio_net_irq:		equ os_SystemVariables + 0x0108
os_apic_ver:		equ os_SystemVariables + 0x0110
os_BSP:			equ os_SystemVariables + 0x0118
virtio_net_rxqueuesize:	equ os_SystemVariables + 0x0120
virtio_net_txqueuesize:	equ os_SystemVariables + 0x0124

; DW - Starting at offset 512, increments by 2
os_NumCores:		equ os_SystemVariables + 0x0200
os_CoreSpeed:		equ os_SystemVariables + 0x0202
os_nvsVar:		equ os_SystemVariables + 0x0208	; Bit 0 for NVMe, 1 for AHCI, 2 for Virtio SCSI, 3 for Virtio Block
os_boot_arch:		equ os_SystemVariables + 0x0220 ; Bit 0 set for legacy ports, bit 1 set for 60/64 support

; DB - Starting at offset 768, increments by 1
scancode:		equ os_SystemVariables + 0x0300
key:			equ os_SystemVariables + 0x0301
key_shift:		equ os_SystemVariables + 0x0302
os_BusEnabled:		equ os_SystemVariables + 0x0303	; 1 if PCI is enabled, 2 if PCIe is enabled
os_NetEnabled:		equ os_SystemVariables + 0x0304	; 1 if a supported network card was enabled
os_payload:		equ os_SystemVariables + 0x0305
os_boot_mode:		equ os_SystemVariables + 0x0306
os_ioapic_ver:		equ os_SystemVariables + 0x0316
os_ioapic_mde:		equ os_SystemVariables + 0x0317
key_control:		equ os_SystemVariables + 0x0318
os_net_icount:		equ os_SystemVariables + 0x031B

serial_rb_head:		equ os_SystemVariables + 0x0320	; Serial ring buffer head (read) pointer
serial_rb_tail:		equ os_SystemVariables + 0x0321	; Serial ring buffer tail (write) pointer
serial_rb:		equ os_SystemVariables + 0x0400	; Serial ring buffer (256 bytes)

kvm_timer:		equ os_SystemVariables + 0x1000

; System tables
bus_table:		equ os_SystemVariables + 0x8000
net_table:		equ os_SystemVariables + 0xA000

; Buffers
;os_PacketBuffers:	equ os_SystemVariables + 0xC000	; 16KiB

; net_table values (per device - 128 bytes)
nt_ID:			equ 0x00 ; 16-bit Driver ID
nt_lock:		equ 0x02 ; 16-bit Lock for b_net_tx
nt_interrupt:		equ 0x04 ; 16-bit Interrupts enabled flag
nt_MAC:			equ 0x08 ; 48-bit MAC Address
nt_base:		equ 0x10 ; 64-bit Base MMIO
nt_config:		equ 0x18 ; 64-bit Config function address
nt_transmit:		equ 0x20 ; 64-bit Transmit function address
nt_poll:		equ 0x28 ; 64-bit Poll function address
nt_tx_desc:		equ 0x30 ; 64-bit Address of TX descriptors
nt_rx_desc:		equ 0x38 ; 64-bit Address of RX descriptors
nt_tx_tail:		equ 0x40 ; 32-bit TX Tail
nt_rx_head:		equ 0x44 ; 32-bit RX Head
nt_rx_tail:		equ 0x48 ; 32-bit RX Tail
nt_tx_head:		equ 0x4A ; 32-bit TX Head
nt_tx_packets:		equ 0x50 ; 64-bit Number of packets transmitted
nt_tx_bytes:		equ 0x58 ; 64-bit Number of bytes transmitted
nt_rx_packets:		equ 0x60 ; 64-bit Number of packets received
nt_rx_bytes:		equ 0x68 ; 64-bit Number of bytes received
; bytes 70-7F for future use


; Misc
tchar: db 0, 0


;------------------------------------------------------------------------------

SYS64_CODE_SEL	equ 8		; defined by Pure64

; =============================================================================
; EOF
