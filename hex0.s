# Copyright (C) 2016 Jeremiah Orians
# This file is part of stage0.
#
# stage0 is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# stage0 is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with stage0.  If not, see <http://www.gnu.org/licenses/>.

    .global _start
    .section .text

# UART base address
.equ UART_BASE, 0x10000000
.equ UART_LSR,  0x10000005
.equ CODE_BASE, 0x10000

_start:
    # Set up stack (grow downward from a safe location)
    li sp, 0x80000
    
    # Set up memory pointer for storing hex bytes
    li s2, CODE_BASE  # bp -> s2: pointer to where we store bytes
    
    # Initialize toggle (di -> s1)
    li s1, 1          # toggle: 1 = first nibble, 0 = second nibble
    
    # Initialize holder (si -> s0)
    li s0, 0          # holder for first nibble

loop:
    call read_char
    
    # Check for C-d (Ctrl-D = 4)
    li t0, 4
    beq a0, t0, execute_code_label
    
    # Check for C-l (Ctrl-L = 12)
    li t0, 12
    beq a0, t0, clear_screen_label
    
    # Check for [Enter] (13)
    li t0, 13
    beq a0, t0, display_newline_label
    
    # Otherwise just print the char
    call print_char    # Show the user what they input
    call hex           # Convert to what we want (result in a0)
    
    # Check if it is hex (a0 < 0 means invalid)
    blt a0, zero, loop  # Don't use nonhex chars
    
    # Check if toggled (s1 == 0 means second nibble)
    beq s1, zero, process_second_nibble
    
    # Process first byte of pair
    li t0, 0x0F        # Mask out top
    and s0, a0, t0     # Store first nibble in s0
    li s1, 0           # Flip the toggle
    j loop

process_second_nibble:
    slli s0, s0, 4     # Shift our first nibble left by 4
    li t0, 0x0F        # Mask out top
    and a0, a0, t0     # Mask second nibble
    add a0, s0, a0     # Combine nibbles
    li s1, 1           # Flip the toggle
    
    # Write byte to memory at [s2]
    sb a0, 0(s2)       # Write our byte out
    addi s2, s2, 1     # Increment our pointer by 1
    
    call insert_spacer
    j loop

execute_code_label:
    call execute_code
    j loop

clear_screen_label:
    call clear_screen
    j loop

display_newline_label:
    call display_newline
    j loop

print_char:
    # Routine: output char in a0 to UART
    # Wait for THR to be empty (LSR bit 5 = Transmit Holding Register Empty)
    li t0, UART_LSR
wait_tx:
    lb t1, 0(t0)
    andi t1, t1, 0x20  # Mask bit 5
    beq t1, zero, wait_tx  # If not empty, wait
    
    # Write character to UART
    li t0, UART_BASE
    sb a0, 0(t0)
    ret

read_char:
    # Routine: read a char into a0 from UART
    li t0, UART_LSR
poll_rx:
    # Poll LSR bit 0 (Data Ready)
    lb a0, 0(t0)
    andi a0, a0, 1
    beq a0, zero, poll_rx  # If no data ready, loop back
    
    # Data is ready, read from RBR (offset 0x00, same as base)
    li t0, UART_BASE
    lb a0, 0(t0)
    ret

clear_screen:
    # Routine: clears the display (for serial console, just print newlines)
    li t0, 24          # Number of lines to clear
clear_loop:
    li a0, 10          # Newline character
    call print_char
    addi t0, t0, -1
    bne t0, zero, clear_loop
    ret

display_newline:
    # Routine: print a newline
    li a0, 13          # Carriage return
    call print_char
    li a0, 10          # Line feed
    call print_char
    ret

hex:
    # deal with line comments starting with #
    li t0, 35
    beq a0, t0, ascii_comment
    
    # deal with line comments starting with ;
    li t0, 59
    beq a0, t0, ascii_comment
    
    # deal all ascii less than 0
    li t0, 48
    blt a0, t0, ascii_other
    
    # deal with 0-9
    li t0, 58
    blt a0, t0, ascii_num
    
    # deal with all ascii less than A
    li t0, 65
    blt a0, t0, ascii_other
    
    # deal with A-F
    li t0, 71
    blt a0, t0, ascii_high
    
    # deal with all ascii less than a
    li t0, 97
    blt a0, t0, ascii_other
    
    # deal with a-f
    li t0, 103
    blt a0, t0, ascii_low
    
    # The rest that remains needs to be ignored
    j ascii_other

ascii_num:
    addi a0, a0, -48
    ret

ascii_low:
    addi a0, a0, -87
    ret

ascii_high:
    addi a0, a0, -55
    ret

ascii_other:
    li a0, -1
    ret

ascii_comment:
    call read_char
    call print_char
    li t0, 13
    bne a0, t0, ascii_comment
    call display_newline
    j ascii_other

execute_code:
    # Zero all registers before jump (except sp and code location)
    li a0, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 0
    li a6, 0
    li a7, 0
    li t0, 0
    li t1, 0
    li t2, 0
    li t3, 0
    li t4, 0
    li t5, 0
    li t6, 0
    li s0, 0
    li s1, 0
    # s2 already points to CODE_BASE, keep it
    li s3, 0
    li s4, 0
    li s5, 0
    li s6, 0
    li s7, 0
    li s8, 0
    li s9, 0
    li s10, 0
    li s11, 0
    
    # Jump to the code that we input by hand
    li t0, CODE_BASE
    jr t0

insert_spacer:
    li a0, 32          # Space character
    call print_char
    ret

done:
    # Halt (infinite loop)
    j done

