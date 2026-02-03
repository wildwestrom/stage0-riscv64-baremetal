ENTRY(_start)
SECTIONS
{
    /* QEMU virt loads the kernel at this address by default. */
    . = 0x80000000;

    /* Pack code + constants + data together to avoid padding between sections. */
    .text : ALIGN(4) {
        KEEP(*(.text.start))
        *(.text .text.*)
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        *(.data .data.*)
        *(.sdata .sdata.*)
    }

    /* Zero-init data. NOLOAD keeps it out of the binary image. */
    .bss (NOLOAD) : ALIGN(8) {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    }

    /* Stack lives above .bss; symbols only so we don't grow the image. */
    . = ALIGN(16);
    _stack_bottom = .;
    _stack_top = _stack_bottom + 0x1000;

    /* Drop metadata/debug sections to keep the image minimal. */
    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}

