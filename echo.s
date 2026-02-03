    .global _start
    .section .text.bios

# Literally all this does is echo characters back through the serial port.

_start:
    # Set up stack (same absolute address as all programs)
    li sp, 0x80002220

    # UART base address
    li a1, 0x10000000
    # LSR offset (Line Status Register at offset 0x05)
    li a2, 0x10000005

echo_loop:
    # Poll LSR bit 0 (Data Ready)
    lb a0, (a2)
    andi a0, a0, 1
    beq a0, x0, echo_loop  # If no data ready, loop back

    # Data is ready, read from RBR (offset 0x00, same as base)
    lb a0, (a1)

    # Wait for THR to be empty (LSR bit 5 = Transmit Holding Register Empty)
wait_tx:
    lb a3, (a2)
    andi a3, a3, 0x20  # Mask bit 5
    beq a3, x0, wait_tx  # If not empty, wait

    # Echo the character back
    sb a0, (a1)

    # Continue loop
    j echo_loop
