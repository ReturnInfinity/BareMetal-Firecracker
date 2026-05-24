OUTPUT_FORMAT("elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)
ENTRY(startup_64)

PHDRS
{
	text PT_LOAD FLAGS(5);
	data PT_LOAD FLAGS(6);
}

SECTIONS
{
	. = 0x00100000;

	.text : ALIGN(16)
	{
		*(.text*)
		*(.rodata*)
	} :text

	.data : ALIGN(16)
	{
		*(.data*)
	} :data

	.bss : ALIGN(16)
	{
		*(.bss*)
		*(COMMON)
	} :data

	. = 0x00101000;
	.kernel :
	{
		*(.kernel)
	} :data
}
