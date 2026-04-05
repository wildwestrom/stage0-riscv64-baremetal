# Set architecture for RISC-V bare metal
set architecture riscv:rv64

# Enable automatic disassembly display
set disassemble-next-line on

# Connect to QEMU GDB server
target remote localhost:1234

# Set up layouts
layout asm
layout regs
disas _start
