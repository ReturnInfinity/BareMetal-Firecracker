; =============================================================================
; BareMetal -- a 64-bit OS written in Assembly for x86-64 systems
; Copyright (C) 2008-2026 Return Infinity -- see LICENSE.TXT
;
; Driver Includes
; =============================================================================


; Internal
%include "drivers/apic.asm"
%include "drivers/ioapic.asm"
%include "drivers/ps2.asm"
%include "drivers/serial.asm"
%include "drivers/timer.asm"

; Bus
%include "drivers/bus/virtio-mmio.asm"

; Non-volatile Storage
%include "drivers/nvs/virtio-blk-mmio.asm"

; Network
%include "drivers/net/virtio-net-mmio.asm"


; =============================================================================
; EOF
