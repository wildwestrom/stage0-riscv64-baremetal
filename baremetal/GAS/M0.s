## Copyright (C) 2026 Christian Westrom
## Copyright (C) 2017 Jeremiah Orians
## Copyright (C) 2021 Andrius Stikonas
## Copyright (C) 2021 Gabriel Wicki
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

.text
.global _start


# Bare metal M0 stage payload.

# Register use:
# s1: heap pointer
# s2: input cursor
# s3: input end
# s4: struct HEAD
# s5: protected char
# s6: scratch

# Struct format: (size 32)
# NEXT => 0
# TYPE => 8
# TEXT => 16
# EXPRESSION => 24

# Types
# None => 0
# MACRO => 1
# STRING => 2

_start:
    addiw sp, zero, 1029  # Set up stack
    slli sp, sp, 0x15  # Set up stack
    addi s4, zero, 0  # HEAD = NULL
    addiw s1, zero, 1027  # Heap starts here
    slli s1, s1, 0x15  # Heap starts here
    lui s2, 0x1  # Input buffer start
    addiw s2, s2, -2041  # Input buffer start
    slli s2, s2, 0x14  # Input buffer start
    addi t1, s2, 0  # Save start for later

read_input_loop:
    jal ra, read_uart  # Read a character from UART
    addi t0, zero, 4  # Ctrl-D
    beq a0, t0, input_done  # Done reading input
    sb a0, 0(s2)  # Store byte in buffer
    addi s2, s2, 1  # Advance buffer pointer
    jal zero, read_input_loop  # Jump unconditionally to read_input_loop

input_done:
    addi s3, s2, 0  # s3 = end of input buffer
    addi s2, t1, 0  # s2 = start of input buffer
    addi a0, zero, 512  # Allocate scratch
    jal ra, malloc  # Get S pointer
    addi s6, a0, 0  # Save scratch pointer
    jal ra, Tokenize_Line  # Get all lines
    addi a0, s4, 0  # Prepare for Reverse_List
    jal ra, Reverse_List  # Correct order
    addi s4, a0, 0  # Update HEAD
    jal ra, Identify_Macros  # Find the DEFINEs
    jal ra, Line_Macro  # Apply the DEFINEs
    jal ra, Process_String  # Handle strings
    jal ra, Eval_Immediates  # Handle numbers
    jal ra, Preserve_Other  # Collect the remaining
    jal ra, Serialize_Expressions  # Build text stream for backend assembler
    addi a2, s1, 0  # Heap pointer for backend label allocations
    jal ra, M0_backend_assemble_and_exec  # Never returns on success
    jal zero, Fail  # Jump unconditionally to Fail

read_uart:
    lui t0, 0x10000  # UART_LSR
    addiw t0, t0, 5  # UART_LSR

poll_rx:
    lb a0, 0(t0)  # Read LSR
    andi a0, a0, 1  # Check bit 0 (Data Ready)
    beq a0, zero, poll_rx  # If no data ready, keep polling
    lui t0, 0x10000  # UART_BASE
    lb a0, 0(t0)  # Read received byte
    jalr zero, 0(ra)  # return

Tokenize_Line:
    addi sp, sp, -8  # allocate stack
    sd ra, 0(sp)  # protect ra

restart:
    jal ra, fgetc  # Read a char
    addi t0, zero, -4  # EOF
    beq a0, t0, done  # File is collected
    addi a2, a0, 0  # Protect C
    jal ra, IsCommentStarter  # Check for comments
    addi t0, zero, 1  # If comment
    beq a0, t0, Purge_LineComment  # try again
    addi a0, a2, 0  # Put C in place for check
    jal ra, IsTerminator  # Check for terminators
    addi t0, zero, 1  # If terminator
    beq a0, t0, restart  # try again
    addi a0, zero, 32  # malloc struct P
    jal ra, malloc  # Get pointer to P
    addi a3, a0, 0  # Protect P
    sd s4, 0(a3)  # P->NEXT = HEAD
    sd zero, 8(a3)  # P->TYPE = None
    sd zero, 16(a3)  # P->TEXT = NULL
    sd zero, 24(a3)  # P->EXPRESSION = NULL
    addi s4, a3, 0  # HEAD = P
    addi a0, a2, 0  # Put C in place for check
    jal ra, IsStringDelimiter  # Check for string char
    addi t0, zero, 1  # If string char
    beq a0, t0, Store_String  # Get string
    jal ra, Store_Atom  # Get whole token
    jal zero, restart  # Jump unconditionally to restart

done:
    ld ra, 0(sp)  # restore ra
    addi sp, sp, 8  # deallocate stack
    jalr zero, 0(ra)  # return

IsCommentStarter:
    addi t0, zero, 35  # '#'
    beq a0, t0, IsCommentStarter_True  # Branch when condition is satisfied
    addi t0, zero, 59  # ';'
    beq a0, t0, IsCommentStarter_True  # Branch when condition is satisfied
    addi a0, zero, 0  # Load immediate constant
    jalr zero, 0(ra)  # Return to caller

IsCommentStarter_True:
    addi a0, zero, 1  # Load immediate constant
    jalr zero, 0(ra)  # Return to caller

IsTerminator:
    addi t0, zero, 10  # '\n'
    beq a0, t0, IsTerminator_True  # Branch when condition is satisfied
    addi t0, zero, 9  # '\t'
    beq a0, t0, IsTerminator_True  # Branch when condition is satisfied
    addi t0, zero, 32  # ' '
    beq a0, t0, IsTerminator_True  # Branch when condition is satisfied
    addi a0, zero, 0  # Load immediate constant
    jalr zero, 0(ra)  # Return to caller

IsTerminator_True:
    addi a0, zero, 1  # Load immediate constant
    jalr zero, 0(ra)  # Return to caller

IsStringDelimiter:
    addi t0, zero, 34  # '"'
    beq a0, t0, IsStringDelimiter_True  # Branch when condition is satisfied
    addi t0, zero, 39  # '\''
    beq a0, t0, IsStringDelimiter_True  # Branch when condition is satisfied
    addi a0, zero, 0  # Load immediate constant
    jalr zero, 0(ra)  # Return to caller

IsStringDelimiter_True:
    addi a0, zero, 1  # Load immediate constant
    jalr zero, 0(ra)  # Return to caller

Purge_LineComment:
    jal ra, fgetc  # Get a char
    addi t0, zero, 10  # While not LF
    bne a0, t0, Purge_LineComment  # Keep reading
    jal zero, restart  # Jump unconditionally to restart

Store_String:
    addi sp, sp, -24  # allocate stack
    sd a1, 0(sp)  # protect a1
    sd a2, 8(sp)  # protect a2
    sd a3, 16(sp)  # protect a3
    addi a0, zero, 2  # Using TYPE STRING
    sd a0, 8(a3)  # HEAD->TYPE = STRING
    addi a1, a2, 0  # Protect terminator
    addi a3, s6, 0  # Protect string pointer

Store_String_Loop:
    sb a2, 0(a3)  # write byte
    jal ra, fgetc  # read next char
    addi a2, a0, 0  # Update C
    addi a3, a3, 1  # STRING = STRING + 1
    bne a1, a2, Store_String_Loop  # Keep looping unless we hit terminator
    sb zero, 0(a3)  # terminate scratch string
    addi a0, s6, 0  # Prepare the string in scratch
    jal ra, string_length  # Calculate length
    addi a0, a0, 1  # Add 1 for 0 terminator
    jal ra, malloc  # Allocate memory
    ld a3, 16(sp)  # restore a3 (HEAD)
    sd a0, 16(a3)  # HEAD->TEXT = STRING
    jal ra, copy_string  # Copy the string
    ld a1, 0(sp)  # restore a1
    ld a2, 8(sp)  # restore a2
    addi sp, sp, 24  # deallocate stack
    jal zero, restart  # Jump unconditionally to restart

copy_string:
    addi sp, sp, -24  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a1, 8(sp)  # protect a1
    sd a2, 16(sp)  # protect a2
    addi a2, s6, 0  # Get S

copy_string_loop:
    lbu a1, 0(a2)  # S[0]
    beq a1, zero, copy_string_done  # Check if we are done
    sb a1, 0(a0)  # Copy char
    addi a2, a2, 1  # S = S + 1
    addi a0, a0, 1  # T = T + 1
    jal zero, copy_string_loop  # Keep going

copy_string_done:
    sb zero, 0(a0)  # write 0 terminator
    jal ra, ClearScratch  # Clear scratch
    ld ra, 0(sp)  # restore ra
    ld a1, 8(sp)  # restore a1
    ld a2, 16(sp)  # restore a2
    addi sp, sp, 24  # deallocate stack
    jalr zero, 0(ra)  # Return to caller

ClearScratch:
    addi sp, sp, -24  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a0, 8(sp)  # protect a0
    sd a1, 16(sp)  # protect a1
    addi a0, s6, 0  # Prepare scratch
    addi a1, zero, 512  # scratch size in bytes

ClearScratch_loop:
    sb zero, 0(a0)  # Write zero: s[i] = 0
    addi a0, a0, 1  # Increment: i = i + 1
    addi a1, a1, -1  # remaining bytes--
    bne a1, zero, ClearScratch_loop  # Keep looping
    ld ra, 0(sp)  # restore ra
    ld a0, 8(sp)  # restore a0
    ld a1, 16(sp)  # restore a1
    addi sp, sp, 24  # deallocate stack
    jalr zero, 0(ra)  # return

Store_Atom:
    addi sp, sp, -24  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a2, 8(sp)  # protect a2
    sd a3, 16(sp)  # protect a3
    addi a3, s6, 0  # Protect string pointer

Store_Atom_loop:
    sb a2, 0(a3)  # write byte
    jal ra, fgetc  # read next char
    addi a2, a0, 0  # Update C
    addi a3, a3, 1  # STRING = STRING + 1
    jal ra, IsTerminator  # Check for terminators
    beq a0, zero, Store_Atom_loop  # Loop if not "\n\t "
    sb zero, 0(a3)  # terminate scratch string
    addi a0, s6, 0  # Prepare the string in scratch
    jal ra, string_length  # Calculate length
    addi a0, a0, 1  # Add 1 for 0 terminator
    jal ra, malloc  # Allocate memory
    ld a3, 16(sp)  # restore a3 (HEAD)
    sd a0, 16(a3)  # HEAD->TEXT = STRING
    jal ra, copy_string  # Copy the string
    addi a0, a3, 0  # Return HEAD
    ld ra, 0(sp)  # restore ra
    ld a2, 8(sp)  # restore a2
    addi sp, sp, 24  # deallocate stack
    jalr zero, 0(ra)  # return

Reverse_List:
    addi sp, sp, -16  # allocate stack
    sd a1, 0(sp)  # protect a1
    sd a2, 8(sp)  # protect a2
    addi a1, a0, 0  # Set HEAD
    addi a0, zero, 0  # ROOT = NULL

Reverse_List_Loop:
    beq a1, zero, Reverse_List_Done  # Stop if HEAD == NULL
    ld a2, 0(a1)  # NEXT = HEAD->NEXT
    sd a0, 0(a1)  # HEAD->NEXT = ROOT
    addi a0, a1, 0  # ROOT = HEAD
    addi a1, a2, 0  # HEAD = NEXT
    jal zero, Reverse_List_Loop  # Continue looping

Reverse_List_Done:
    ld a1, 0(sp)  # restore a1
    ld a2, 8(sp)  # restore a2
    addi sp, sp, 16  # deallocate stack
    jalr zero, 0(ra)  # return

Identify_Macros:
    addi sp, sp, -24  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a0, 8(sp)  # protect a0
    sd a2, 16(sp)  # protect a2
    addi a2, a0, 0  # I = HEAD

Identify_Macros_Loop:
    ld a0, 16(a2)  # I->TEXT
    jal ra, match_DEFINE  # IF "DEFINE" == I->TEXT
    bne a0, zero, Identify_Macros_Next  # Check if we got macro
    addi a0, zero, 1  # a0 = MACRO
    sd a0, 8(a2)  # I->TYPE = MACRO
    ld a0, 0(a2)  # I->NEXT
    ld a0, 16(a0)  # I->NEXT->TEXT
    sd a0, 16(a2)  # I->TEXT = I->NEXT->TEXT
    ld a0, 0(a2)  # I->NEXT
    ld a0, 0(a0)  # I->NEXT->NEXT
    ld a0, 16(a0)  # I->NEXT->NEXT->TEXT
    sd a0, 24(a2)  # I->EXPRESSION = I->NEXT->NEXT->TEXT
    ld a0, 0(a2)  # I->NEXT
    ld a0, 0(a0)  # I->NEXT->NEXT
    ld a0, 0(a0)  # I->NEXT->NEXT->NEXT
    sd a0, 0(a2)  # I->NEXT = I->NEXT->NEXT->NEXT

Identify_Macros_Next:
    ld a2, 0(a2)  # I = I->NEXT
    bne a2, zero, Identify_Macros_Loop  # Check if we are done
    ld ra, 0(sp)  # restore ra
    ld a0, 8(sp)  # restore a0
    ld a2, 16(sp)  # restore a2
    addi sp, sp, 24  # deallocate stack
    jalr zero, 0(ra)  # return

match_DEFINE:
    lbu t0, 0(a0)  # Load value from memory
    addi t1, zero, 68  # Load immediate constant
    bne t0, t1, match_DEFINE_False  # Branch when condition is satisfied
    lbu t0, 1(a0)  # Load value from memory
    addi t1, zero, 69  # Load immediate constant
    bne t0, t1, match_DEFINE_False  # Branch when condition is satisfied
    lbu t0, 2(a0)  # Load value from memory
    addi t1, zero, 70  # Load immediate constant
    bne t0, t1, match_DEFINE_False  # Branch when condition is satisfied
    lbu t0, 3(a0)  # Load value from memory
    addi t1, zero, 73  # Load immediate constant
    bne t0, t1, match_DEFINE_False  # Branch when condition is satisfied
    lbu t0, 4(a0)  # Load value from memory
    addi t1, zero, 78  # Load immediate constant
    bne t0, t1, match_DEFINE_False  # Branch when condition is satisfied
    lbu t0, 5(a0)  # Load value from memory
    addi t1, zero, 69  # Load immediate constant
    bne t0, t1, match_DEFINE_False  # Branch when condition is satisfied
    lbu t0, 6(a0)  # Load value from memory
    bne t0, zero, match_DEFINE_False  # Branch when condition is satisfied
    addi a0, zero, 0  # Load immediate constant
    jalr zero, 0(ra)  # Return to caller

match_DEFINE_False:
    addi a0, zero, 1  # Load immediate constant
    jalr zero, 0(ra)  # Return to caller

match:
    addi sp, sp, -24  # allocate stack
    sd a1, 0(sp)  # protect a1
    sd a2, 8(sp)  # protect a2
    sd a3, 16(sp)  # protect a3
    addi a2, a0, 0  # S1 in place
    addi a3, a1, 0  # S2 in place

match_Loop:
    lbu a0, 0(a2)  # S1[i]
    lbu a1, 0(a3)  # S2[i]
    bne a0, a1, match_False  # Check if they match
    addi a2, a2, 1  # S1 = S1 + 1
    addi a3, a3, 1  # S2 = S2 + 1
    beq a0, zero, match_Done  # Match if we reached end of string
    jal zero, match_Loop  # Otherwise keep looping

match_False:
    addi a0, zero, 1  # Return false

match_Done:
    ld a1, 0(sp)  # restore a1
    ld a2, 8(sp)  # restore a2
    ld a3, 16(sp)  # restore a3
    addi sp, sp, 24  # deallocate stack
    jalr zero, 0(ra)  # return

Line_Macro:
    addi sp, sp, -32  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a0, 8(sp)  # protect a0
    sd a1, 16(sp)  # protect a1
    sd a2, 24(sp)  # protect a2

Line_Macro_Loop:
    ld a1, 8(a0)  # I->TYPE
    addi t0, zero, 1  # t0 = MACRO
    bne a1, t0, Line_Macro_Next  # Move on unless I->TYPE == MACRO
    ld a1, 16(a0)  # I->TEXT
    ld a2, 24(a0)  # I->EXPRESSION
    ld a0, 0(a0)  # I->NEXT
    jal ra, Set_Expression  # Apply it
    jal zero, Line_Macro_Loop  # Move on to next

Line_Macro_Next:
    ld a0, 0(a0)  # I->NEXT
    bne a0, zero, Line_Macro_Loop  # Check if we are done
    ld ra, 0(sp)  # restore ra
    ld a0, 8(sp)  # restore a0
    ld a1, 16(sp)  # restore a1
    ld a2, 24(sp)  # restore a2
    addi sp, sp, 32  # deallocate stack
    jalr zero, 0(ra)  # return

Set_Expression:
    addi sp, sp, -40  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a0, 8(sp)  # protect a0
    sd a1, 16(sp)  # protect a1
    sd a2, 24(sp)  # protect a2
    sd a3, 32(sp)  # protect a3
    addi a3, a0, 0  # Set I

Set_Expression_Loop:
    ld a0, 8(a3)  # I->TYPE
    addi t0, zero, 1  # t0 = MACRO
    beq a0, t0, Set_Expression_Next  # If MACRO == I->Type then ignore and move on
    ld a0, 16(a3)  # I->TEXT
    jal ra, match  # Check for match
    bne a0, zero, Set_Expression_Next  # Check next if does not match
    sd a2, 24(a3)  # I->EXPRESSION = EXP

Set_Expression_Next:
    ld a3, 0(a3)  # I = I->NEXT
    bne a3, zero, Set_Expression_Loop  # Check if we are done
    ld ra, 0(sp)  # restore ra
    ld a0, 8(sp)  # restore a0
    ld a1, 16(sp)  # restore a1
    ld a2, 24(sp)  # restore a2
    ld a3, 32(sp)  # restore a3
    addi sp, sp, 40  # deallocate stack
    jalr zero, 0(ra)  # return

Process_String:
    addi sp, sp, -40  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a0, 8(sp)  # protect a0
    sd a1, 16(sp)  # protect a1
    sd a2, 24(sp)  # protect a2
    sd a3, 32(sp)  # protect a3
    addi a2, a0, 0  # I = HEAD

Process_String_loop:
    ld a0, 8(a2)  # I->TYPE
    addi t0, zero, 2  # t0 = STRING
    bne a0, t0, Process_String_Next  # Skip to next
    ld a1, 16(a2)  # I->TEXT
    lbu a0, 0(a1)  # I->TEXT[0]
    addi t0, zero, 39  # t0 = \'
    bne a0, t0, Process_String_Raw  # Deal with '"'
    addi a1, a1, 1  # I->TEXT + 1
    sd a1, 24(a2)  # I->EXPRESSION = I->TEXT + 1
    jal zero, Process_String_Next  # Move on to next

Process_String_Raw:
    addi a0, a1, 0  # I->TEXT
    jal ra, string_length  # Get length of I->TEXT
    srli a0, a0, 0x2  # LENGTH = LENGTH >> 2
    addi a0, a0, 1  # LENGTH = LENGTH + 1
    slli a0, a0, 0x3  # LENGTH = LENGTH << 3
    jal ra, malloc  # Get string
    addi a3, a1, 0  # S = I->TEXT
    addi a3, a3, 1  # S = S + 1
    sd a0, 24(a2)  # I->EXPRESSION = hexify
    addi a1, a0, 0  # Put hexify buffer in a1

Process_String_Raw_Loop:
    lbu a0, 0(a3)  # Read 1 character
    addi a3, a3, 1  # S = S + 1
    addi s5, a0, 0  # Protect character
    jal ra, hex8  # write them all
    addi a0, s5, 0  # Restore character
    bne a0, zero, Process_String_Raw_Loop  # Keep looping

Process_String_Next:
    ld a2, 0(a2)  # I = I->NEXT
    bne a2, zero, Process_String_loop  # Check if we are done
    ld ra, 0(sp)  # restore ra
    ld a0, 8(sp)  # restore a0
    ld a1, 16(sp)  # restore a1
    ld a2, 24(sp)  # restore a2
    ld a3, 32(sp)  # restore a3
    addi sp, sp, 40  # deallocate stack
    jalr zero, 0(ra)  # return

string_length:
    addi sp, sp, -16  # allocate stack
    sd a1, 0(sp)  # protect a1
    sd a2, 8(sp)  # protect a2
    addi a1, a0, 0  # Set S
    addi a2, zero, 0  # INDEX = 0

string_length_loop:
    add t0, a1, a2  # S + INDEX
    lbu a0, 0(t0)  # S[INDEX]
    beq a0, zero, string_length_done  # Check if we are done
    addi a2, a2, 1  # INDEX = INDEX + 1
    jal zero, string_length_loop  # Keep going

string_length_done:
    addi a0, a2, 0  # return INDEX
    ld a1, 0(sp)  # restore a1
    ld a2, 8(sp)  # restore a2
    addi sp, sp, 16  # deallocate stack
    jalr zero, 0(ra)  # return

Eval_Immediates:
    addi sp, sp, -40  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a0, 8(sp)  # protect a0
    sd a1, 16(sp)  # protect a1
    sd a2, 24(sp)  # protect a2
    sd a3, 32(sp)  # protect a3
    addi a3, a0, 0  # I = HEAD

Eval_Immediates_Loop:
    ld a0, 8(a3)  # I->TYPE
    addi t0, zero, 1  # t0 = MACRO
    beq a0, t0, Eval_Immediates_Next  # Skip to next if I->TYPE == MACRO
    ld a0, 24(a3)  # I->EXPRESSION
    bne a0, zero, Eval_Immediates_Next  # Skip to next if NULL == I->EXPRESSION
    ld a0, 16(a3)  # I->TEXT
    lbu a1, 0(a0)  # I->TEXT[0]
    addi a0, a0, 1  # I->TEXT + 1
    lbu a2, 0(a0)  # I->TEXT[1]
    jal ra, numerate_string  # Convert string to INT
    bne a0, zero, Eval_Immediates_value  # Has a value IF 0 != numerate_string(I->TEXT + 1)
    addi t0, zero, 48  # If '0' = I->TEXT[1]
    bne a2, t0, Eval_Immediates_Next  # Skip to next

Eval_Immediates_value:
    jal ra, express_number  # Convert value to hex string
    sd a0, 24(a3)  # I->EXPRESSION = express_number(value, I-TEXT[0])

Eval_Immediates_Next:
    ld a3, 0(a3)  # I = I->NEXT
    bne a3, zero, Eval_Immediates_Loop  # Check if we are done
    ld ra, 0(sp)  # restore ra
    ld a0, 8(sp)  # restore a0
    ld a1, 16(sp)  # restore a1
    ld a2, 24(sp)  # restore a2
    ld a3, 32(sp)  # restore a3
    addi sp, sp, 40  # deallocate stack
    jalr zero, 0(ra)  # return

numerate_string:
    addi sp, sp, -24  # allocate stack
    sd a1, 0(sp)  # protect a1
    sd a2, 8(sp)  # protect a2
    sd a3, 16(sp)  # protect a3
    addi a1, a0, 0  # put S in correct place
    addi a0, zero, 0  # Initialize to Zero

numerate_string_loop:
    addi t0, a1, 1  # S + 1
    lbu a2, 0(t0)  # S[1]
    addi t0, zero, 120  # 'x'
    beq a2, t0, numerate_hex  # Deal with hex_input
    addi a3, zero, 0  # Assume no negation
    lbu a2, 0(a1)  # S[0]
    addi t0, zero, 45  # '-'
    bne a2, t0, numerate_decimal  # Skip negation
    addi a3, zero, 1  # Set FLAG
    addi a1, a1, 1  # S = S + 1

numerate_decimal:
    lbu a2, 0(a1)  # S[i]
    beq a2, zero, numerate_decimal_done  # We are done if NULL == S[i]
    slli t0, a0, 0x3  # a0 * 8
    slli t1, a0, 0x1  # a0 * 2
    add a0, t0, t1  # VALUE = VALUE * 10
    addi a2, a2, -48  # CH = CH - '0'
    addi t0, zero, 9  # t0 = 9
    blt t0, a2, numerate_string_fail  # Check for illegal CH > 9
    blt a2, zero, numerate_string_fail  # Check for illegal CH < 0
    add a0, a0, a2  # VALUE = VALUE + CH
    addi a1, a1, 1  # S = S + 1
    jal zero, numerate_decimal  # Jump unconditionally to numerate_decimal

numerate_decimal_done:
    addi t0, zero, 1  # Check for negative FLAG
    bne a3, t0, numerate_string_done  # Nope
    sub a0, zero, a0  # VALUE = -VALUE
    jal zero, numerate_string_done  # Done

numerate_hex:
    addi a1, a1, 2  # S = S + 2

numerate_hex_loop:
    lbu a2, 0(a1)  # S[i]
    beq a2, zero, numerate_string_done  # We are done if NULL == S[i]
    slli a0, a0, 0x4  # VALUE = VALUE << 4
    addi a2, a2, -48  # CH = CH - '0'
    addi t0, zero, 10  # t0 = 10
    blt a2, t0, numerate_hex_digit  # Check if we are dealing with number or letter
    addi a2, a2, -7  # Push A-F into range

numerate_hex_digit:
    addi t0, zero, 15  # t0 = 15
    blt t0, a2, numerate_string_fail  # Check for CH > 'F'
    blt a2, zero, numerate_string_fail  # Check for CH < 0
    add a0, a0, a2  # VALUE = VALUE + CH
    addi a1, a1, 1  # S = S + 1
    jal zero, numerate_hex_loop  # Keep looping

numerate_string_fail:
    addi a0, zero, 0  # return ZERO

numerate_string_done:
    ld a1, 0(sp)  # restore a1
    ld a2, 8(sp)  # restore a2
    ld a3, 16(sp)  # restore a3
    addi sp, sp, 24  # deallocate stack
    jalr zero, 0(ra)  # return

express_number:
    addi sp, sp, -32  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a1, 8(sp)  # protect a1
    sd a2, 16(sp)  # protect a2
    sd a3, 24(sp)  # protect a3
    addi a2, a1, 0  # Put CH in right place
    addi s5, a0, 0  # Protect VALUE
    addi a0, zero, 10  # We need 10 bytes
    jal ra, malloc  # Get S pointer
    addi a1, a0, 0  # Put S in place
    addi a0, s5, 0  # Restore VALUE
    addi t0, zero, 37  # Check for %
    beq a2, t0, express_number_const  # Branch when condition is satisfied
    addi s5, a1, 0  # Protect S
    addi t0, zero, 46  # t0 = '.'
    sd t0, 0(a1)  # S[0] = '.'
    addi a1, a1, 1  # Next byte
    addi t0, zero, 33  # Check for !
    beq a2, t0, express_number_I  # Branch when condition is satisfied
    addi t0, zero, 64  # Check for @
    beq a2, t0, express_number_S  # Branch when condition is satisfied
    addi t0, zero, 126  # Check for ~
    beq a2, t0, express_number_U  # Branch when condition is satisfied
    jal zero, Fail  # Error

express_number_const:
    addiw t0, zero, 1  # provides an option for 32-bit immediate constants
    slli t0, t0, 0x20  # provides an option for 32-bit immediate constants
    addi t0, t0, -1  # provides an option for 32-bit immediate constants
    and a0, a0, t0  # immediate = value & 0xffffffff
    addi s5, a1, 0  # Protect S
    jal ra, hex32l  # Store 32-bits
    jal zero, express_number_done  # done

express_number_I:
    lui t0, 0x1  # (value & 0xfff) << 20
    addiw t0, t0, -1  # (value & 0xfff) << 20
    and a0, a0, t0  # value & 0xfff
    slli a0, a0, 0x14  # (value & 0xfff) << 20
    jal ra, hex32l  # Store 32-bits
    jal zero, express_number_done  # done

express_number_S:
    addi t0, zero, 31  # ((value & 0x1f) << 7) | ((value & 0xfe0) << (31 - 11))
    and t1, a0, t0  # value & 0x1f
    slli t1, t1, 0x7  # (value & 0x1f) << 7
    lui t0, 0x1  # Prepare upper immediate bits
    addiw t0, t0, -32  # Advance algorithm state
    and t0, a0, t0  # value & 0xfe0
    slli t0, t0, 0x14  # (value & 0xfe0) << (31 - 11)
    or a0, t0, t1  # Combine two parts
    jal ra, hex32l  # Store 32-bits
    jal zero, express_number_done  # done

express_number_U:
    lui t0, 0x1  # if value is 0x800 or more we have to add 11-th bit (0x1000) to compensate for signed extension
    addiw t0, t0, -2048  # if value is 0x800 or more we have to add 11-th bit (0x1000) to compensate for signed extension
    lui t1, 0x1  # Prepare upper immediate bits
    addiw t1, t1, -1  # Advance algorithm state
    lui t2, 0x100  # Prepare upper immediate bits
    addiw t2, t2, -1  # Advance algorithm state
    slli t2, t2, 0xC  # Shift bits to align field values
    and t1, a0, t1  # value & 0xfff
    and a0, a0, t2  # value & 0xfffff000
    blt t1, t0, express_number_U_small  # Branch when condition is satisfied
    lui t0, 0x1  # Deal with sign extension: add 0x1000
    addw a0, t0, a0  # (value & 0xfffff000) + 0x1000

express_number_U_small:
    jal ra, hex32l  # Store 32-bits
    jal zero, express_number_done  # done

express_number_done:
    addi a0, s5, 0  # Restore S
    ld ra, 0(sp)  # restore ra
    ld a1, 8(sp)  # restore a1
    ld a2, 16(sp)  # restore a2
    ld a3, 24(sp)  # restore a3
    addi sp, sp, 32  # deallocate stack
    jalr zero, 0(ra)  # return

hex32l:
    addi sp, sp, -16  # allocate stack
    sd ra, 0(sp)  # Protect ra
    sd a0, 8(sp)  # Protect top 16 bits
    jal ra, hex16l  # Store it
    ld a0, 8(sp)  # do high 16 bits
    srli a0, a0, 0x10  # do bottom 16 bits
    jal ra, hex16l  # Store it
    ld ra, 0(sp)  # restore ra
    addi sp, sp, 16  # deallocate stack
    jalr zero, 0(ra)  # return

hex16l:
    addi sp, sp, -16  # allocate stack
    sd ra, 0(sp)  # Protect ra
    sd a0, 8(sp)  # Protect top byte
    jal ra, hex8  # Store it
    ld a0, 8(sp)  # do high byte
    srli a0, a0, 0x8  # do bottom byte
    jal ra, hex8  # Store it
    ld ra, 0(sp)  # restore ra
    addi sp, sp, 16  # deallocate stack
    jalr zero, 0(ra)  # return

hex8:
    addi sp, sp, -16  # allocate stack
    sd ra, 0(sp)  # Protect ra
    sd a0, 8(sp)  # Protect bottom nibble
    srli a0, a0, 0x4  # do high nibble first
    jal ra, hex4  # Store it
    ld a0, 8(sp)  # do low nibble
    jal ra, hex4  # Store it
    ld ra, 0(sp)  # restore ra
    addi sp, sp, 16  # deallocate stack
    jalr zero, 0(ra)  # return

hex4:
    addi t0, zero, 15  # Load immediate constant
    and a0, a0, t0  # isolate nibble
    addi a0, a0, 48  # convert to ascii
    addi t0, zero, 57  # t0 = '9'
    bge t0, a0, hex1  # check if valid digit
    addi a0, a0, 7  # use alpha range

hex1:
    sb a0, 0(a1)  # store result
    addi a1, a1, 1  # next position
    jalr zero, 0(ra)  # return

Preserve_Other:
    addi sp, sp, -32  # allocate stack
    sd a1, 0(sp)  # protect a1
    sd a2, 8(sp)  # protect a2
    sd a3, 16(sp)  # protect a3
    sd a4, 24(sp)  # protect a4

Preserve_Other_Loop:
    ld a1, 24(a0)  # I->EXPRESSION
    bne a1, zero, Preserve_Other_Next  # IF NULL == I->EXPRESSION then preserve
    ld a1, 16(a0)  # I->TEXT
    sd a1, 24(a0)  # I->EXPRESSION = I->TEXT

Preserve_Other_Next:
    ld a0, 0(a0)  # I = I->NEXT
    bne a0, zero, Preserve_Other_Loop  # Keep looping until I == NULL
    ld a1, 0(sp)  # restore a1
    ld a2, 8(sp)  # restore a2
    ld a3, 16(sp)  # restore a3
    ld a4, 24(sp)  # restore a4
    addi sp, sp, 32  # deallocate stack
    jalr zero, 0(ra)  # return

Serialize_Expressions:
    addi sp, sp, -32  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a2, 8(sp)  # protect a2
    sd a3, 16(sp)  # protect a3
    sd a4, 24(sp)  # protect a4
    lui a2, 0x1  # output text buffer start
    addiw a2, a2, -2041  # output text buffer start
    slli a2, a2, 0x14  # output text buffer start
    addi a3, a2, 0  # running write pointer
    addi a4, s4, 0  # I = HEAD

Serialize_Expressions_Loop:
    beq a4, zero, Serialize_Expressions_Done  # Branch when condition is satisfied
    ld t0, 8(a4)  # I->TYPE
    addi t1, zero, 1  # MACRO
    beq t0, t1, Serialize_Expressions_Next  # Branch when condition is satisfied
    ld t0, 24(a4)  # I->EXPRESSION
    beq t0, zero, Serialize_Expressions_Next  # Branch when condition is satisfied

Serialize_Expressions_Copy:
    lbu t1, 0(t0)  # c = expression[i]
    beq t1, zero, Serialize_Expressions_Term  # Branch when condition is satisfied
    sb t1, 0(a3)  # write c
    addi a3, a3, 1  # Advance algorithm state
    addi t0, t0, 1  # Advance algorithm state
    jal zero, Serialize_Expressions_Copy  # Jump unconditionally to Serialize_Expressions_Copy

Serialize_Expressions_Term:
    addi t1, zero, 10  # '\n'
    sb t1, 0(a3)  # Store value to memory
    addi a3, a3, 1  # Advance algorithm state

Serialize_Expressions_Next:
    ld a4, 0(a4)  # I = I->NEXT
    jal zero, Serialize_Expressions_Loop  # Jump unconditionally to Serialize_Expressions_Loop

Serialize_Expressions_Done:
    addi a0, a2, 0  # start pointer
    addi a1, a3, 0  # end pointer
    ld ra, 0(sp)  # restore ra
    ld a2, 8(sp)  # restore a2
    ld a3, 16(sp)  # restore a3
    ld a4, 24(sp)  # restore a4
    addi sp, sp, 32  # deallocate stack
    jalr zero, 0(ra)  # return

Print_Hex:
    addi sp, sp, -24  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a1, 8(sp)  # protect a1
    sd a2, 16(sp)  # protect a2
    addi a1, s4, 0  # I = HEAD

Print_Hex_Loop:
    ld a0, 8(a1)  # I->TYPE
    addi t0, zero, 1  # t0 = MACRO
    beq a0, t0, Print_Hex_Next  # Skip if MACRO = I->TYPE
    ld a0, 24(a1)  # Using EXPRESSION
    jal ra, File_Print  # Print it
    addi a0, zero, 10  # \n
    jal ra, fputc  # Print newline

Print_Hex_Next:
    ld a1, 0(a1)  # Iterate to next Token
    bne a1, zero, Print_Hex_Loop  # Stop if NULL, otherwise keep looping
    ld ra, 0(sp)  # restore ra
    ld a1, 8(sp)  # restore a1
    ld a2, 16(sp)  # restore a2
    addi sp, sp, 24  # deallocate stack
    jalr zero, 0(ra)  # return

File_Print:
    addi sp, sp, -24  # allocate stack
    sd ra, 0(sp)  # protect ra
    sd a1, 8(sp)  # protect a1
    sd a2, 16(sp)  # protect a2
    addi a1, a0, 0  # protect a0
    beq a0, zero, File_Print_Done  # Protect against nulls

File_Print_Loop:
    lbu a0, 0(a1)  # Read byte
    beq a0, zero, File_Print_Done  # Stop at NULL
    jal ra, fputc  # print it
    addi a1, a1, 1  # S = S + 1
    jal zero, File_Print_Loop  # Keep printing

File_Print_Done:
    ld ra, 0(sp)  # restore ra
    ld a1, 8(sp)  # restore a1
    ld a2, 16(sp)  # restore a2
    addi sp, sp, 24  # deallocate stack
    jalr zero, 0(ra)  # return

fgetc:
    bge s2, s3, fgetc_eof  # Check if we've reached end of buffer
    lb a0, 0(s2)  # Load byte from buffer
    addi s2, s2, 1  # Advance buffer pointer
    jalr zero, 0(ra)  # return

fgetc_eof:
    addi a0, zero, -4  # Return EOF
    jalr zero, 0(ra)  # return

malloc:
    addi t0, s1, 0  # Store the current pointer
    add s1, s1, a0  # Bump the pointer by requested bytes
    addi a0, t0, 0  # Return the old pointer
    jalr zero, 0(ra)  # return

fputc:
    addi sp, sp, -8  # allocate stack
    sd a1, 0(sp)  # protect a1
    lui a1, 0x10000  # UART_LSR
    addiw a1, a1, 5  # UART_LSR

fputc_wait:
    lb t0, 0(a1)  # Read LSR
    andi t0, t0, 32  # Check bit 5 (THR Empty)
    beq t0, zero, fputc_wait  # If TX not ready, wait
    lui a1, 0x10000  # UART_BASE
    sb a0, 0(a1)  # Write character
    ld a1, 0(sp)  # restore a1
    addi sp, sp, 8  # deallocate stack
    jalr zero, 0(ra)  # return

Fail:
    jal zero, Fail  # Halt (infinite loop)

M0_backend_assemble_and_exec:
    addi s2, a0, 0  # a0 = input_buffer start, a1 = input_buffer end, a2 = heap pointer
    addi s3, a0, 0  # Copy register value
    addi s11, a1, 0  # Copy register value
    addi s9, a2, 0  # Copy register value
    addi s1, zero, 0  # jump table head = NULL
    addi s4, zero, -1  # Toggle
    addi s5, zero, 0  # Hold
    lui s6, 0x1  # Instruction Pointer / output buffer base
    addiw s6, s6, -2045  # Instruction Pointer / output buffer base
    slli s6, s6, 0x14  # Instruction Pointer / output buffer base
    jal ra, backend_ClearScratch  # Zero scratch
    jal ra, backend_First_pass  # First pass
    addi s2, s3, 0  # Reset to start of buffer
    addi s4, zero, -1  # Toggle
    addi s5, zero, 0  # Hold
    lui s6, 0x1  # Instruction Pointer / output buffer base
    addiw s6, s6, -2045  # Instruction Pointer / output buffer base
    slli s6, s6, 0x14  # Instruction Pointer / output buffer base
    addi s7, zero, 0  # tempword
    addi s8, zero, 0  # Shift register
    jal ra, backend_Second_pass  # Now do the second pass
    lui t0, 0x1  # output_buffer
    addiw t0, t0, -2045  # output_buffer
    slli t0, t0, 0x14  # output_buffer
    jalr zero, 0(t0)  # Jump to address held in register

backend_First_pass:
    addi sp, sp, -8  # Allocate stack
    sd ra, 0(sp)  # protect ra

backend_First_pass_loop:
    bge s2, s11, backend_First_pass_done  # Check if we've reached end of buffer
    jal ra, backend_Read_byte  # Get another byte
    addi t1, zero, 58  # Check for :
    beq a0, t1, backend_StoreLabel  # Store this label
    addi t1, zero, 46  # Check for '.'
    beq a0, t1, backend_First_pass_UpdateWord  # Branch when condition is satisfied
    addi t1, zero, 37  # Check for %
    beq a0, t1, backend_First_pass_pointer  # Branch when condition is satisfied
    addi t1, zero, 38  # Check for &
    beq a0, t1, backend_First_pass_pointer  # Branch when condition is satisfied
    addi t1, zero, 33  # Check for !
    beq a0, t1, backend_Throwaway_token  # Branch when condition is satisfied
    addi t1, zero, 64  # Check for @
    beq a0, t1, backend_Throwaway_token  # Branch when condition is satisfied
    addi t1, zero, 36  # Check for $
    beq a0, t1, backend_Throwaway_token  # Branch when condition is satisfied
    addi t1, zero, 126  # Check for ~
    beq a0, t1, backend_Throwaway_token  # Branch when condition is satisfied
    addi t1, zero, 60  # Check for <
    addi a1, zero, -1  # write = false
    beq a0, t1, backend_PadToAlign  # Branch when condition is satisfied
    addi a1, zero, -1  # write = false
    addi a2, zero, -1  # update = false
    jal ra, backend_DoByte  # Deal with everything else
    jal zero, backend_First_pass_loop  # Keep looping

backend_Throwaway_token:
    addiw a1, zero, 513  # scratch address
    slli a1, a1, 0x16  # scratch address
    jal ra, backend_consume_token  # Read token
    jal ra, backend_ClearScratch  # Throw away token
    jal zero, backend_First_pass_loop  # Loop again

backend_First_pass_pointer:
    addi s6, s6, 4  # Update ip
    addiw a1, zero, 513  # scratch address
    slli a1, a1, 0x16  # scratch address
    jal ra, backend_consume_token  # Read token
    jal ra, backend_ClearScratch  # Throw away token
    addi t1, zero, 62  # Check for '>'
    bne a0, t1, backend_First_pass_loop  # Loop again
    addiw a1, zero, 513  # scratch address
    slli a1, a1, 0x16  # scratch address
    jal ra, backend_consume_token  # Read token
    jal ra, backend_ClearScratch  # Throw away token
    jal zero, backend_First_pass_loop  # Loop again

backend_First_pass_UpdateWord:
    addi s10, zero, 0  # updates = 0
    addi s7, zero, 0  # tempword = 0
    addi a5, zero, 4  # a5 = 4

backend_First_pass_UpdateWord_loop:
    jal ra, backend_Read_byte  # Read another byte into a0
    addi a1, zero, -1  # write = false
    addi a2, zero, 0  # update = true
    jal ra, backend_DoByte  # Process byte
    blt s10, a5, backend_First_pass_UpdateWord_loop  # loop 4 times
    addi s6, s6, -4  # ip = ip - 4
    jal zero, backend_First_pass_loop  # Loop again

backend_First_pass_done:
    ld ra, 0(sp)  # restore ra
    addi sp, sp, 8  # deallocate stack
    jalr zero, 0(ra)  # return

backend_Second_pass:
    addi sp, sp, -8  # Allocate stack
    sd ra, 0(sp)  # protect ra
    lui a7, 0x1  # output_buffer - use a7 as output pointer
    addiw a7, a7, -2045  # output_buffer - use a7 as output pointer
    slli a7, a7, 0x14  # output_buffer - use a7 as output pointer

backend_Second_pass_loop:
    bge s2, s11, backend_Second_pass_done  # Check if we've reached end of buffer
    jal ra, backend_Read_byte  # Read another byte
    addi t1, zero, 58  # Drop the label
    bne a0, t1, backend_Second_pass_0  # Branch when condition is satisfied
    addiw a1, zero, 513  # scratch address
    slli a1, a1, 0x16  # scratch address
    jal ra, backend_consume_token  # Read the label
    jal ra, backend_ClearScratch  # Throw away token
    jal zero, backend_Second_pass_loop  # Continue looping

backend_Second_pass_0:
    addi t1, zero, 46  # Check for '.'
    beq a0, t1, backend_Second_pass_UpdateWord  # Branch when condition is satisfied
    addi t1, zero, 37  # Check for %
    beq a0, t1, backend_StorePointer  # Branch when condition is satisfied
    addi t1, zero, 38  # Check for &
    beq a0, t1, backend_StorePointer  # Branch when condition is satisfied
    addi t1, zero, 33  # Check for !
    beq a0, t1, backend_UpdateShiftRegister  # Branch when condition is satisfied
    addi t1, zero, 64  # Check for @
    beq a0, t1, backend_UpdateShiftRegister  # Branch when condition is satisfied
    addi t1, zero, 36  # Check for $
    beq a0, t1, backend_UpdateShiftRegister  # Branch when condition is satisfied
    addi t1, zero, 126  # Check for ~
    beq a0, t1, backend_UpdateShiftRegister  # Branch when condition is satisfied
    addi t1, zero, 60  # Check for <
    addi a1, zero, 0  # write = true
    beq a0, t1, backend_PadToAlign  # Branch when condition is satisfied
    addi a1, zero, 0  # write = true
    addi a2, zero, -1  # update = false
    jal ra, backend_DoByte  # Process our char
    jal zero, backend_Second_pass_loop  # continue looping

backend_Second_pass_UpdateWord:
    addi s10, zero, 0  # updates = 0
    addi s7, zero, 0  # tempword = 0
    addi a5, zero, 4  # a5 = 4

backend_Second_pass_UpdateWord_loop:
    jal ra, backend_Read_byte  # Read another byte into a0
    addi a1, zero, -1  # write = false
    addi a2, zero, 0  # update = true
    jal ra, backend_DoByte  # Process byte
    blt s10, a5, backend_Second_pass_UpdateWord_loop  # loop 4 times
    addi a0, s7, 0  # tempword
    jal zero, backend_UpdateShiftRegister_DOT  # UpdateShiftRegister('.', tempword)

backend_UpdateShiftRegister:
    addi a2, a0, 0  # Store label prefix
    addiw a1, zero, 513  # Get scratch
    slli a1, a1, 0x16  # Get scratch
    jal ra, backend_ClearScratch  # Clear scratch
    jal ra, backend_consume_token  # Read token
    jal ra, backend_GetTarget  # Get target
    ld a0, 0(a0)  # Dereference pointer
    sub a0, a0, s6  # target - ip
    addi t1, zero, 33  # Check for !
    beq a2, t1, backend_UpdateShiftRegister_I  # Branch when condition is satisfied
    addi t1, zero, 64  # Check for @
    beq a2, t1, backend_UpdateShiftRegister_B  # Branch when condition is satisfied
    addi t1, zero, 36  # Check for $
    beq a2, t1, backend_UpdateShiftRegister_J  # Branch when condition is satisfied
    addi t1, zero, 126  # Check for ~
    beq a2, t1, backend_UpdateShiftRegister_U  # Branch when condition is satisfied
    jal zero, backend_Second_pass_loop  # Continue looping

backend_UpdateShiftRegister_DOT:
    srliw t2, a0, 0x18  # value >> 24
    addi t1, zero, 255  # t1 = 0xff
    and t0, t1, t2  # (value >> 24) & 0xff
    slliw t2, a0, 0x8  # value << 8
    lui t1, 0xFF0  # t1 = 0xff0000
    and t2, t1, t2  # (value << 8) & 0xff0000
    or t0, t0, t2  # logical or with the previous expression
    srliw t2, a0, 0x8  # value >> 8
    lui t1, 0x10  # t1 = 0xff00
    addiw t1, t1, -256  # t1 = 0xff00
    and t2, t1, t2  # (value >> 8) & 0xff00
    or t0, t0, t2  # logical or with the previous expression
    slliw t2, a0, 0x18  # value << 24
    addiw t1, zero, 255  # t1 = 0xff000000
    slli t1, t1, 0x18  # t1 = 0xff000000
    and t2, t1, t2  # (value << 24) & 0xff000000
    or t0, t0, t2  # swap
    xor s8, s8, t0  # shiftregister = shiftregister ^ swap
    addi s6, s6, -4  # ip = ip - 4
    jal zero, backend_Second_pass_loop  # continue looping

backend_UpdateShiftRegister_I:
    addiw a0, a0, 4  # add 4 due to this being 2nd part of AUIPC combo
    lui t1, 0x1  # Prepare upper immediate bits
    addiw t1, t1, -1  # Advance algorithm state
    and t1, a0, t1  # (value & 0xfff)
    slliw s7, t1, 0x14  # tempword = (value & 0xfff) << 20
    xor s8, s8, s7  # shiftregister = shiftregister ^ tempword
    jal zero, backend_Second_pass_loop  # Continue looping

backend_UpdateShiftRegister_B:
    addi t1, zero, 30  # | ((value & 0x1000) << (31 - 12))  , imm[12]
    and t1, a0, t1  # value & 0x1e
    slliw t0, t1, 0x7  # tempword = (value & 0x1e) << 7
    addi t1, zero, 2016  # Load immediate constant
    and t1, a0, t1  # value & 0x7e0
    slliw t1, t1, 0x14  # (value & 0x7e0) << (31 - 11)
    or t0, t0, t1  # logical or with the previous expression
    lui t1, 0x1  # Prepare upper immediate bits
    addiw t1, t1, -2048  # Advance algorithm state
    and t1, a0, t1  # value & 0x800
    srliw t1, t1, 0x4  # (value & 0x800) >> 4
    or t0, t0, t1  # logical or with the previous expression
    lui t1, 0x1  # Prepare upper immediate bits
    and t1, a0, t1  # value & 0x1000
    slliw t1, t1, 0x13  # (value & 0x1000) << (31 - 12)
    or s7, t0, t1  # tempword
    xor s8, s8, s7  # shiftregister = shiftregister ^ tempword
    jal zero, backend_Second_pass_loop  # Continue looping

backend_UpdateShiftRegister_J:
    addi t1, zero, 2046  # | ((value & 0x100000) << (31 - 20)) , imm[20]
    and t1, a0, t1  # value & 0x7fe
    slliw t0, t1, 0x14  # tempword = (value & 0x7fe) << 20
    lui t1, 0x1  # Prepare upper immediate bits
    addiw t1, t1, -2048  # Advance algorithm state
    and t1, a0, t1  # value & 0x800
    slliw t1, t1, 0x9  # (value & 0x800) << (20 - 11)
    or t0, t0, t1  # logical or with the previous expression
    lui t1, 0xFF  # Prepare upper immediate bits
    and t1, a0, t1  # value & 0xff000
    or t0, t0, t1  # logical or with the previous expression
    lui t1, 0x100  # Prepare upper immediate bits
    and t1, a0, t1  # value & 0x100000
    slliw t1, t1, 0xB  # (value & 0x100000) << (31 - 20)
    or s7, t0, t1  # tempword
    xor s8, s8, s7  # shiftregister = shiftregister ^ tempword
    jal zero, backend_Second_pass_loop  # Continue looping

backend_UpdateShiftRegister_U:
    lui t0, 0x1  # if value is 0x800 or more we have to add 11-th bit (0x1000) to compensate for signed extension
    addiw t0, t0, -2048  # if value is 0x800 or more we have to add 11-th bit (0x1000) to compensate for signed extension
    lui t1, 0x1  # Prepare upper immediate bits
    addiw t1, t1, -1  # Advance algorithm state
    lui t2, 0x100  # Prepare upper immediate bits
    addiw t2, t2, -1  # Advance algorithm state
    slli t2, t2, 0xC  # Shift bits to align field values
    and t1, a0, t1  # value & 0xfff
    and s7, a0, t2  # value & 0xfffff000
    blt t1, t0, backend_UpdateShiftRegister_U_small  # Branch when condition is satisfied
    lui t0, 0x1  # Deal with sign extension: add 0x1000
    addw s7, t0, s7  # (value & 0xfffff000) + 0x1000

backend_UpdateShiftRegister_U_small:
    xor s8, s8, s7  # shiftregister = shiftregister ^ tempword
    jal zero, backend_Second_pass_loop  # Continue looping

backend_StorePointer:
    addi s6, s6, 4  # Update ip
    addi a2, a0, 0  # Store label prefix
    addiw a1, zero, 513  # Get scratch
    slli a1, a1, 0x16  # Get scratch
    jal ra, backend_ClearScratch  # clear scratch
    jal ra, backend_consume_token  # consume token
    addi a5, a0, 0  # save char
    jal ra, backend_GetTarget  # Get target
    ld a1, 0(a0)  # Dereference pointer
    addi t1, zero, 62  # If char is > then change relative base address to ip
    beq t1, a5, backend_StorePointer_1  # Branch when condition is satisfied
    addi t1, zero, 38  # Check for &
    beq a2, t1, backend_StorePointer_0  # Branch when condition is satisfied
    addi t1, zero, 37  # Check for %
    bne a2, t1, backend_Fail  # Branch when condition is satisfied
    sub a1, a1, s6  # displacement = target - ip

backend_StorePointer_0:
    addi a5, zero, 4  # number of bytes

backend_StorePointer_loop:
    srli t1, a1, 0x8  # value / 256
    slli a0, t1, 0x8  # Shift bits to align field values
    sub a0, a1, a0  # byte = value % 256
    addi a1, t1, 0  # value = value / 256
    jal ra, backend_write_byte  # write value
    addi a5, a5, -1  # decrease number of bytes to write
    bne a5, zero, backend_StorePointer_loop  # continue looping
    jal zero, backend_Second_pass_loop  # Continue looping

backend_StorePointer_1:
    addi a2, a1, 0  # save target
    addiw a1, zero, 513  # Get scratch
    slli a1, a1, 0x16  # Get scratch
    jal ra, backend_ClearScratch  # clear scratch
    jal ra, backend_consume_token  # consume token
    jal ra, backend_GetTarget  # Get target
    ld a1, 0(a0)  # Dereference pointer
    sub a1, a2, a1  # displacement = target - ip
    jal zero, backend_StorePointer_0  # Continue looping

backend_Second_pass_done:
    ld ra, 0(sp)  # restore ra
    addi sp, sp, 8  # Deallocate stack
    jalr zero, 0(ra)  # return

backend_PadToAlign:
    addi t1, zero, 1  # t1 = 1
    and a0, s6, t1  # ip & 0x1
    bne a0, t1, backend_PadToAlign_1  # check if ip & 0x1 == 1
    add s6, s6, t1  # ip = ip + 1
    bne a1, zero, backend_PadToAlign_1  # check if we have to write
    addi a0, zero, 0  # a0 = 0
    jal ra, backend_write_byte  # write 0

backend_PadToAlign_1:
    addi t1, zero, 2  # t1 = 2
    and a0, s6, t1  # ip & 0x2
    bne a0, t1, backend_PadToAlign_2  # check if ip & 0x2 == 2
    add s6, s6, t1  # ip = ip + 2
    bne a1, zero, backend_PadToAlign_2  # check if we have to write
    addi a0, zero, 0  # a0 = 0
    jal ra, backend_write_byte  # write 0
    addi a0, zero, 0  # a0 = 0
    jal ra, backend_write_byte  # write 0

backend_PadToAlign_2:
    beq a1, zero, backend_Second_pass_loop  # return to Second_pass
    jal zero, backend_First_pass_loop  # return to First_pass

backend_ClearScratch:
    addi sp, sp, -24  # Allocate stack
    sd ra, 0(sp)  # protect ra
    sd a0, 8(sp)  # protect a0
    sd a1, 16(sp)  # protect a1
    addiw a0, zero, 513  # scratch address
    slli a0, a0, 0x16  # scratch address
    addi a1, zero, 512  # scratch size in bytes

backend_ClearScratch_loop:
    sb zero, 0(a0)  # Write zero: s[i] = 0
    addi a0, a0, 1  # Increment: i = i + 1
    addi a1, a1, -1  # remaining bytes--
    bne a1, zero, backend_ClearScratch_loop  # Keep looping
    ld ra, 0(sp)  # restore ra
    ld a0, 8(sp)  # restore a0
    ld a1, 16(sp)  # restore a1
    addi sp, sp, 24  # Deallocate stack
    jalr zero, 0(ra)  # return

backend_consume_token:
    addi sp, sp, -8  # Allocate stack
    sd ra, 0(sp)  # protect ra

backend_consume_token_0:
    bge s2, s11, backend_consume_token_done  # Check bounds
    jal ra, backend_Read_byte  # Read byte into a0
    addi t1, zero, 9  # Check for \t
    beq a0, t1, backend_consume_token_done  # Branch when condition is satisfied
    addi t1, zero, 10  # Check for \n
    beq a0, t1, backend_consume_token_done  # Branch when condition is satisfied
    addi t1, zero, 32  # Check for ' '
    beq a0, t1, backend_consume_token_done  # Branch when condition is satisfied
    addi t1, zero, 62  # Check for >
    beq a0, t1, backend_consume_token_done  # Branch when condition is satisfied
    sb a0, 0(a1)  # Store char
    addi a1, a1, 1  # Point to next spot
    jal zero, backend_consume_token_0  # Continue looping

backend_consume_token_done:
    sd zero, 0(a1)  # Pad with nulls
    addi a1, a1, 8  # Update the pointer
    ld ra, 0(sp)  # restore ra
    addi sp, sp, 8  # Deallocate stack
    jalr zero, 0(ra)  # return

backend_DoByte:
    addi sp, sp, -16  # Allocate stack
    sd ra, 0(sp)  # protect ra
    sd a6, 8(sp)  # protect a6
    jal ra, backend_hex  # Process hex, store it in a6
    blt a6, zero, backend_DoByte_Done  # Deal with unrecognized characters
    bne s4, zero, backend_DoByte_NotToggle  # Check if toggle is set
    bne a1, zero, backend_DoByte_1  # check if we have to write
    addi t0, zero, 255  # First, calculate new shiftregister
    and t0, s8, t0  # sr_nextb = shiftregister & 0xff
    srliw s8, s8, 0x8  # shiftregister >> 8
    xor t0, t0, a6  # hex(c) ^ sr_nextb
    slli t1, s5, 0x4  # hold * 16
    add a0, t0, t1  # (hold * 16) + hex(c) ^ sr_nextb()
    jal ra, backend_write_byte  # write it

backend_DoByte_1:
    addi s6, s6, 1  # Increment IP
    beq a2, zero, backend_DoByte_2  # check if we have to update

backend_DoByte_2b:
    addi s5, zero, 0  # hold = 0
    jal zero, backend_DoByte_FlipToggle  # return

backend_DoByte_NotToggle:
    addi s5, a6, 0  # hold = hex(c)

backend_DoByte_FlipToggle:
    xori s4, s4, -1  # Flip the toggle

backend_DoByte_Done:
    ld ra, 0(sp)  # restore ra
    ld a6, 8(sp)  # restore a6
    addi sp, sp, 16  # Deallocate stack
    jalr zero, 0(ra)  # return

backend_DoByte_2:
    slli t1, s5, 0x4  # hold * 16
    add s5, t1, a6  # hold = hold * 16 + hex(c)
    slli t1, s7, 0x8  # tempword << 8
    xor s7, t1, s5  # tempword = (tempword << 8) ^ hold
    addi s10, s10, 1  # updates = updates + 1
    jal zero, backend_DoByte_2b  # Jump unconditionally to backend_DoByte_2b

backend_hex:
    addi sp, sp, -16  # Allocate stack
    sd ra, 0(sp)  # protect ra
    sd a1, 8(sp)  # protect a1
    addi t1, zero, 35  # deal with line comments starting with #
    beq a0, t1, backend_ascii_comment  # a0 eq to '#'
    addi t1, zero, 59  # deal with line comments starting with ,
    beq a0, t1, backend_ascii_comment  # a0 eq to ','
    addi t1, zero, 48  # deal all ascii less than 0
    blt a0, t1, backend_ascii_other  # Branch when condition is satisfied
    addi t1, zero, 58  # deal with 0-9
    blt a0, t1, backend_ascii_num  # Branch when condition is satisfied
    addi t1, zero, 65  # deal with all ascii less than A
    blt a0, t1, backend_ascii_other  # Branch when condition is satisfied
    addi t1, zero, 71  # deal with A-F
    blt a0, t1, backend_ascii_high  # Branch when condition is satisfied
    addi t1, zero, 97  # deal with all ascii less than a
    blt a0, t1, backend_ascii_other  # Branch when condition is satisfied
    addi t1, zero, 103  # deal with a-f
    blt a0, t1, backend_ascii_low  # Branch when condition is satisfied
    jal zero, backend_ascii_other  # The rest that remains needs to be ignored

backend_ascii_num:
    addi t1, zero, 48  # '0' -> 0
    sub a6, a0, t1  # Update arithmetic value
    jal zero, backend_hex_return  # return

backend_ascii_low:
    addi t1, zero, 87  # 'a' -> 0xA
    sub a6, a0, t1  # Update arithmetic value
    jal zero, backend_hex_return  # return

backend_ascii_high:
    addi t1, zero, 55  # 'A' -> 0xA
    sub a6, a0, t1  # Update arithmetic value
    jal zero, backend_hex_return  # return

backend_ascii_other:
    addi a6, zero, -1  # Return -1
    jal zero, backend_hex_return  # return

backend_ascii_comment:
    bge s2, s11, backend_ascii_comment_done  # Check bounds
    jal ra, backend_Read_byte  # Call backend_Read_byte
    addi t1, zero, 13  # CR
    beq a0, t1, backend_ascii_comment_done  # Branch when condition is satisfied
    addi t1, zero, 10  # LF
    bne a0, t1, backend_ascii_comment  # Keep reading comment

backend_ascii_comment_done:
    addi a6, zero, -1  # Return -1

backend_hex_return:
    ld ra, 0(sp)  # restore ra
    ld a1, 8(sp)  # restore a1
    addi sp, sp, 16  # Deallocate stack
    jalr zero, 0(ra)  # return

backend_Read_byte:
    lb a0, 0(s2)  # Load byte from buffer
    addi s2, s2, 1  # Advance buffer pointer
    jalr zero, 0(ra)  # return

backend_read_uart:
    lui t0, 0x10000  # UART_LSR
    addiw t0, t0, 5  # UART_LSR

backend_poll_rx:
    lb a0, 0(t0)  # Read LSR
    andi a0, a0, 1  # Check bit 0 (Data Ready)
    beq a0, zero, backend_poll_rx  # If no data ready, keep polling
    lui t0, 0x10000  # UART_BASE
    lb a0, 0(t0)  # Read received byte
    jalr zero, 0(ra)  # return

backend_GetTarget:
    addi sp, sp, -8  # Allocate stack
    sd ra, 0(sp)  # protect ra
    addi t0, s1, 0  # grab jump_table

backend_GetTarget_loop_0:
    addiw t1, zero, 513  # scratch
    slli t1, t1, 0x16  # scratch
    ld t2, 16(t0)  # I->name

backend_GetTarget_loop:
    lbu t4, 0(t2)  # I->name[i]
    lbu t3, 0(t1)  # scratch[i]
    bne t3, t4, backend_GetTarget_miss  # strings don't match
    addi t1, t1, 1  # Look at the next char
    addi t2, t2, 1  # Advance algorithm state
    bne t4, zero, backend_GetTarget_loop  # Loop until zero (end of string)
    jal zero, backend_GetTarget_done  # We have a match

backend_GetTarget_miss:
    ld t0, 0(t0)  # I = I->next
    beq t0, zero, backend_Fail  # Abort, no match found
    jal zero, backend_GetTarget_loop_0  # Try another label

backend_GetTarget_done:
    addi a0, t0, 8  # Get target address
    ld ra, 0(sp)  # restore ra
    addi sp, sp, 8  # Deallocate stack
    jalr zero, 0(ra)  # return

backend_StoreLabel:
    addi sp, sp, -8  # Allocate stack
    sd ra, 0(sp)  # protect ra
    addi a0, s9, 0  # struct entry
    addi s9, s9, 24  # calloc
    sd s6, 8(a0)  # entry->target = ip
    sd s1, 0(a0)  # entry->next = jump_table
    addi s1, a0, 0  # jump_table = entry
    sd s9, 16(a0)  # entry->name = token
    addi a1, s9, 0  # Write after struct
    jal ra, backend_consume_token  # Collect string
    addi s9, a1, 0  # update HEAP
    ld ra, 0(sp)  # restore ra
    addi sp, sp, 8  # Deallocate stack
    jal zero, backend_First_pass_loop  # return

backend_write_byte:
    sb a0, 0(a7)  # Write byte to output buffer
    addi a7, a7, 1  # Advance output pointer
    jalr zero, 0(ra)  # return

backend_Fail:
    jal zero, backend_Fail  # Halt (infinite loop) - indicates an error
