## Copyright (C) 2026 Christian Westrom
## This file is part of stage0.
##
## stage0 is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## stage0 is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with stage0.  If not, see <http://www.gnu.org/licenses/>.

# Literally all this does is echo characters over UART.

# This prototype may not match the commented hex

    .global _start
    .section .text.bios

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
    beq a3, x0, wait_tx  # If TX not ready, wait

    # Echo the character back
    sb a0, (a1)

    # Continue loop
    j echo_loop
