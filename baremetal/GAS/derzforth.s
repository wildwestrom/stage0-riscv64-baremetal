## SPDX-FileCopyrightText: 2021 Andrew Dailey
## SPDX-FileCopyrightText: 2026 Christian Westrom
## SPDX-License-Identifier: MIT
##
.text
.global _start
_start:
## MIT License
##
## Copyright (c) 2021 Andrew Dailey
## Copyright (c) 2026 Christian Westrom
##
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to deal
## in the Software without restriction, including without limitation the rights
## to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
## copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all
## copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
## OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
## SOFTWARE.
##

## GNU assembler port of DerzForth for the QEMU `virt` machine used in this
## repository. This file is checked in intentionally; do not regenerate it at
## build time. See LICENSES/MIT.txt for the canonical license text.

# jump to "main" since programs execute top to bottom
# we do this to enable writing helper funcs at the top
    j main

# pull in the necessary defs / funcs for a given board
#  (based on the assembler's search path)
#
# this file should define:
#   RAM_BASE_ADDR
#   RAM_SIZE
#   ROM_BASE_ADDR
#   ROM_SIZE
#
# and implement:
#   serial_init(a0: baud_rate)
#   serial_getc() -> a0: char
#   serial_putc(a0: char)
    .include "baremetal/GAS/derzforth_qemu_virt_board.inc"


#  16KB      Memory Map
# 0x0000 |----------------|
#        |                |
#        |                |
#        |                |
#        |   Interpreter  |
#        |       +        | 12KB
#        |   Dictionary   |
#        |                |
#        |                |
#        |                |
# 0x3000 |----------------|
#        |      s2       | 1KB
# 0x3400 |----------------|
#        |  Return Stack  | 1KB (256 calls deep)
# 0x3800 |----------------|
#        |                |
#        |   Data Stack   | 2KB (512 elements)
#        |                |
# 0x4000 |----------------|

    .equ INTERPRETER_BASE_ADDR, 0x0000
    .equ TIB_BASE_ADDR, 0x3000
    .equ RETURN_STACK_BASE_ADDR, 0x3400
    .equ DATA_STACK_BASE_ADDR, 0x3800

    .equ INTERPRETER_SIZE, 0x3000  # 12KB
    .equ TIB_SIZE, 0x0400  # 1KB
    .equ RETURN_STACK_SIZE, 0x0400  # 1KB
    .equ DATA_STACK_SIZE, 0x0800  # 2KB

    .equ DERZFORTH_SIZE, 0x4000  # 16KB
    .equ HEAP_BASE_ADDR, RAM_BASE_ADDR + DERZFORTH_SIZE
    .equ HEAP_SIZE, RAM_SIZE - DERZFORTH_SIZE

    .equ SERIAL_BAUD_RATE, 115200

# word flags (top 2 bits of hash)
    .equ FLAGS_MASK, 0xc0000000
    .equ F_IMMEDIATE, 0x80000000
    .equ F_HIDDEN, 0x40000000


# Func: memclr
# Arg: a0 = buffer addr
# Arg: a1 = buffer size
# Ret: none
memclr:
    beqz a1, memclr_done  # loop til size == 0
    sb zero, 0(a0)           # 0 -> [addr]
    addi a0, a0, 1        # addr += 1
    addi a1, a1, -1       # size -= 1
    j memclr              # repeat
memclr_done:
    ret


# Func: memcpy
# Arg: a0 = src buffer addr
# Arg: a1 = dst buffer addr
# Arg: a2 = buffer size
# Ret: none
memcpy:
    beqz a2, memcpy_done  # loop til size == 0
    lb t0, 0(a0)          # t0 <- [src]
    sb t0, 0(a1)          # t0 -> [dst]
    addi a0, a0, 1        # src += 1
    addi a1, a1, 1        # dst += 1
    addi a2, a2, -1       # size -= 1
    j memcpy              # repeat
memcpy_done:
    ret


# Func: strtok
# Arg: a0 = buffer addr
# Arg: a1 = buffer size
# Ret: a0 = token addr (0 if not found)
# Ret: a1 = token size (0 if not found)
# Ret: a2 = total bytes consumed (0 if not found)
strtok:
    addi t0, zero, ' '         # t0 = whitespace threshold
    mv t2, a0                  # save buffer's start addr for later
strtok_skip_whitespace:
    beqz a1, strtok_not_found  # not found if we run out of chars
    lbu t1, 0(a0)              # pull the next char
    bgtu t1, t0, strtok_scan   # if not whitespace, start the scan
    addi a0, a0, 1             # else advance ptr by one char
    addi a1, a1, -1            # and reduce size by 1
    j strtok_skip_whitespace   # repeat
strtok_scan:
    mv t3, a0                  # save the token's start addr for later
strtok_scan_loop:
    beqz a1, strtok_not_found  # early exit if reached EOB
    lbu t1, 0(a0)              # grab the next char
    bleu t1, t0, strtok_found  # if found whitespace, we are done
    addi a0, a0, 1             # else advance ptr by one char
    addi a1, a1, -1            # and reduce size by 1
    j strtok_scan_loop         # repeat
strtok_found:
    sub a2, a0, t2             # a2 = (end - buffer) = bytes consumed
    addi a2, a2, 1             # add one to include the delimiter
    sub a1, a0, t3             # a1 = (end - start) = token size
    mv a0, t3                  # a0 = start = token addr
    ret
strtok_not_found:
    addi a0, zero, 0           # a0 = 0 (not found)
    addi a1, zero, 0           # a1 = 0 (not found)
    addi a2, zero, 0           # a2 = 0 (not found)
    ret


# Func: lookup
# Arg: a0 = addr of latest entry in word dict
# Arg: a1 = hash of word name to lookup
# Ret: a0 = addr of found word (0 if not found)
lookup:
    beqz a0, lookup_not_found  # not found if next word addr is 0 (end of dict)
    lw t0, 4(a0)               # t0 = hash of word name

    # skip if the word is hidden
    li t1, F_HIDDEN            # load hidden flag into t1
    and t1, t0, t1             # isolate hidden bit in word hash
    bnez t1, lookup_next       # if hidden, skip this word and try the next one

    li t1, ~FLAGS_MASK         # t1 = inverted FLAGS_MASK
    and t0, t0, t1             # ignore flags when comparing hashes
    beq t0, a1, lookup_found   # done if hash (dict) matches hash (lookup)
lookup_next:
    lwu a0, 0(a0)               # follow link to next word in dict
    j lookup                   # repeat
lookup_found:
    # a0 is already pointing at the current dict entry
    ret
lookup_not_found:
    addi a0, zero, 0           # a0 = 0 (not found)
    ret


# Func: djb2_hash
# Arg: a0 = buffer addr
# Arg: a1 = buffer size
# Ret: a0 = hash value
djb2_hash:
    li t0, 5381         # t0 = hash value
djb2_hash_loop:
    beqz a1, djb2_hash_done
    lbu t2, 0(a0)       # c <- [addr]
    slliw t1, t0, 5     # t1 = h * 32 (32-bit wrap)
    addw t0, t1, t0     # h = h * 33 (32-bit wrap)
    addw t0, t0, t2     # h = h + c (32-bit wrap)
    addi a0, a0, 1      # addr += 1
    addi a1, a1, -1     # size -= 1
    j djb2_hash_loop    # repeat
djb2_hash_done:
    slli t0, t0, 32     # zero-extend the wrapped 32-bit hash
    srli t0, t0, 32
    li t1, ~FLAGS_MASK  # clear the top two bits (used for word flags)
    and a0, t0, t1      # a0 = final hash value
    ret


###
### interpreter
###

main:
    li a0, SERIAL_BAUD_RATE
    call serial_init

    # QEMU virt links DerzForth directly at RAM_BASE_ADDR.
    la s6, here
    la s7, latest
    j reset

error:
    # print " ?" and fall into reset
    li a0, ' '
    call serial_putc
    li a0, '?'
    call serial_putc
    li a0, '\n'
    call serial_putc

reset:
    # set working reg to zero
    li s0, 0

    # set interpreter state reg to 0 (execute)
    li s1, 0

    # setup data stack ptr
    li sp, RAM_BASE_ADDR + DATA_STACK_BASE_ADDR

    # setup return stack ptr
    li tp, RAM_BASE_ADDR + RETURN_STACK_BASE_ADDR

    # setup text input buffer addr
    li s2, RAM_BASE_ADDR + TIB_BASE_ADDR

    j interpreter

interpreter_ok:
    # print "ok" and fall into interpreter
    li a0, ' '
    call serial_putc
    li a0, 'o'
    call serial_putc
    li a0, 'k'
    call serial_putc
    li a0, '\n'
    call serial_putc

interpreter:

tib_clear:
    mv a0, s2       # a0 = buffer addr
    li a1, TIB_SIZE  # a1 = buffer size
    call memclr      # clear out the text input buffer

tib_init:
    mv s3, s2  # set s3 to s2
    li s4, 0    # set s4 to 0
    li s5, 0    # set s5 to 0

interpreter_repl:
    # read and echo a single char
    call serial_getc
    call serial_putc

    # check for single-line comment
    li t0, '\\'                           # comments start with \ char
    beq a0, t0, interpreter_skip_comment  # skip the comment if \ is found

    # check for bounded comments (parens)
    li t0, 0x28                           # bounded comments start with ( char
    beq a0, t0, interpreter_skip_parens   # skip the comment if ( is found

    # check for backspace
    li t0, '\b'
    bne a0, t0, interpreter_repl_char
    beqz s4, interpreter_repl  # ignore BS if s4 is zero

    # if backspace, dec s4 and send a space and another backspace
    #   this simulates clearing the char on the client side
    addi s4, s4, -1
    li a0, ' '
    call serial_putc
    li a0, '\b'
    call serial_putc

    j interpreter_repl

interpreter_skip_comment:
    # read and echo a single char
    call serial_getc
    call serial_putc

    # skip char until newline is found
    li t0, '\n'                           # newlines start with \n
    bne a0, t0, interpreter_skip_comment  # loop back to SKIP comment unless newline
    j interpreter_repl

interpreter_skip_parens:
    # read and echo a single char
    call serial_getc
    call serial_putc

    # skip char until closing parens is found
    li t0, 0x29                           # closing parens start with )
    bne a0, t0, interpreter_skip_parens   # loop back to SKIP parens unless closing parens
    j interpreter_repl

interpreter_repl_char:
    add t0, s3, s4   # t0 = dest addr for this char in s3
    li t1, TIB_SIZE      # t1 = buffer size
    bge s4, t1, error  # bounds check on s3
    sb a0, 0(t0)         # write char into s3
    addi s4, s4, 1   # s4 += 1
    addi t0, zero, '\n'  # t0 = newline char
    beq a0, t0, interpreter_interpret  # interpret the input upon newline
    j interpreter_repl

# TODO: allow multiline word defs
interpreter_interpret:
    # grab the next token
    add a0, s3, s5       # a0 = buffer addr
    sub a1, s4, s5       # a1 = buffer size
    call strtok              # a0 = str addr, a1 = str size, a2 = bytes consumed
    beqz a0, interpreter_ok  # loop back to REPL if input is used up
    add s5, s5, a2       # update s5 based on strtok bytes consumed

    # hash the current token
    call djb2_hash  # a0 = str hash

    # lookup the hash in the word dict
    mv a1, a0       # a1 = hash of word name
    mv a0, s7   # a0 = addr of latest word
    call lookup     # a0 = addr of found word (0 if not found)
    beqz a0, error  # check for error from lookup

    # load and isolate the immediate flag
    lw t0, 4(a0)        # load word hash into t0
    li t1, F_IMMEDIATE  # load immediate flag into t1
    and t0, t0, t1      # isolate immediate bit in word hash

    # decide whether to compile or execute the word
    bnez t0, interpreter_execute     # execute if word is immediate...
    beqz s1, interpreter_execute  # or if s1 is 0 (execute)

interpreter_compile:
    addi t0, a0, 8      # t0 = addr of word's code field
    sw t0, 0(s6)      # write addr of word's code field to current definition
    addi s6, s6, 4  # s6 += 4
    j interpreter_interpret

interpreter_execute:
    # setup double-indirect addr back to interpreter loop
    la gp, interpreter_addr_addr
    addi s0, a0, 8  # s0 = addr of word's code field
    lwu t0, 0(s0)    # t0 = addr of word's body
    jr t0          # execute the word


    .balign 4
interpreter_addr:
    .word interpreter_interpret
interpreter_addr_addr:
    .word interpreter_addr

# standard forth routine: next
next:
    lwu s0, 0(gp)     # s0 <- [gp]
    addi gp, gp, 4  # gp += 4
    lwu t0, 0(s0)     # t0 <- [s0]
    jr t0

# standard forth routine: enter
enter:
    sw gp, 0(tp)     # gp -> [tp]
    addi tp, tp, 4  # tp += 4
    addi gp, s0, 4     # gp = s0 + 4 (skip code field)
    j next


###
### dictionary
###

    .balign 4
word_exit:
    .word 0
    .word 0x3c967e3f  # djb2_hash('exit')
code_exit:
    .word body_exit
body_exit:
    addi tp, tp, -4  # dec return stack ptr
    lwu gp, 0(tp)      # load next addr into gp
    j next

    .balign 4
word_colon:
    .word word_exit
    .word 0x0002b5df  # djb2_hash(':')
code_colon:
    .word body_colon
body_colon:
    # grab the next token
    add a0, s3, s5   # a0 = buffer addr
    sub a1, s4, s5   # a1 = buffer size
    call strtok          # a0 = str addr, a1 = str size
    beqz a0, error       # error and reset if strtok fails
    add s5, s5, a2   # update s5 based on strtok bytes consumed

    # hash the current token
    call djb2_hash       # a0 = str hash

    # set the hidden flag
    li t0, F_HIDDEN      # load hidden flag into t0
    or a0, a0, t0        # hide the word

    # write the word's link and hash
    sw s7, 0(s6)   # write link to prev word (s7 -> [s6])
    sw a0, 4(s6)       # write word name hash (hash -> [s6 + 4])
    mv s7, s6      # set s7 = s6 (before s6 gets modified)
    addi s6, s6, 8   # move s6 past link and hash (to start of code)

    # set word's code field to "enter"
    la t0, enter
    sw t0, 0(s6)       # write addr of "enter" to word definition
    addi s6, s6, 4   # s6 += 4
    addi s1, zero, 1  # s1 = 1 (compile)
    j next

    .balign 4
word_semi:
    .word word_colon
    .word 0x0002b5e0 | F_IMMEDIATE  # djb2_hash(';') or'd w/ F_IMMEDIATE flag
code_semi:
    .word body_semi
body_semi:
    # clear the hidden flag
    lw t0, 4(s7)     # load word name hash (t0 <- [s7+4])
    li t1, ~F_HIDDEN     # load hidden flag mask into t1
    and t0, t0, t1       # reveal the word
    sw t0, 4(s7)     # write word name hash (t0 -> [s7+4])

    la t0, code_exit
    sw t0, 0(s6)       # write addr of "code_exit" to word definition
    addi s6, s6, 4   # s6 += 4
    addi s1, zero, 0  # s1 = 0 (execute)
    j next

    .balign 4
word_at:
    .word word_semi
    .word 0x0002b5e5  # djb2_hash('@')
code_at:
    .word body_at
body_at:
    addi sp, sp, -4  # dec data stack ptr
    lwu t0, 0(sp)      # pop addr into t0
    lw t0, 0(t0)       # load value from addr
    sw t0, 0(sp)      # push value onto stack
    addi sp, sp, 4   # inc data stack ptr
    j next

    .balign 4
word_ex:
    .word word_at
    .word 0x0002b5c6  # djb2_hash('!')
code_ex:
    .word body_ex
body_ex:
    addi sp, sp, -8  # dec data stack ptr
    lwu t0, 4(sp)      # pop addr into t0
    lw t1, 0(sp)      # pop value into t1
    sw t1, 0(t0)       # store value at addr
    j next

    .balign 4
word_spat:
    .word word_ex
    .word 0x0b88aac8  # djb2_hash('sp@')
code_spat:
    .word body_spat
body_spat:
    mv t0, sp        # copy next sp addr
    addi t0, t0, -4   # dec to reach current sp addr
    sw t0, 0(sp)      # push addr onto data stack
    addi sp, sp, 4  # inc data stack ptr
    j next

    .balign 4
word_rpat:
    .word word_spat
    .word 0x0b88a687  # djb2_hash('rp@')
code_rpat:
    .word body_rpat
body_rpat:
    mv t0, tp        # copy next tp addr
    addi t0, t0, -4   # dec to reach current tp addr
    sw t0, 0(sp)      # push addr onto data stack
    addi sp, sp, 4  # inc data stack ptr
    j next

    .balign 4
word_zeroeq:
    .word word_rpat
    .word 0x005970b2  # djb2_hash('0=')
code_zeroeq:
    .word body_zeroeq
body_zeroeq:
    addi sp, sp, -4  # dec data stack ptr
    lw t0, 0(sp)      # pop value into t0
    addi t1, zero, 0   # setup initial result as 0
    bnez t0, notzero   #  0 if not zero
    addi t1, t1, -1    # -1 if zero
notzero:
    sw t1, 0(sp)      # push value onto stack
    addi sp, sp, 4   # inc data stack ptr
    j next

    .balign 4
word_plus:
    .word word_zeroeq
    .word 0x0002b5d0  # djb2_hash('+')
code_plus:
    .word body_plus
body_plus:
    addi sp, sp, -8  # dec data stack ptr
    lw t0, 4(sp)      # pop first value into t0
    lw t1, 0(sp)      # pop second value into t1
    add t0, t0, t1     # ADD the values together into t0
    sw t0, 0(sp)      # push value onto stack
    addi sp, sp, 4   # inc data stack ptr
    j next

    .balign 4
word_nand:
    .word word_plus
    .word 0x3c9b0c66  # djb2_hash('nand')
code_nand:
    .word body_nand
body_nand:
    addi sp, sp, -8  # dec data stack ptr
    lw t0, 4(sp)      # pop first value into t0
    lw t1, 0(sp)      # pop second value into t1
    and t0, t0, t1     # AND the values together into t0
    not t0, t0         # NOT t0 (invert the bits)
    sw t0, 0(sp)      # push value onto stack
    addi sp, sp, 4   # inc data stack ptr
    j next

    .balign 4
word_state:
    .word word_nand
    .word 0x10614a06  # djb2_hash('state')
code_state:
    .word body_state
body_state:
    sw s1, 0(sp)
    addi sp, sp, 4
    j next

    .balign 4
word_tib:
    .word word_state
    .word 0x0b88ae44  # djb2_hash('tib')
code_tib:
    .word body_tib
body_tib:
    sw s2, 0(sp)
    addi sp, sp, 4
    j next

    .balign 4
word_toin:
    .word word_tib
    .word 0x0b87c89a  # djb2_hash('>in')
code_toin:
    .word body_toin
body_toin:
    sw s5, 0(sp)
    addi sp, sp, 4
    j next

    .balign 4
word_here:
    .word word_toin
    .word 0x3c97d3a9  # djb2_hash('here')
code_here:
    .word body_here
body_here:
    sw s6, 0(sp)
    addi sp, sp, 4
    j next

    .balign 4
word_latest:
    .word word_here
    .word 0x0ae8ca72  # djb2_hash('latest')
code_latest:
    .word body_latest
body_latest:
    sw s7, 0(sp)
    addi sp, sp, 4
    j next

    .balign 4
word_key:
    .word word_latest
    .word 0x0b88878e  # djb2_hash('key')
code_key:
    .word body_key
body_key:
    call serial_getc  # read char into a0 via serial_getc
    sw a0, 0(sp)     # push char onto stack
    addi sp, sp, 4  # inc data stack ptr
    j next

    .balign 4
word_emit:
    .word word_key
    .word 0x3c964f74  # djb2_hash('emit')
code_emit:
    .word body_emit
body_emit:
    addi sp, sp, -4  # dec data stack ptr
    lw a0, 0(sp)      # pop char into a1
    call serial_putc   # emit the char via serial_putc
    j next

    .balign 4
latest:  # mark the latest builtin word
word_bye:
    .word word_emit
    .word 0x0b8863c5  # djb2_hash('bye')
code_bye:
    .word body_bye
body_bye:
    call qemu_poweroff
    j next

    .balign 4
here:  # next new word will go here
