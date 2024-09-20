SECTIONS
{
    . = 0x80200000;
    .text : {
        *(.text)
		}
    . = ALIGN (CONSTANT (COMMONPAGESIZE));
    .data : {
        *(.data)
		}
}

