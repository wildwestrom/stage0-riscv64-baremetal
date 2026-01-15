ENTRY(_start)
SECTIONS
{
    . = 0x80200000;
    .text : {
        KEEP(*(.text.start))
        *(.text .text.*)
    }
    .rodata : {
        *(.rodata .rodata.*)
    }
    .data : {
        *(.data .data.*)
    }
    .bss : {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    }
    . = ALIGN(16);
    _stack_bottom = .;
    . = . + 0x1000;
    _stack_top = .;
}

