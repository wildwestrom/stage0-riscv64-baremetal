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
    .text

.equ UART_BASE, 0x10000000
# Register usage
# a1: UART_BASE
# a2: LSR

_start:
    # Set up stack (same absolute address as all programs)
    li sp, 0x80002220
    # UART base address
    li a1, 0x10000000
    # LSR offset (Line Status Register at offset 0x5)
    addi a2, a1, 0x5

poll_rx:
    # Poll LSR
    lb a0, (a2)
		# Mask bit 0 (data ready)
    andi a0, a0, 0b1
		# If no data ready, loop back
    beq a0, x0, poll_rx
read_data:
    # Data is ready, read from RBR (offset 0x00, same as base)
    lb a0, (a1)

poll_tx:
		# Poll LSR
    lb a3, (a2)
		# Mask bit 5 (TX ready)
    andi a3, a3, 0b100000
		# If TX not ready, wait
    beq a3, x0, poll_tx
echo_char:
    # Echo the character back
    sb a0, (a1)
    # Start read
    j poll_rx
