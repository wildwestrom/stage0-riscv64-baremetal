/* Minimal linker script to ensure _start comes first in the binary */
SECTIONS
{
  . = 0x80000000;
  .text : {
    *(.text)          /* _start goes here since we put it in .text */
    *(.text.*)        /* All other text subsections follow */
  }
  .bss : {
    *(.bss)
    *(.bss.*)
  }
}
