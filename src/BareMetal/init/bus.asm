; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Initialize Bus
; =============================================================================


; Build a table of known devices on the system bus
;
; ┌───────────────────────────────────────────────────────────────────┐
; │                         Bus Table Format                          │
; ├───┬───────────────────────────────┬───────────────┬───────────────┤
; │0x0│     Base Value for bus_*      │   Vendor ID   │   Device ID   │
; ├───┼───────┬───────┬───────────────┴───────────────┴───────────────┤
; │0x8│ Class │ SubCl │                     Flags                     │
; └───┴───────┴───────┴───────────────────────────────────────────────┘
;
; Bytes 0-3	Base value used for os_bus_read/write (SG SG BS DF)
; Bytes 4-5	Vendor ID
; Bytes 6-7	Device ID
; Byte 8	Class code
; Byte 9	Subclass code
; Bytes 10-15	Flags
; Byte 14 is the bus type (1 for PCI, 2 for PCIe)
; Byte 15 will be set to 0x01 later if a driver enabled it


; -----------------------------------------------------------------------------
init_bus:

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_bus
	call os_debug_string
%endif

	; Firecracker - Terminate the bus_table BareMetal uses
	mov edi, bus_table		; Address of Bus Table in memory
	mov eax, 0xFFFFFFFF
	mov ecx, 4
	rep stosd

	call virtio_mmio_init

%ifdef DEBUG
	; Output progress via serial
	mov esi, msg_ok
	call os_debug_string
%endif

	ret
; -----------------------------------------------------------------------------


; =============================================================================
; EOF
