# BareMetal-Firecracker

This repository contains the source code for BareMetal-Firecracker. This is a custom version of the BareMetal kernel explicitly for execution within a Firecracker microVM. The goal of this project was to achieve a <1ms cold start for the BareMetal kernel and its payload. That goal was achieved.

- [BareMetal](https://github.com/ReturnInfinity/BareMetal), an exokernel written in x86-64 Assembly.
- [Firecracker](https://firecracker-microvm.github.io), a streamlined virtualization environment.

On an AMD Ryzen AI Max+ 395 running Ubuntu Desktop 25.10 execution times are as follows:

- Init: ~100µs from Firecracker handoff to kernel start.
- BareMetal: ~700µs with network and disk enabled. ~500µs with only network enabled.

## Contents

- `src`: Source code for BareMetal init and the BareMetal kernel.
- `payload`: Payload for the kernel - Currently a minimal version of BareMetal Monitor.
- `scripts`: Scripts for creating/removing bridge and tap networks.
- `img`: Screenshot

## Firecracker

### Overview

What is missing from a "standard" VM:

- No BIOS or UEFI
- No PCI/PCIe bus
- No VGA or LFB
- No USB
- Minimal ACPI
- NO HPET

What you get:

- VirtIO devices (block, net, and others) addressable via MMIO
- PS/2 keyboard controller (only used for sending Ctrl-Alt-Del)
- Serial console

Note: It is possible to enable a PCIe bus for Firecracker but it is not a default.

### Memory usage

Firecracker uses the following memory address on startup:

<table border="1" cellpadding="2" cellspacing="0">
<tr><th>Start Address</th><th>Description</th></tr>
<tr><td>0x000500</td><td>GDT</td></tr>
<tr><td>0x000520</td><td>IDT</td></tr>
<tr><td>0x006000</td><td>PVH</td></tr>
<tr><td>0x007000</td><td>boot_params</td></tr>
<tr><td>0x008000</td><td>Stack (starts at 0x8FF0)</td></tr>
<tr><td>0x009000</td><td>PML4 (CR3 points here)</td></tr>
<tr><td>0x00A000</td><td>PDPTE</td></tr>
<tr><td>0x00B000</td><td>PDE</td></tr>
<tr><td>0x020000</td><td>cmd_line</td></tr>
<tr><td>0x0E0000</td><td>RSDP</td></tr>
<tr><td>0x100000</td><td>your software</td></tr>
</table>

`0xC000`-`0xFFFF` should be free

### Startup

Execution starts at `0x100000`. RFLAGS is set to `0x2`, RSP/RBP to `0x8FF0`, and RSI to address of `boot_params`.

## BareMetal Init

Init preps the system for the BareMetal Kernel. It sets the system up in a similar way to [Pure64](https://github.com/ReturnInfinity/Pure64). It is also written in Assembly.

### Memory Map

<table border="1" cellpadding="2" cellspacing="0">
<tr><th>Start Address</th><th>End Address</th><th>Size</th><th>Description</th></tr>
<tr><td>0x0000000000000000</td><td>0x0000000000000FFF</td><td>4 KiB</td><td>IDT - 256 descriptors (each descriptor is 16 bytes)</td></tr>
<tr><td>0x0000000000001000</td><td>0x0000000000001FFF</td><td>4 KiB</td><td>GDT - 256 descriptors (each descriptor is 16 bytes)</td></tr>
<tr><td>0x0000000000002000</td><td>0x0000000000002FFF</td><td>4 KiB</td><td>PML4 - 512 entries, entry 0 points to PDP at 0x3000, entry 256 points to PDP at 0x4000</td></tr>
<tr><td>0x0000000000003000</td><td>0x0000000000003FFF</td><td>4 KiB</td><td>PDP Low - 512 entries</td></tr>
<tr><td>0x0000000000004000</td><td>0x0000000000004FFF</td><td>4 KiB</td><td>PDP High - 512 entries</td></tr>
<tr><td>0x0000000000005000</td><td>0x0000000000005FFF</td><td>4 KiB</td><td>Init data</td></tr>
<tr><td>0x0000000000006000</td><td>0x0000000000006FFF</td><td>4 KiB</td><td>Stack</td></tr>
<tr><td>0x0000000000007000</td><td>0x0000000000007FFF</td><td>4 KiB</td><td>boot_params</td></tr>
<tr><td>0x0000000000008000</td><td>0x000000000000FFFF</td><td>32 KiB</td><td>Stub</td></tr>
<tr><td>0x0000000000010000</td><td>0x000000000001FFFF</td><td>64 KiB</td><td>PD Low - Entries are 8 bytes per 2MiB page</td></tr>
<tr><td>0x0000000000020000</td><td>0x000000000005FFFF</td><td>256 KiB</td><td>PD High - Entries are 8 bytes per 2MiB page</td></tr>
<tr><td>0x0000000000060000</td><td>0x000000000009FFFF</td><td>256 KiB</td><td>Free</td></tr>
<tr><td>0x00000000000A0000</td><td>0x00000000000FFFFF</td><td>384 KiB</td><td>Legacy BIOS ROM Area</td></tr>
<tr><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>VGA RAM at 0xA0000 (128 KiB) Color text starts at 0xB8000</td></tr>
<tr><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>Video BIOS at 0xC0000 (64 KiB)</td></tr>
<tr><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>Motherboard BIOS at F0000 (64 KiB)</td></tr>
<tr><td>0x0000000000100000</td><td>0xFFFFFFFFFFFFFFFF</td><td>1+ MiB</td><td>The software payload is loaded here</td></tr>
</table>

#### Init data

<table border="1" cellpadding="2" cellspacing="0">
<tr><th>Start Address</th><th>End Address</th><th>Size</th><th>Description</th></tr>
<tr><td>0x0000000000005800</td><td>0x00000000000058FF</td><td>256 B</td><td>MMIO devices</td></tr>
<tr><td>0x0000000000005900</td><td>0x00000000000059FF</td><td>256 B</td><td>memmap</td></tr>
<tr><td>0x0000000000005A00</td><td>0x0000000000005AFF</td><td>256 B</td><td>cmdline</td></tr>
</table>

## BareMetal

The BareMetal kernel in this repo has been adapted from the general version. VirtIO drivers have been reworked to use MMIO.

Virtio-Block and Virtio-Net drivers are present. Virtio-Vsock, and other Firecracker-supported devices, is yet to be added.

SMP is not included in this version of BareMetal and will be added at a later date. BareMetal uses 2MiB of memory - A microVM should be provisioned with at least 4MiB of memory so 2MiB can be mapped at `0xFFFF800000000000`. 2MiB is the minimum if the application runs from kernel memory (there is some room).

The kernel binary is currently ~5500 bytes.

## TODO

- proper parsing of the `cmdline` string to gather the base addresses and IRQs of the Virtio MMIO devices
- parse ACPI tables for APIC IDs (SMP removed from this version)
- unikernel mode for diskless systems (embed app into ELF image)

//EOF
