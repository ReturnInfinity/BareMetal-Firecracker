OUTPUT_FORMAT("elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)
ENTRY(startup_64)

PHDRS
{
	text PT_LOAD FLAGS(5);
	data PT_LOAD FLAGS(6);
	note PT_NOTE FLAGS(4);
}

SECTIONS
{
	. = 0x00100000;

	.text : ALIGN(16)
	{
		*(.text*)
		*(.rodata*)
	} :text

	.note.Xen : ALIGN(4)
	{
		KEEP(*(.note.Xen))
	} :text :note

	.data : ALIGN(16)
	{
		*(.data*)
	} :data

	.bss : ALIGN(16)
	{
		*(.bss*)
		*(COMMON)
	} :data

	ASSERT(. <= 0x00101000, "init overlaps the kernel at 0x101000")
	. = 0x00101000;
	.kernel :
	{
		*(.kernel)
	} :data

	/DISCARD/ :
	{
		*(.debug*)
		*(.comment*)
		*(.note*)
		*(.eh_frame*)
	}
}
