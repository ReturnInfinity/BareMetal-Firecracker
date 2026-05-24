# BareMetal-Firecracker

This repository contains the source code for BareMetal-Firecracker. This is a custom version of the BareMetal kernel explicitly for execution within Firecracker.

- [BareMetal]() is a exokernel written in x86-64 Assembly.
- [Firecracker]() is a streamlined virtualization environment.

## Firecracker

### Devices

In a nutshell:

- No BIOS or UEFI
- No PCI/PCIe bus
- No VGA or LFB
- No USB
- No ACPI
- NO HPET

What you can get:

- A KVM-based VM
- Serial console
- PS/2 (only used for sending Ctrl-Alt-Del)
- VirtIO devices (block, net, ballon, RNG, and vsock) addressable via MMIO

### Memory usage

Firecracker uses the following memory address on startup:

0x000500 GDT
0x000520 IDT
0x006000 PVH
0x007000 boot_params
0x008000 Stack (starts at 0x8FF0)
0x009000 PML4 (CR3 points here)
0x00A000 PDPTE
0x00B000 PDE
0x020000 cmd_line
0x0E0000 RSDP
0x100000 your kernel

0xC000-0xFFFF should be free

### Startup

Execution starts at 0x100000. RFLAGS is set to 0x2, RSP/RBP to 0x8FF0, and RSI to boot_params.

## BareMetal Init

Init preps the system for the BareMetal Kernel. It sets the system up in a similar way to [Pure64]().

### Memory Map

Start Address		End Address		Size	Description
0x0000000000000000	0x0000000000000FFF	4 KiB	IDT - 256 descriptors (each descriptor is 16 bytes)
0x0000000000001000	0x0000000000001FFF	4 KiB	GDT - 256 descriptors (each descriptor is 16 bytes)
0x0000000000002000	0x0000000000002FFF	4 KiB	PML4 - 512 entries, first entry points to PDP at 0x3000
0x0000000000003000	0x0000000000003FFF	4 KiB	PDP Low - 512 entries
0x0000000000004000	0x0000000000004FFF	4 KiB	PDP High - 512 entries
0x0000000000005000	0x0000000000005FFF	4 KiB	Init data
0x0000000000006000	0x0000000000006FFF	4 KiB	Stack
0x0000000000007000	0x0000000000007FFF	4 KiB	boot_params
0x0000000000008000	0x0000000000008XXX		Stub
0x0000000000010000	0x000000000001FFFF	64 KiB	PD Low - Entries are 8 bytes per 2MiB page - Room to map 16384MiB
0x0000000000020000	0x000000000005FFFF	256 KiB	PD High - Entries are 8 bytes per 2MiB page - Room to map 65536MiB
0x000000000009FC00	0x00000000000FFFFF		Legacy ROM/Video
0x0000000000100000					Kernel payload

## BareMetal

The BareMetal kernel in this repo has been adapted from the general version. VirtIO drivers have been reworked to use MMIO.

//EOF
