#!/bin/sh
set -eu

mkdir -p sys

cd payload
cd BareMetal-Monitor
./setup.sh
./build.sh
mv bin/* ../../sys/
cd ..
cd ..

cd src
cd init
nasm -f elf64 init.asm -o ../../sys/init.o
cd ..
cd BareMetal
nasm kernel.asm -o ../../sys/kernel.sys -l ../../sys/kernel-debug.txt
cd ..
cd ..

cd sys
if [ $# -eq 1 ]; then
	if [ -f $1 ]; then
		echo "Unikernel mode enabled"
		cat kernel.sys monitor.bin $1 > payload.sys
	else
		echo "'$1' does not exist in sys. Skipping unikernel build"
		cat kernel.sys monitor.bin > payload.sys
	fi
else
	cat kernel.sys monitor.bin > payload.sys
fi

objcopy --input-target binary --output-target elf64-x86-64 --binary-architecture i386:x86-64 --rename-section .data=.kernel payload.sys payload_sys.o
ld -m elf_x86_64 -nostdlib -z max-page-size=0x1000 -T ../src/baremetal.ld -o baremetal.elf init.o payload_sys.o
strip --strip-all baremetal.elf # Remove elf debug symbols
cd ..
