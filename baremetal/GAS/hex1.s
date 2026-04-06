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


# Register use:
# s2: input buffer start (for rewinding)
# s3: input buffer current position
# s4: toggle
# s5: hold
# s6: ip
# s7: tempword
# s8: shiftregister
# s9: input buffer end
# s10: output buffer current position

# Memory layout:
# We start from the code buffer we jumped to in hex0
#                  ----------
#     entry point: 0x80001190
#       stack_top: pc - 4
#    input_buffer: 0x80100000
#           table: input_buffer_end + 4
#   output_buffer: input_buffer_end + 0x400

.equ INPUT_BUFFER_START, 0x80100000
.equ OUTPUT_BUFFER_OFFSET, 0x400

# Phases:
# This program works in multiple phases:
# - Initialize registers
# - Read input
# - First pass: save label definitions
# - Second pass: use label definitions to calculate offsets
# - Clear registers
# - Execute code

.text
.global _start
_start:
    # The previous program, hex0, is effectively dead code
    # Since the stack grows downwards, we can just set it below this code
		auipc t0, 0                  # get the program counter
		addi sp, t0, -4               # set the stack pointer to that program counter
    li s2, INPUT_BUFFER_START    # s2 = input_buffer_start
    mv s3, s2                    # s3 = s2; set the cursor to the start

input_loop:
    call read_uart               # Read a character from UART
    li t0, 4                     # Ctrl-D
    beq a0, t0, input_done       # Done reading input
    sb a0, 0(s3)                 # Store byte in buffer
    addi s3, s3, 1               # Advance buffer pointer
    j input_loop

input_done:
    mv s9, s3                    # Save end of input buffer
    mv s3, s2                    # Reset to start of buffer

    # We have to align the bytes just in case
    addi s9, s9, 3               # Round up
    andi s9, s9, -4              # To the next byte boundary above the end of the input

    # Initialize globals
    li s4, -1                    # Toggle
    li s5, 0                     # Hold
    li s6, 0                     # Instruction Pointer

# First pass loop to determine addresses of labels
First_pass_loop:
    bge s3, s9, First_pass_done  # Check if we've reached end of buffer
    call Read_byte               # Get another byte

    # Check for ':'
    li t1, 0x3a
    bne a0, t1, First_pass_0
    call StoreLabel              # Store this label

First_pass_0:
    # Check for !
    li t1, 0x21
    beq a0, t1, Throwaway_token

    # Check for @
    li t1, 0x40
    beq a0, t1, Throwaway_token

    # Check for $
    li t1, 0x24
    beq a0, t1, Throwaway_token

    # Check for ~
    li t1, 0x7e
    beq a0, t1, Throwaway_token

    li a1, -1                    # write = false
    call DoByte                  # Deal with everything else

    j First_pass_loop            # Keep looping

Throwaway_token:
    # Deal with Pointer to label
    bge s3, s9, First_pass_done  # Check bounds before reading
    call Read_byte               # Drop the char
    j First_pass_loop            # Loop again

First_pass_done:
    # Rewind input buffer
    mv s3, s2                    # Reset to start of buffer

    # Initialize globals
    li s4, -1                    # Toggle
    li s5, 0                     # Hold
    li s6, 0                     # Instruction Pointer
    li s7, 0                     # tempword
    li s8, 0                     # Shift register
    addi s10, s9, OUTPUT_BUFFER_OFFSET # Set output buffer pointer to 1024 bytes after the end of the input buffer

Second_pass_loop:
    bge s3, s9, Second_pass_done # Check if we've reached end of buffer
    call Read_byte               # Read another byte

    # Drop the label
    li t1, 0x3a
    bne a0, t1, Second_pass_0

    bge s3, s9, Second_pass_done # Check bounds before reading
    call Read_byte               # Read the label
    j Second_pass_loop           # Continue looping

Second_pass_0:
    # Check for !
    li t1, 0x21
    beq a0, t1, UpdateShiftRegister

    # Check for @
    li t1, 0x40
    beq a0, t1, UpdateShiftRegister

    # Check for $
    li t1, 0x24
    beq a0, t1, UpdateShiftRegister

    # Check for ~
    li t1, 0x7e
    beq a0, t1, UpdateShiftRegister

    # Deal with everything else
    mv a1, zero                  # write the character to the table
    call DoByte                  # Process our char

    j Second_pass_loop           # continue looping

UpdateShiftRegister:
    mv a1, a0                    # Store label prefix
    call Get_table_target        # Get target
    ld a0, (a0)                  # Dereference pointer
    sub a0, a0, s6               # target - ip

    # Check for !
    li t1, 0x21
    beq a1, t1, UpdateShiftRegister_I

    # Check for @
    li t1, 0x40
    beq a1, t1, UpdateShiftRegister_B

    # Check for $
    li t1, 0x24
    beq a1, t1, UpdateShiftRegister_J

    # Check for ~
    li t1, 0x7e
    beq a1, t1, UpdateShiftRegister_U

    j Second_pass_loop           # Continue looping

UpdateShiftRegister_I:
    # Corresponds to RISC-V I format

    # tempword = ((value & 0xfff) << 20)             ; imm[11:0]

    addi a0, a0, 4               # add 4 due to this being 2nd part of AUIPC combo

    li t1, 0xfff                 # set mask to 0xfff
    and t1, a0, t1               # (value & 0xfff)
    slli s7, t1, 20              # tempword = (value & 0xfff) << 20
    xor s8, s8, s7               # shiftregister = shiftregister ^ tempword

    j Second_pass_loop           # Continue looping

UpdateShiftRegister_B:
    # Corresponds to RISC-V B format

    # tempword = ((value & 0x1e) << 7)            ; imm[4:1]
    #          | ((value & 0x7e0) << (31 - 11))   ; imm[10:5]
    #          | ((value & 0x800) >> 4)           ; imm[11]
    #          | ((value & 0x1000) << (31 - 12))  ; imm[12]

    li t1, 0x1e
    and t1, a0, t1               # value & 0x1e
    slli t0, t1, 7               # tempword = (value & 0x1e) << 7

    li t1, 0x7e0
    and t1, a0, t1               # value & 0x7e0
    slli t1, t1, 20              # (value & 0x7e0) << (31 - 11)
    or t0, t0, t1                # logical or with the previous expression

    li t1, 0x800
    and t1, a0, t1               # value & 0x800
    srli t1, t1, 4               # (value & 0x800) >> 4
    or t0, t0, t1                # logical or with the previous expression

    li t1, 0x1000
    and t1, a0, t1               # value & 0x1000
    slli t1, t1, 19              # (value & 0x1000) << (31 - 12)
    or s7, t0, t1                # tempword

    xor s8, s8, s7               # shiftregister = shiftregister ^ tempword

    j Second_pass_loop           # Continue looping

UpdateShiftRegister_J:
    # Corresponds to RISC-V J format

    # tempword = ((value & 0x7fe) << (30 - 10))    ; imm[10:1]
    #          | ((value & 0x800) << (20 - 11))    ; imm[11]
    #          | ((value & 0xff000))               ; imm[19:12]
    #          | ((value & 0x100000) << (31 - 20)) ; imm[20]

    li t1, 0x7fe
    and t1, a0, t1               # value & 0x7fe
    slli t0, t1, 20              # tempword = (value & 0x7fe) << 20

    li t1, 0x800
    and t1, a0, t1               # value & 0x800
    slli t1, t1, 9               # (value & 0x800) << (20 - 11)
    or t0, t0, t1                # logical or with the previous expression

    li t1, 0xff000
    and t1, a0, t1               # value & 0xff000
    or t0, t0, t1                # logical or with the previous expression

    li t1, 0x100000
    and t1, a0, t1               # value & 0x100000
    slli t1, t1, 11              # (value & 0x100000) << (31 - 20)
    or s7, t0, t1                # tempword

    xor s8, s8, s7               # shiftregister = shiftregister ^ tempword

    j Second_pass_loop           # Continue looping

UpdateShiftRegister_U:
    # Corresponds to RISC-V U format

    # tempword = (value & 0xfffff000)                 ; imm[31:12]
    # if (value & 0xfff) >= 0x800: tempword += 0x1000 ; sign extension compensation

    li t0, 0x800
    li t1, 0xfff
    li t2, 0xfffff000
    and t1, a0, t1               # value & 0xfff
    and s7, a0, t2               # value & 0xfffff000
    blt t1, t0, UpdateShiftRegister_U_small

    # Deal with sign extension: add 0x1000
    li t0, 0x1000
    addw s7, t0, s7              # (value & 0xfffff000) + 0x1000

UpdateShiftRegister_U_small:
    xor s8, s8, s7               # shiftregister = shiftregister ^ tempword

    j Second_pass_loop           # Continue looping

Second_pass_done:
    # Second pass is complete so now we execute the code

Execute_code:
		## The output buffer is at the input_end +
    addi t0, s9, OUTPUT_BUFFER_OFFSET # Set the jump address to start of the output_buffer

    li a0, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 0
    li a6, 0
    li a7, 0
    # Don't zero out t0 as it holds the assembled code
    li t1, 0
    li t2, 0
    li t3, 0
    li t4, 0
    li t5, 0
    li t6, 0
    li s0, 0
    li s1, 0
    li s2, 0
    li s3, 0
    li s4, 0
    li s5, 0
    li s6, 0
    li s7, 0
    li s8, 0
    li s9, 0
    li s10, 0
    li s11, 0
    jr t0

# DoByte function
# Receives:
#   character in a0
#   bool write in a1
# Does not return anything
DoByte:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

    call hex                     # Process hex, store it in a6

    bltz a6, DoByte_Done         # Skip unrecognized characters

    bnez s4, DoByte_NotToggle    # Check if toggle is set

    # toggle = true
    bnez a1, DoByte_1            # check if we have to write

    # write = true
    # We calculate (hold * 16) + hex(c) ^ sr_nextb()
    # First, calculate new shiftregister
    li t0, 0xff
    and t0, s8, t0               # sr_nextb = shiftregister & 0xff
    srli s8, s8, 8               # shiftregister >> 8

    xor t0, t0, a6               # hex(c) ^ sr_nextb
    slli t1, s5, 4               # hold * 16
    add a0, t0, t1               # (hold * 16) + hex(c) ^ sr_nextb()
    call write_byte              # write byte to output

DoByte_1:
    addi s6, s6, 1               # Increment IP
    mv s5, zero                  # hold = 0
    j DoByte_FlipToggle          # return

DoByte_NotToggle:
    mv s5, a6                    # hold = hex(c)

DoByte_FlipToggle:
    not s4, s4                   # Flip the toggle

DoByte_Done:
    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    ret                          # return

# Convert ASCII hex characters into binary representation, e.g. 'a' -> 0xA
# Receives:
#   character in a0
# Returns:
#   a6 with character's hex value.
hex:
    addi sp, sp, -16             # Allocate stack
    sd ra, 0(sp)                 # protect ra
    sd a1, 8(sp)                 # protect a1

    # deal with line comments starting with #
    li t1, 0x23
    beq a0, t1, ascii_comment    # a0 eq to '#'

    # deal with line comments starting with ;
    li t1, 0x3b
    beq a0, t1, ascii_comment    # a0 eq to ';'

    # deal all ascii less than 0
    li t1, 0x30
    blt a0, t1, ascii_other

    # deal with 0-9
    li t1, 0x3a
    blt a0, t1, ascii_num

    # deal with all ascii less than A
    li t1, 0x41
    blt a0, t1, ascii_other

    # deal with A-F
    li t1, 0x47
    blt a0, t1, ascii_high

    # deal with all ascii less than a
    li t1, 0x61
    blt a0, t1, ascii_other

    # deal with a-f
    li t1, 0x67
    blt a0, t1, ascii_low

    # The rest that remains needs to be ignored
    j ascii_other

ascii_num:
    li t1, 0x30                  # '0' -> 0
    sub a6, a0, t1
    j hex_return                 # return
ascii_low:
    li t1, 0x57                  # 'a' -> 0xA
    sub a6, a0, t1
    j hex_return                 # return
ascii_high:
    li t1, 0x37                  # 'A' -> 0xA
    sub a6, a0, t1
    j hex_return                 # return
ascii_other:
    li a6, -1                    # Return -1
    j hex_return                 # return
ascii_comment:                   # Read the comment until newline
    bge s3, s9, ascii_comment_done  # Check bounds
    call Read_byte
    li t1, 0xd                   # CR
    beq a0, t1, ascii_comment_done
    li t1, 0xa                   # LF
    bne a0, t1, ascii_comment    # Keep reading comment
ascii_comment_done:
    li a6, -1                    # Return -1
hex_return:
    ld ra, 0(sp)                 # restore ra
    ld a1, 8(sp)                 # restore a1
    addi sp, sp, 16              # Deallocate stack
    ret                          # return

# Read byte from input buffer into a0
# Caller must check s3 < s9 before calling
Read_byte:
    lb a0, 0(s3)                 # Load byte from buffer
    addi s3, s3, 1               # Advance buffer pointer
    ret                          # return

# Read a character from UART into a0
read_uart:
    li t0, 0x10000005            # UART_LSR
poll_rx:
    lb a0, 0(t0)                 # Read LSR
    andi a0, a0, 1               # Check bit 0 (Data Ready)
    beq a0, zero, poll_rx        # If no data ready, keep polling

    li t0, 0x10000000            # UART_BASE
    lb a0, 0(t0)                 # Read received byte
    ret                          # return

# Reads a byte and calculates table address
# Returns a pointer in a0
Get_table_target:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

    call Read_byte               # Get single char label
    slli a0, a0, 3               # Each label in table takes 8 bytes to store
    addi t0, s9, 4               # Set table to the end of the input buffer + padding
    add a0, a0, t0               # Calculate offset

    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    ret                          # return

StoreLabel:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

    call Get_table_target
    sd s6, (a0)                  # Store ip into table target

    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    ret                          # return

# write_byte function
# Receives CHAR in a0
# Writes to output buffer
write_byte:
    sb a0, 0(s10)                # Write byte to output buffer
    addi s10, s10, 1             # Advance output pointer
    ret                          # return

done:
    # Halt (infinite loop)
    j done
