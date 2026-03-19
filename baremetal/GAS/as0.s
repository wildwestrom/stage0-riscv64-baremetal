    .global _start
    .global compile_as0_program
    .text

.equ WORK_BASE,        0x80100000
.equ SOURCE_BASE,      0x80200000
.equ SOURCE_MAX,       131072
.equ STACK_TOP,        0x80500000
.equ UART_BASE,        0x10000000
.equ UART_LSR,         UART_BASE + 5
.equ UART_LSR_DATA_READY, 0x01
.equ UART_LSR_THR_EMPTY,  0x20
.equ TEST_FINISHER_BASE,  0x00100000
.equ TEST_FINISHER_PASS,  0x00005555
.equ TEST_FINISHER_FAIL,  0x00003333
.equ LABEL_COUNT_PTR,  WORK_BASE + 0x0000
.equ DEFINE_COUNT_PTR, WORK_BASE + 0x0004
.equ FAIL_LINE_PTR,    WORK_BASE + 0x0008
.equ FAIL_PHASE_PTR,   WORK_BASE + 0x000c
.equ FAIL_STAGE_PTR,   WORK_BASE + 0x0010
.equ LABELS_BASE,      WORK_BASE + 0x0100
.equ DEFINES_BASE,     WORK_BASE + 0x9000
.equ LINE_BASE,        WORK_BASE + 0xc000
.equ TOKEN_PTRS_BASE,  WORK_BASE + 0xc100

.equ LABEL_MAX,        512
.equ LABEL_NAME_MAX,   64
.equ LABEL_ENTRY_SIZE, 68
.equ DEFINE_MAX,       128
.equ DEFINE_ENTRY_SIZE,72
.equ LINE_MAX,         256
.equ TOKEN_MAX,        6

.equ RV_MATCH_ADD,     0x00000033
.equ RV_MATCH_ADDI,    0x00000013
.equ RV_MATCH_ADDIW,   0x0000001b
.equ RV_MATCH_ANDI,    0x00007013
.equ RV_MATCH_AND,     0x00007033
.equ RV_MATCH_AUIPC,   0x00000017
.equ RV_MATCH_BGE,     0x00005063
.equ RV_MATCH_BGEU,    0x00007063
.equ RV_MATCH_BLT,     0x00004063
.equ RV_MATCH_BLTU,    0x00006063
.equ RV_MATCH_BEQ,     0x00000063
.equ RV_MATCH_BNE,     0x00001063
.equ RV_MATCH_EBREAK,  0x00100073
.equ RV_MATCH_ECALL,   0x00000073
.equ RV_MATCH_FENCE,   0x0ff0000f
.equ RV_MATCH_FENCE_I, 0x0000100f
.equ RV_MATCH_JAL,     0x0000006f
.equ RV_MATCH_JALR,    0x00000067
.equ RV_MATCH_LBU,     0x00004003
.equ RV_MATCH_LD,      0x00003003
.equ RV_MATCH_LUI,     0x00000037
.equ RV_MATCH_LW,      0x00002003
.equ RV_MATCH_LWU,     0x00006003
.equ RV_MATCH_MUL,     0x02000033
.equ RV_MATCH_OR,      0x00006033
.equ RV_MATCH_SB,      0x00000023
.equ RV_MATCH_SD,      0x00003023
.equ RV_MATCH_SLLI,    0x00001013
.equ RV_MATCH_SLT,     0x00002033
.equ RV_MATCH_SLTIU,   0x00003013
.equ RV_MATCH_SLTU,    0x00003033
.equ RV_MATCH_SRLI,    0x00005013
.equ RV_MATCH_SUB,     0x40000033
.equ RV_MATCH_SUBW,    0x4000003b
.equ RV_MATCH_SW,      0x00002023
.equ RV_MATCH_XOR,     0x00004033
.equ RV_MATCH_XORI,    0x00004013

# s0 source
# s1 sink
# s2 diag
# s3 current output position

_start:
    la t0, stack_top_addr  # addr stack_top_addr -> t0
    ld sp, 0(t0)  # u64 0(t0) -> sp
    call read_source_from_uart  # call read_source_from_uart
    beq a0, zero, .Lboot_fail  # if a0 == zero goto .Lboot_fail

    addi sp, sp, -64  # sp += -64
    la t0, str_as0  # addr str_as0 -> t0
    sd t0, 0(sp)  # u64 t0 -> 0(sp)
    la t0, source_base_addr  # addr source_base_addr -> t0
    ld t0, 0(t0)  # u64 0(t0) -> t0
    sd t0, 8(sp)  # u64 t0 -> 8(sp)
    la t0, raw_sink_begin_program  # addr raw_sink_begin_program -> t0
    sd t0, 16(sp)  # u64 t0 -> 16(sp)
    la t0, raw_sink_write_byte  # addr raw_sink_write_byte -> t0
    sd t0, 24(sp)  # u64 t0 -> 24(sp)
    la t0, raw_sink_end_program  # addr raw_sink_end_program -> t0
    sd t0, 32(sp)  # u64 t0 -> 32(sp)
    sd zero, 40(sp)  # u64 zero -> 40(sp)
    sw zero, 48(sp)  # u32 zero -> 48(sp)
    sw zero, 52(sp)  # u32 zero -> 52(sp)
    sw zero, 56(sp)  # u32 zero -> 56(sp)

    mv a0, sp  # sp -> a0
    addi a1, sp, 16  # sp + 16 -> a1
    addi a2, sp, 48  # sp + 48 -> a2
    call compile_as0_program  # call compile_as0_program
    beq a0, zero, .Lboot_fail_after_frame  # if a0 == zero goto .Lboot_fail_after_frame

    addi sp, sp, 64  # sp += 64
    li a0, 0  # 0 -> a0
    j system_exit  # goto system_exit

.Lboot_fail_after_frame:
    addi sp, sp, 64  # sp += 64
.Lboot_fail:
    li a0, 1  # 1 -> a0
    j system_exit  # goto system_exit

raw_sink_begin_program:
    ret  # return

raw_sink_write_byte:
    li t0, UART_LSR  # UART_LSR -> t0
.Lraw_sink_write_wait:
    lbu t1, 0(t0)  # u8 0(t0) -> t1
    andi t1, t1, UART_LSR_THR_EMPTY  # t1 & UART_LSR_THR_EMPTY -> t1
    beq t1, zero, .Lraw_sink_write_wait  # if t1 == zero goto .Lraw_sink_write_wait
    li t0, UART_BASE  # UART_BASE -> t0
    sb a1, 0(t0)  # u8 a1 -> 0(t0)
    ret  # return

raw_sink_end_program:
    ret  # return

read_source_from_uart:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    sd s0, 16(sp)  # u64 s0 -> 16(sp)
    sd s1, 8(sp)  # u64 s1 -> 8(sp)
    sd s2, 0(sp)  # u64 s2 -> 0(sp)

    la s0, source_base_addr  # addr source_base_addr -> s0
    ld s0, 0(s0)  # u64 0(s0) -> s0
    li s1, SOURCE_MAX - 1  # SOURCE_MAX - 1 -> s1
    li s2, 0  # 0 -> s2
.Lread_source_loop:
    call uart_read  # call uart_read
    li t3, 4  # 4 -> t3
    beq a0, t3, .Lread_source_done  # if a0 == t3 goto .Lread_source_done
    bgeu s2, s1, .Lread_source_fail  # if s2 >=u s1 goto .Lread_source_fail
    sb a0, 0(s0)  # u8 a0 -> 0(s0)
    addi s0, s0, 1  # s0 + 1 -> s0
    addi s2, s2, 1  # s2 + 1 -> s2
    j .Lread_source_loop  # goto .Lread_source_loop
.Lread_source_done:
    sb zero, 0(s0)  # u8 zero -> 0(s0)
    li a0, 1  # 1 -> a0
    j .Lread_source_return  # goto .Lread_source_return
.Lread_source_fail:
    li a0, 0  # 0 -> a0
.Lread_source_return:
    ld s2, 0(sp)  # u64 0(sp) -> s2
    ld s1, 8(sp)  # u64 8(sp) -> s1
    ld s0, 16(sp)  # u64 16(sp) -> s0
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

uart_read:
    li t0, UART_LSR  # UART_LSR -> t0
.Luart_read_wait:
    lbu t1, 0(t0)  # u8 0(t0) -> t1
    andi t1, t1, UART_LSR_DATA_READY  # t1 & UART_LSR_DATA_READY -> t1
    beq t1, zero, .Luart_read_wait  # if t1 == zero goto .Luart_read_wait
    li t0, UART_BASE  # UART_BASE -> t0
    lbu a0, 0(t0)  # u8 0(t0) -> a0
    ret  # return

system_exit:
    li t0, TEST_FINISHER_BASE  # TEST_FINISHER_BASE -> t0
    beq a0, zero, .Lsystem_exit_pass  # if a0 == zero goto .Lsystem_exit_pass
    slli a0, a0, 48  # a0 << 48 -> a0
    srli a0, a0, 48  # a0 >> 48 -> a0
    bne a0, zero, .Lsystem_exit_fail_code_ok  # if a0 != zero goto .Lsystem_exit_fail_code_ok
    li a0, 1  # 1 -> a0
.Lsystem_exit_fail_code_ok:
    slli a0, a0, 16  # a0 << 16 -> a0
    li t1, TEST_FINISHER_FAIL  # TEST_FINISHER_FAIL -> t1
    or a0, a0, t1  # a0 | t1 -> a0
    sw a0, 0(t0)  # u32 a0 -> 0(t0)
.Lsystem_exit_spin:
    j .Lsystem_exit_spin  # goto .Lsystem_exit_spin
.Lsystem_exit_pass:
    li t1, TEST_FINISHER_PASS  # TEST_FINISHER_PASS -> t1
    sw t1, 0(t0)  # u32 t1 -> 0(t0)
    j .Lsystem_exit_spin  # goto .Lsystem_exit_spin

compile_as0_program:
    addi sp, sp, -80  # sp += -80
    sd ra, 72(sp)  # u64 ra -> 72(sp)
    sd s0, 64(sp)  # u64 s0 -> 64(sp)
    sd s1, 56(sp)  # u64 s1 -> 56(sp)
    sd s2, 48(sp)  # u64 s2 -> 48(sp)
    sd s3, 40(sp)  # u64 s3 -> 40(sp)
    sd s4, 32(sp)  # u64 s4 -> 32(sp)
    sd s5, 24(sp)  # u64 s5 -> 24(sp)
    sd s6, 16(sp)  # u64 s6 -> 16(sp)

    mv s1, a1  # a1 -> s1
    mv s2, a2  # a2 -> s2
    ld s0, 8(a0)  # u64 8(a0) -> s0
    sd a0, 8(sp)  # u64 a0 -> 8(sp)

    li t0, 0  # 0 -> t0
    la t1, label_count_addr  # addr label_count_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    la t1, define_count_addr  # addr define_count_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    sw t0, 0(s2)  # u32 t0 -> 0(s2)
    sw t0, 4(s2)  # u32 t0 -> 4(s2)
    sw t0, 8(s2)  # u32 t0 -> 8(s2)
    la t1, fail_line_addr  # addr fail_line_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    sw zero, 0(t1)  # u32 zero -> 0(t1)
    la t1, fail_phase_addr  # addr fail_phase_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    sw zero, 0(t1)  # u32 zero -> 0(t1)
    la t1, fail_stage_addr  # addr fail_stage_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    sw zero, 0(t1)  # u32 zero -> 0(t1)

    li s3, 0  # 0 -> s3
.Lpass1:
    lbu t0, 0(s0)  # u8 0(s0) -> t0
    beq t0, zero, .Lpass1_done  # if t0 == zero goto .Lpass1_done
    la t1, fail_line_addr  # addr fail_line_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    lw t0, 0(t1)  # i32 0(t1) -> t0
    addi t0, t0, 1  # t0 + 1 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    la t1, fail_phase_addr  # addr fail_phase_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    li t0, 1  # 1 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    la t1, fail_stage_addr  # addr fail_stage_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    li t0, 1  # 1 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    mv a0, s0  # s0 -> a0
    call read_line  # call read_line
    beq a1, zero, .Lfail  # if a1 == zero goto .Lfail
    mv s0, a0  # a0 -> s0
    la t1, fail_stage_addr  # addr fail_stage_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    li t0, 2  # 2 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    call tokenize_line  # call tokenize_line
    blt a0, zero, .Lfail  # if a0 < zero goto .Lfail
    beq a0, zero, .Lpass1  # if a0 == zero goto .Lpass1
    mv s4, a0  # a0 -> s4

    li a0, 0  # 0 -> a0
    call token_ptr  # call token_ptr
    mv s5, a0  # a0 -> s5
    call split_label  # call split_label
    beq a0, zero, .Lpass1_not_label  # if a0 == zero goto .Lpass1_not_label
    la t1, fail_stage_addr  # addr fail_stage_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    li t0, 3  # 3 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    mv a0, s5  # s5 -> a0
    mv a1, s3  # s3 -> a1
    call add_label  # call add_label
    beq a0, zero, .Lfail  # if a0 == zero goto .Lfail
    j .Lpass1  # goto .Lpass1

.Lpass1_not_label:
    la t1, fail_stage_addr  # addr fail_stage_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    li t0, 4  # 4 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    call line_size  # call line_size
    blt a0, zero, .Lfail  # if a0 < zero goto .Lfail
    add s3, s3, a0  # s3 + a0 -> s3
    j .Lpass1  # goto .Lpass1

.Lpass1_done:
    ld t0, 8(sp)  # u64 8(sp) -> t0
    ld s0, 8(t0)  # u64 8(t0) -> s0
    li s3, 0  # 0 -> s3
    la t1, fail_line_addr  # addr fail_line_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    sw zero, 0(t1)  # u32 zero -> 0(t1)
    la t1, fail_phase_addr  # addr fail_phase_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    li t0, 2  # 2 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    la t1, fail_stage_addr  # addr fail_stage_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    sw zero, 0(t1)  # u32 zero -> 0(t1)

    ld a5, 0(s1)  # u64 0(s1) -> a5
    ld a0, 8(sp)  # u64 8(sp) -> a0
    ld a1, 0(a0)  # u64 0(a0) -> a1
    mv a0, s1  # s1 -> a0
    jalr a5  # goto *a5

.Lpass2:
    lbu t0, 0(s0)  # u8 0(s0) -> t0
    beq t0, zero, .Lpass2_done  # if t0 == zero goto .Lpass2_done
    la t1, fail_line_addr  # addr fail_line_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    lw t0, 0(t1)  # i32 0(t1) -> t0
    addi t0, t0, 1  # t0 + 1 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    la t1, fail_stage_addr  # addr fail_stage_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    li t0, 5  # 5 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    mv a0, s0  # s0 -> a0
    call read_line  # call read_line
    beq a1, zero, .Lfail_after_begin  # if a1 == zero goto .Lfail_after_begin
    mv s0, a0  # a0 -> s0
    la t1, fail_stage_addr  # addr fail_stage_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    li t0, 6  # 6 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    call tokenize_line  # call tokenize_line
    blt a0, zero, .Lfail_after_begin  # if a0 < zero goto .Lfail_after_begin
    beq a0, zero, .Lpass2  # if a0 == zero goto .Lpass2
    mv s4, a0  # a0 -> s4

    li a0, 0  # 0 -> a0
    call token_ptr  # call token_ptr
    mv s5, a0  # a0 -> s5
    call split_label  # call split_label
    bne a0, zero, .Lpass2  # if a0 != zero goto .Lpass2
    la t1, fail_stage_addr  # addr fail_stage_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    li t0, 7  # 7 -> t0
    sw t0, 0(t1)  # u32 t0 -> 0(t1)
    call emit_line  # call emit_line
    beq a0, zero, .Lfail_after_begin  # if a0 == zero goto .Lfail_after_begin
    j .Lpass2  # goto .Lpass2

.Lpass2_done:
    sw s3, 4(s2)  # u32 s3 -> 4(s2)
    srli t0, s3, 2  # s3 >> 2 -> t0
    sw t0, 0(s2)  # u32 t0 -> 0(s2)
    sw zero, 8(s2)  # u32 zero -> 8(s2)

    ld a5, 16(s1)  # u64 16(s1) -> a5
    ld t0, 8(sp)  # u64 8(sp) -> t0
    ld a1, 0(t0)  # u64 0(t0) -> a1
    mv a0, s1  # s1 -> a0
    mv a2, s2  # s2 -> a2
    jalr a5  # goto *a5

    li a0, 1  # 1 -> a0
    j .Ldone  # goto .Ldone

.Lfail_after_begin:
    call debug_fail  # call debug_fail
    li a0, 0  # 0 -> a0
    j .Ldone  # goto .Ldone

.Lfail:
    call debug_fail  # call debug_fail
    li a0, 0  # 0 -> a0

.Ldone:
    ld ra, 72(sp)  # u64 72(sp) -> ra
    ld s0, 64(sp)  # u64 64(sp) -> s0
    ld s1, 56(sp)  # u64 56(sp) -> s1
    ld s2, 48(sp)  # u64 48(sp) -> s2
    ld s3, 40(sp)  # u64 40(sp) -> s3
    ld s4, 32(sp)  # u64 32(sp) -> s4
    ld s5, 24(sp)  # u64 24(sp) -> s5
    ld s6, 16(sp)  # u64 16(sp) -> s6
    addi sp, sp, 80  # sp += 80
    ret  # return

debug_fail:
    addi sp, sp, -16  # sp += -16
    sd ra, 8(sp)  # u64 ra -> 8(sp)
    ld a5, 8(s1)  # u64 8(s1) -> a5
    mv a0, s1  # s1 -> a0
    li a1, 'F'  # 'F' -> a1
    jalr a5  # goto *a5
    ld a5, 8(s1)  # u64 8(s1) -> a5
    mv a0, s1  # s1 -> a0
    la t0, fail_phase_addr  # addr fail_phase_addr -> t0
    ld t0, 0(t0)  # u64 0(t0) -> t0
    lw t0, 0(t0)  # i32 0(t0) -> t0
    addi a1, t0, '0'  # t0 + '0' -> a1
    jalr a5  # goto *a5
    ld a5, 8(s1)  # u64 8(s1) -> a5
    mv a0, s1  # s1 -> a0
    la t0, fail_stage_addr  # addr fail_stage_addr -> t0
    ld t0, 0(t0)  # u64 0(t0) -> t0
    lw t0, 0(t0)  # i32 0(t0) -> t0
    addi a1, t0, '0'  # t0 + '0' -> a1
    jalr a5  # goto *a5
    ld a5, 8(s1)  # u64 8(s1) -> a5
    mv a0, s1  # s1 -> a0
    la a1, fail_line_addr  # addr fail_line_addr -> a1
    ld a1, 0(a1)  # u64 0(a1) -> a1
    lw a1, 0(a1)  # i32 0(a1) -> a1
    andi a1, a1, 0xff  # a1 & 0xff -> a1
    jalr a5  # goto *a5
    ld a5, 8(s1)  # u64 8(s1) -> a5
    mv a0, s1  # s1 -> a0
    la a1, fail_line_addr  # addr fail_line_addr -> a1
    ld a1, 0(a1)  # u64 0(a1) -> a1
    lw a1, 0(a1)  # i32 0(a1) -> a1
    srli a1, a1, 8  # a1 >> 8 -> a1
    andi a1, a1, 0xff  # a1 & 0xff -> a1
    jalr a5  # goto *a5
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return

read_line:
    la t0, line_addr  # addr line_addr -> t0
    ld t0, 0(t0)  # u64 0(t0) -> t0
    li t1, 0  # 0 -> t1
.Lread_line_loop:
    lbu t2, 0(a0)  # u8 0(a0) -> t2
    beq t2, zero, .Lread_line_end  # if t2 == zero goto .Lread_line_end
    li t3, 10  # 10 -> t3
    beq t2, t3, .Lread_line_nl  # if t2 == t3 goto .Lread_line_nl
    li t3, LINE_MAX - 1  # LINE_MAX - 1 -> t3
    bgeu t1, t3, .Lread_line_fail  # if t1 >=u t3 goto .Lread_line_fail
    sb t2, 0(t0)  # u8 t2 -> 0(t0)
    addi t0, t0, 1  # t0 + 1 -> t0
    addi a0, a0, 1  # a0 + 1 -> a0
    addi t1, t1, 1  # t1 + 1 -> t1
    j .Lread_line_loop  # goto .Lread_line_loop
.Lread_line_nl:
    addi a0, a0, 1  # a0 + 1 -> a0
.Lread_line_end:
    sb zero, 0(t0)  # u8 zero -> 0(t0)
    li a1, 1  # 1 -> a1
    ret  # return
.Lread_line_fail:
    li a1, 0  # 0 -> a1
    ret  # return

tokenize_line:
    la t0, line_addr  # addr line_addr -> t0
    ld t0, 0(t0)  # u64 0(t0) -> t0
    la t1, token_ptrs_addr  # addr token_ptrs_addr -> t1
    ld t1, 0(t1)  # u64 0(t1) -> t1
    li t2, 0  # 0 -> t2
.Ltok_skip:
    lbu t3, 0(t0)  # u8 0(t0) -> t3
    beq t3, zero, .Ltok_done  # if t3 == zero goto .Ltok_done
    li t4, ' '  # ' ' -> t4
    beq t3, t4, .Ltok_advance  # if t3 == t4 goto .Ltok_advance
    li t4, '\t'  # '\t' -> t4
    beq t3, t4, .Ltok_advance  # if t3 == t4 goto .Ltok_advance
    li t4, ','  # li
    beq t3, t4, .Ltok_delim  # if t3 == t4 goto .Ltok_delim
    li t4, '('  # '(' -> t4
    beq t3, t4, .Ltok_delim  # if t3 == t4 goto .Ltok_delim
    li t4, ')'  # ')' -> t4
    beq t3, t4, .Ltok_delim  # if t3 == t4 goto .Ltok_delim
    li t4, '#'  # '#' -> t4
    beq t3, t4, .Ltok_done  # if t3 == t4 goto .Ltok_done
    li t4, ';'  # ';' -> t4
    beq t3, t4, .Ltok_done  # if t3 == t4 goto .Ltok_done
    li t4, '"'  # '"' -> t4
    beq t3, t4, .Ltok_string  # if t3 == t4 goto .Ltok_string
    li t4, '\''  # '\'' -> t4
    beq t3, t4, .Ltok_char  # if t3 == t4 goto .Ltok_char
    li t4, TOKEN_MAX  # TOKEN_MAX -> t4
    bgeu t2, t4, .Ltok_fail  # if t2 >=u t4 goto .Ltok_fail
    sd t0, 0(t1)  # u64 t0 -> 0(t1)
    addi t1, t1, 8  # t1 + 8 -> t1
.Ltok_scan:
    lbu t3, 0(t0)  # u8 0(t0) -> t3
    beq t3, zero, .Ltok_store  # if t3 == zero goto .Ltok_store
    li t4, ' '  # ' ' -> t4
    beq t3, t4, .Ltok_store_advance  # if t3 == t4 goto .Ltok_store_advance
    li t4, '\t'  # '\t' -> t4
    beq t3, t4, .Ltok_store_advance  # if t3 == t4 goto .Ltok_store_advance
    li t4, ','  # li
    beq t3, t4, .Ltok_store_advance  # if t3 == t4 goto .Ltok_store_advance
    li t4, '('  # '(' -> t4
    beq t3, t4, .Ltok_store_advance  # if t3 == t4 goto .Ltok_store_advance
    li t4, ')'  # ')' -> t4
    beq t3, t4, .Ltok_store_advance  # if t3 == t4 goto .Ltok_store_advance
    li t4, '#'  # '#' -> t4
    beq t3, t4, .Ltok_store_comment  # if t3 == t4 goto .Ltok_store_comment
    li t4, ';'  # ';' -> t4
    beq t3, t4, .Ltok_store_comment  # if t3 == t4 goto .Ltok_store_comment
    addi t0, t0, 1  # t0 + 1 -> t0
    j .Ltok_scan  # goto .Ltok_scan
.Ltok_store_comment:
    sb zero, 0(t0)  # u8 zero -> 0(t0)
    j .Ltok_store  # goto .Ltok_store
.Ltok_store_advance:
    sb zero, 0(t0)  # u8 zero -> 0(t0)
    addi t0, t0, 1  # t0 + 1 -> t0
.Ltok_store:
    addi t2, t2, 1  # t2 + 1 -> t2
    j .Ltok_skip  # goto .Ltok_skip
.Ltok_advance:
    addi t0, t0, 1  # t0 + 1 -> t0
    j .Ltok_skip  # goto .Ltok_skip
.Ltok_delim:
    sb zero, 0(t0)  # u8 zero -> 0(t0)
    addi t0, t0, 1  # t0 + 1 -> t0
    j .Ltok_skip  # goto .Ltok_skip
.Ltok_string:
    li t4, TOKEN_MAX  # TOKEN_MAX -> t4
    bgeu t2, t4, .Ltok_fail  # if t2 >=u t4 goto .Ltok_fail
    addi t0, t0, 1  # t0 + 1 -> t0
    sd t0, 0(t1)  # u64 t0 -> 0(t1)
    addi t1, t1, 8  # t1 + 8 -> t1
.Ltok_string_scan:
    lbu t3, 0(t0)  # u8 0(t0) -> t3
    beq t3, zero, .Ltok_fail  # if t3 == zero goto .Ltok_fail
    li t4, '"'  # '"' -> t4
    beq t3, t4, .Ltok_string_done  # if t3 == t4 goto .Ltok_string_done
    addi t0, t0, 1  # t0 + 1 -> t0
    j .Ltok_string_scan  # goto .Ltok_string_scan
.Ltok_string_done:
    sb zero, 0(t0)  # u8 zero -> 0(t0)
    addi t0, t0, 1  # t0 + 1 -> t0
    addi t2, t2, 1  # t2 + 1 -> t2
    j .Ltok_skip  # goto .Ltok_skip
.Ltok_char:
    li t4, TOKEN_MAX  # TOKEN_MAX -> t4
    bgeu t2, t4, .Ltok_fail  # if t2 >=u t4 goto .Ltok_fail
    sd t0, 0(t1)  # u64 t0 -> 0(t1)
    addi t1, t1, 8  # t1 + 8 -> t1
    addi t0, t0, 1  # t0 + 1 -> t0
.Ltok_char_scan:
    lbu t3, 0(t0)  # u8 0(t0) -> t3
    beq t3, zero, .Ltok_fail  # if t3 == zero goto .Ltok_fail
    li t4, '\\'  # '\\' -> t4
    beq t3, t4, .Ltok_char_escape  # if t3 == t4 goto .Ltok_char_escape
    li t4, '\''  # '\'' -> t4
    beq t3, t4, .Ltok_char_done  # if t3 == t4 goto .Ltok_char_done
    addi t0, t0, 1  # t0 + 1 -> t0
    j .Ltok_char_scan  # goto .Ltok_char_scan
.Ltok_char_escape:
    addi t0, t0, 1  # t0 + 1 -> t0
    lbu t3, 0(t0)  # u8 0(t0) -> t3
    beq t3, zero, .Ltok_fail  # if t3 == zero goto .Ltok_fail
    addi t0, t0, 1  # t0 + 1 -> t0
    j .Ltok_char_scan  # goto .Ltok_char_scan
.Ltok_char_done:
    addi t0, t0, 1  # t0 + 1 -> t0
    lbu t3, 0(t0)  # u8 0(t0) -> t3
    beq t3, zero, .Ltok_char_store  # if t3 == zero goto .Ltok_char_store
    li t4, ' '  # ' ' -> t4
    beq t3, t4, .Ltok_char_store  # if t3 == t4 goto .Ltok_char_store
    li t4, '\t'  # '\t' -> t4
    beq t3, t4, .Ltok_char_store  # if t3 == t4 goto .Ltok_char_store
    li t4, ','  # li
    beq t3, t4, .Ltok_char_store  # if t3 == t4 goto .Ltok_char_store
    li t4, '('  # '(' -> t4
    beq t3, t4, .Ltok_char_store  # if t3 == t4 goto .Ltok_char_store
    li t4, ')'  # ')' -> t4
    beq t3, t4, .Ltok_char_store  # if t3 == t4 goto .Ltok_char_store
    li t4, '#'  # '#' -> t4
    beq t3, t4, .Ltok_char_store  # if t3 == t4 goto .Ltok_char_store
    li t4, ';'  # ';' -> t4
    beq t3, t4, .Ltok_char_store  # if t3 == t4 goto .Ltok_char_store
    j .Ltok_fail  # goto .Ltok_fail
.Ltok_char_store:
    sb zero, 0(t0)  # u8 zero -> 0(t0)
    addi t2, t2, 1  # t2 + 1 -> t2
    j .Ltok_skip  # goto .Ltok_skip
.Ltok_done:
    mv a0, t2  # t2 -> a0
    ret  # return
.Ltok_fail:
    li a0, -1  # -1 -> a0
    ret  # return

line_size:
    addi sp, sp, -16  # sp += -16
    sd ra, 8(sp)  # u64 ra -> 8(sp)
    mv a0, s5  # s5 -> a0
    la a1, str_dot_equ  # addr str_dot_equ -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lline_size_equ  # if a0 != zero goto .Lline_size_equ
    mv a0, s5  # s5 -> a0
    la a1, str_dot_byte  # addr str_dot_byte -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lline_size_byte  # if a0 != zero goto .Lline_size_byte
    mv a0, s5  # s5 -> a0
    la a1, str_dot_word  # addr str_dot_word -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lline_size_word  # if a0 != zero goto .Lline_size_word
    mv a0, s5  # s5 -> a0
    la a1, str_dot_string  # addr str_dot_string -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lline_size_string  # if a0 != zero goto .Lline_size_string
    mv a0, s5  # s5 -> a0
    la a1, str_dot_align  # addr str_dot_align -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lline_size_align  # if a0 != zero goto .Lline_size_align
    mv a0, s5  # s5 -> a0
    la a1, str_dot_dword  # addr str_dot_dword -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lline_size_dword  # if a0 != zero goto .Lline_size_dword
    mv a0, s5  # s5 -> a0
    la a1, str_dot_global  # addr str_dot_global -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lline_size_nop  # if a0 != zero goto .Lline_size_nop
    mv a0, s5  # s5 -> a0
    la a1, str_dot_text  # addr str_dot_text -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lline_size_nop  # if a0 != zero goto .Lline_size_nop
    mv a0, s5  # s5 -> a0
    call instr_size  # call instr_size
    j .Lline_size_done  # goto .Lline_size_done
.Lline_size_equ:
    li t0, 3  # 3 -> t0
    beq s4, t0, .Lline_size_equ_eval  # if s4 == t0 goto .Lline_size_equ_eval
    li t0, 5  # 5 -> t0
    bne s4, t0, .Lline_size_fail  # if s4 != t0 goto .Lline_size_fail
.Lline_size_equ_eval:
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    mv s6, a0  # a0 -> s6
    li a0, 2  # 2 -> a0
    addi a1, s4, -2  # s4 + -2 -> a1
    call eval_expr_range  # call eval_expr_range
    beq a0, zero, .Lline_size_fail  # if a0 == zero goto .Lline_size_fail
    mv a0, s6  # s6 -> a0
    call add_define  # call add_define
    beq a0, zero, .Lline_size_fail  # if a0 == zero goto .Lline_size_fail
    li a0, 0  # 0 -> a0
    j .Lline_size_done  # goto .Lline_size_done
.Lline_size_byte:
    addi a0, s4, -1  # s4 + -1 -> a0
    blt a0, zero, .Lline_size_fail  # if a0 < zero goto .Lline_size_fail
    j .Lline_size_done  # goto .Lline_size_done
.Lline_size_word:
    li t0, 2  # 2 -> t0
    bltu s4, t0, .Lline_size_fail  # if s4 <u t0 goto .Lline_size_fail
    li a0, 4  # 4 -> a0
    j .Lline_size_done  # goto .Lline_size_done
.Lline_size_string:
    li t0, 2  # 2 -> t0
    bne s4, t0, .Lline_size_fail  # if s4 != t0 goto .Lline_size_fail
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call string_length  # call string_length
    addi a0, a0, 1  # a0 + 1 -> a0
    j .Lline_size_done  # goto .Lline_size_done
.Lline_size_align:
    andi t0, s3, 3  # s3 & 3 -> t0
    beq t0, zero, .Lline_size_align_done  # if t0 == zero goto .Lline_size_align_done
    li a0, 4  # 4 -> a0
    sub a0, a0, t0  # a0 - t0 -> a0
    j .Lline_size_done  # goto .Lline_size_done
.Lline_size_align_done:
    li a0, 0  # 0 -> a0
    j .Lline_size_done  # goto .Lline_size_done
.Lline_size_dword:
    li t0, 2  # 2 -> t0
    bltu s4, t0, .Lline_size_fail  # if s4 <u t0 goto .Lline_size_fail
    li a0, 8  # 8 -> a0
    j .Lline_size_done  # goto .Lline_size_done
.Lline_size_nop:
    li a0, 0  # 0 -> a0
    j .Lline_size_done  # goto .Lline_size_done
.Lline_size_fail:
    li a0, -1  # -1 -> a0
.Lline_size_done:
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return

token_ptr:
    la t0, token_ptrs_addr  # addr token_ptrs_addr -> t0
    ld t0, 0(t0)  # u64 0(t0) -> t0
    slli t1, a0, 3  # a0 << 3 -> t1
    add t0, t0, t1  # t0 + t1 -> t0
    ld a0, 0(t0)  # u64 0(t0) -> a0
    ret  # return

split_label:
    mv t0, a0  # a0 -> t0
.Lsplit_scan:
    lbu t1, 0(t0)  # u8 0(t0) -> t1
    beq t1, zero, .Lsplit_no  # if t1 == zero goto .Lsplit_no
    li t2, ':'  # ':' -> t2
    beq t1, t2, .Lsplit_yes  # if t1 == t2 goto .Lsplit_yes
    addi t0, t0, 1  # t0 + 1 -> t0
    j .Lsplit_scan  # goto .Lsplit_scan
.Lsplit_yes:
    lbu t1, 1(t0)  # u8 1(t0) -> t1
    bne t1, zero, .Lsplit_no  # if t1 != zero goto .Lsplit_no
    sb zero, 0(t0)  # u8 zero -> 0(t0)
    li a0, 1  # 1 -> a0
    ret  # return
.Lsplit_no:
    li a0, 0  # 0 -> a0
    ret  # return

instr_size:
    addi sp, sp, -16  # sp += -16
    sd ra, 8(sp)  # u64 ra -> 8(sp)
    la a1, str_addi  # addr str_addi -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_sd  # addr str_sd -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_ld  # addr str_ld -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_add  # addr str_add -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_sub  # addr str_sub -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_beq  # addr str_beq -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_jal  # addr str_jal -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_jalr  # addr str_jalr -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_lui  # addr str_lui -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_lbu  # addr str_lbu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_and  # addr str_and -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bge  # addr str_bge -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bgeu  # addr str_bgeu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_blt  # addr str_blt -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bltu  # addr str_bltu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bne  # addr str_bne -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_ebreak  # addr str_ebreak -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_ecall  # addr str_ecall -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_fence  # addr str_fence -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_fence_i  # addr str_fence_i -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_sb  # addr str_sb -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_or  # addr str_or -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_slt  # addr str_slt -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_sltiu  # addr str_sltiu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_sltu  # addr str_sltu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_subw  # addr str_subw -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_xor  # addr str_xor -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_xori  # addr str_xori -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_j  # addr str_j -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_jr  # addr str_jr -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_beqz  # addr str_beqz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bnez  # addr str_bnez -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_blez  # addr str_blez -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bgez  # addr str_bgez -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bltz  # addr str_bltz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bgtz  # addr str_bgtz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bgt  # addr str_bgt -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_ble  # addr str_ble -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bgtu  # addr str_bgtu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_bleu  # addr str_bleu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_call  # addr str_call -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_8  # if a0 != zero goto .Lsize_8
    mv a0, s5  # s5 -> a0
    la a1, str_tail  # addr str_tail -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_8  # if a0 != zero goto .Lsize_8
    mv a0, s5  # s5 -> a0
    la a1, str_mv  # addr str_mv -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_ret  # addr str_ret -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_li  # addr str_li -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_li  # if a0 != zero goto .Lsize_li
    mv a0, s5  # s5 -> a0
    la a1, str_la  # addr str_la -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_8  # if a0 != zero goto .Lsize_8
    mv a0, s5  # s5 -> a0
    la a1, str_lw  # addr str_lw -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_lwu  # addr str_lwu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_sw  # addr str_sw -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_slli  # addr str_slli -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_srli  # addr str_srli -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_andi  # addr str_andi -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_mul  # addr str_mul -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_neg  # addr str_neg -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_negw  # addr str_negw -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_not  # addr str_not -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_seqz  # addr str_seqz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_snez  # addr str_snez -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_sgtz  # addr str_sgtz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    mv a0, s5  # s5 -> a0
    la a1, str_sltz  # addr str_sltz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lsize_4  # if a0 != zero goto .Lsize_4
    li a0, -1  # -1 -> a0
    j .Linstr_size_done  # goto .Linstr_size_done
.Lsize_4:
    li a0, 4  # 4 -> a0
    j .Linstr_size_done  # goto .Linstr_size_done
.Lsize_8:
    li a0, 8  # 8 -> a0
    j .Linstr_size_done  # goto .Linstr_size_done
.Lsize_li:
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lsize_li_expr  # if s4 != t0 goto .Lsize_li_expr
    li a0, 2  # 2 -> a0
    li a1, 1  # 1 -> a1
    call eval_expr_range  # call eval_expr_range
    beq a0, zero, .Lsize_fail  # if a0 == zero goto .Lsize_fail
    j .Lsize_li_check  # goto .Lsize_li_check
.Lsize_li_expr:
    li t0, 5  # 5 -> t0
    bne s4, t0, .Lsize_fail  # if s4 != t0 goto .Lsize_fail
    li a0, 2  # 2 -> a0
    li a1, 3  # 3 -> a1
    call eval_expr_range  # call eval_expr_range
    beq a0, zero, .Lsize_fail  # if a0 == zero goto .Lsize_fail
.Lsize_li_check:
    li t0, -2048  # -2048 -> t0
    blt a1, t0, .Lsize_li_wide  # if a1 < t0 goto .Lsize_li_wide
    li t0, 2048  # 2048 -> t0
    bge a1, t0, .Lsize_li_wide  # if a1 >= t0 goto .Lsize_li_wide
    li a0, 4  # 4 -> a0
    j .Linstr_size_done  # goto .Linstr_size_done
.Lsize_li_wide:
    li t0, 0xfff  # 0xfff -> t0
    and t1, a1, t0  # a1 & t0 -> t1
    beq t1, zero, .Lsize_4  # if t1 == zero goto .Lsize_4
    j .Lsize_8  # goto .Lsize_8
.Lsize_fail:
    li a0, -1  # -1 -> a0
 .Linstr_size_done:
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return

emit_line:
    addi sp, sp, -16  # sp += -16
    sd ra, 8(sp)  # u64 ra -> 8(sp)
    mv a0, s5  # s5 -> a0
    la a1, str_dot_equ  # addr str_dot_equ -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lemit_line_equ  # if a0 != zero goto .Lemit_line_equ
    mv a0, s5  # s5 -> a0
    la a1, str_dot_byte  # addr str_dot_byte -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lemit_line_byte  # if a0 != zero goto .Lemit_line_byte
    mv a0, s5  # s5 -> a0
    la a1, str_dot_word  # addr str_dot_word -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lemit_line_word  # if a0 != zero goto .Lemit_line_word
    mv a0, s5  # s5 -> a0
    la a1, str_dot_string  # addr str_dot_string -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lemit_line_string  # if a0 != zero goto .Lemit_line_string
    mv a0, s5  # s5 -> a0
    la a1, str_dot_align  # addr str_dot_align -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lemit_line_align  # if a0 != zero goto .Lemit_line_align
    mv a0, s5  # s5 -> a0
    la a1, str_dot_dword  # addr str_dot_dword -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lemit_line_dword  # if a0 != zero goto .Lemit_line_dword
    mv a0, s5  # s5 -> a0
    la a1, str_dot_global  # addr str_dot_global -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lemit_line_nop  # if a0 != zero goto .Lemit_line_nop
    mv a0, s5  # s5 -> a0
    la a1, str_dot_text  # addr str_dot_text -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lemit_line_nop  # if a0 != zero goto .Lemit_line_nop
    mv a0, s5  # s5 -> a0
    call emit_instruction  # call emit_instruction
    j .Lemit_line_done  # goto .Lemit_line_done
.Lemit_line_equ:
    li a0, 1  # 1 -> a0
    j .Lemit_line_done  # goto .Lemit_line_done
.Lemit_line_byte:
    call emit_dot_byte  # call emit_dot_byte
    j .Lemit_line_done  # goto .Lemit_line_done
.Lemit_line_word:
    call emit_dot_word  # call emit_dot_word
    j .Lemit_line_done  # goto .Lemit_line_done
.Lemit_line_string:
    call emit_dot_string  # call emit_dot_string
    j .Lemit_line_done  # goto .Lemit_line_done
.Lemit_line_align:
    call emit_dot_align  # call emit_dot_align
    j .Lemit_line_done  # goto .Lemit_line_done
.Lemit_line_dword:
    call emit_dot_dword  # call emit_dot_dword
    j .Lemit_line_done  # goto .Lemit_line_done
.Lemit_line_nop:
    li a0, 1  # 1 -> a0
.Lemit_line_done:
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return

emit_instruction:
    addi sp, sp, -16  # sp += -16
    sd ra, 8(sp)  # u64 ra -> 8(sp)
    la a1, str_addi  # addr str_addi -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_addi  # if a0 != zero goto .Ldispatch_addi
    mv a0, s5  # s5 -> a0
    la a1, str_sd  # addr str_sd -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_sd  # if a0 != zero goto .Ldispatch_sd
    mv a0, s5  # s5 -> a0
    la a1, str_ld  # addr str_ld -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_ld  # if a0 != zero goto .Ldispatch_ld
    mv a0, s5  # s5 -> a0
    la a1, str_add  # addr str_add -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_add  # if a0 != zero goto .Ldispatch_add
    mv a0, s5  # s5 -> a0
    la a1, str_sub  # addr str_sub -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_sub  # if a0 != zero goto .Ldispatch_sub
    mv a0, s5  # s5 -> a0
    la a1, str_beq  # addr str_beq -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_beq  # if a0 != zero goto .Ldispatch_beq
    mv a0, s5  # s5 -> a0
    la a1, str_jal  # addr str_jal -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_jal  # if a0 != zero goto .Ldispatch_jal
    mv a0, s5  # s5 -> a0
    la a1, str_jalr  # addr str_jalr -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_jalr  # if a0 != zero goto .Ldispatch_jalr
    mv a0, s5  # s5 -> a0
    la a1, str_lui  # addr str_lui -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_lui  # if a0 != zero goto .Ldispatch_lui
    mv a0, s5  # s5 -> a0
    la a1, str_lbu  # addr str_lbu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_lbu  # if a0 != zero goto .Ldispatch_lbu
    mv a0, s5  # s5 -> a0
    la a1, str_and  # addr str_and -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_and  # if a0 != zero goto .Ldispatch_and
    mv a0, s5  # s5 -> a0
    la a1, str_bge  # addr str_bge -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bge  # if a0 != zero goto .Ldispatch_bge
    mv a0, s5  # s5 -> a0
    la a1, str_bgeu  # addr str_bgeu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bgeu  # if a0 != zero goto .Ldispatch_bgeu
    mv a0, s5  # s5 -> a0
    la a1, str_blt  # addr str_blt -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_blt  # if a0 != zero goto .Ldispatch_blt
    mv a0, s5  # s5 -> a0
    la a1, str_bltu  # addr str_bltu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bltu  # if a0 != zero goto .Ldispatch_bltu
    mv a0, s5  # s5 -> a0
    la a1, str_bne  # addr str_bne -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bne  # if a0 != zero goto .Ldispatch_bne
    mv a0, s5  # s5 -> a0
    la a1, str_ebreak  # addr str_ebreak -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_ebreak  # if a0 != zero goto .Ldispatch_ebreak
    mv a0, s5  # s5 -> a0
    la a1, str_ecall  # addr str_ecall -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_ecall  # if a0 != zero goto .Ldispatch_ecall
    mv a0, s5  # s5 -> a0
    la a1, str_fence  # addr str_fence -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_fence  # if a0 != zero goto .Ldispatch_fence
    mv a0, s5  # s5 -> a0
    la a1, str_fence_i  # addr str_fence_i -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_fence_i  # if a0 != zero goto .Ldispatch_fence_i
    mv a0, s5  # s5 -> a0
    la a1, str_sb  # addr str_sb -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_sb  # if a0 != zero goto .Ldispatch_sb
    mv a0, s5  # s5 -> a0
    la a1, str_or  # addr str_or -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_or  # if a0 != zero goto .Ldispatch_or
    mv a0, s5  # s5 -> a0
    la a1, str_slt  # addr str_slt -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_slt  # if a0 != zero goto .Ldispatch_slt
    mv a0, s5  # s5 -> a0
    la a1, str_sltiu  # addr str_sltiu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_sltiu  # if a0 != zero goto .Ldispatch_sltiu
    mv a0, s5  # s5 -> a0
    la a1, str_sltu  # addr str_sltu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_sltu  # if a0 != zero goto .Ldispatch_sltu
    mv a0, s5  # s5 -> a0
    la a1, str_subw  # addr str_subw -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_subw  # if a0 != zero goto .Ldispatch_subw
    mv a0, s5  # s5 -> a0
    la a1, str_xor  # addr str_xor -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_xor  # if a0 != zero goto .Ldispatch_xor
    mv a0, s5  # s5 -> a0
    la a1, str_xori  # addr str_xori -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_xori  # if a0 != zero goto .Ldispatch_xori
    mv a0, s5  # s5 -> a0
    la a1, str_j  # addr str_j -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_j  # if a0 != zero goto .Ldispatch_j
    mv a0, s5  # s5 -> a0
    la a1, str_jr  # addr str_jr -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_jr  # if a0 != zero goto .Ldispatch_jr
    mv a0, s5  # s5 -> a0
    la a1, str_beqz  # addr str_beqz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_beqz  # if a0 != zero goto .Ldispatch_beqz
    mv a0, s5  # s5 -> a0
    la a1, str_bnez  # addr str_bnez -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bnez  # if a0 != zero goto .Ldispatch_bnez
    mv a0, s5  # s5 -> a0
    la a1, str_blez  # addr str_blez -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_blez  # if a0 != zero goto .Ldispatch_blez
    mv a0, s5  # s5 -> a0
    la a1, str_bgez  # addr str_bgez -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bgez  # if a0 != zero goto .Ldispatch_bgez
    mv a0, s5  # s5 -> a0
    la a1, str_bltz  # addr str_bltz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bltz  # if a0 != zero goto .Ldispatch_bltz
    mv a0, s5  # s5 -> a0
    la a1, str_bgtz  # addr str_bgtz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bgtz  # if a0 != zero goto .Ldispatch_bgtz
    mv a0, s5  # s5 -> a0
    la a1, str_bgt  # addr str_bgt -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bgt  # if a0 != zero goto .Ldispatch_bgt
    mv a0, s5  # s5 -> a0
    la a1, str_ble  # addr str_ble -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_ble  # if a0 != zero goto .Ldispatch_ble
    mv a0, s5  # s5 -> a0
    la a1, str_bgtu  # addr str_bgtu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bgtu  # if a0 != zero goto .Ldispatch_bgtu
    mv a0, s5  # s5 -> a0
    la a1, str_bleu  # addr str_bleu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_bleu  # if a0 != zero goto .Ldispatch_bleu
    mv a0, s5  # s5 -> a0
    la a1, str_call  # addr str_call -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_call  # if a0 != zero goto .Ldispatch_call
    mv a0, s5  # s5 -> a0
    la a1, str_tail  # addr str_tail -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_tail  # if a0 != zero goto .Ldispatch_tail
    mv a0, s5  # s5 -> a0
    la a1, str_mv  # addr str_mv -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_mv  # if a0 != zero goto .Ldispatch_mv
    mv a0, s5  # s5 -> a0
    la a1, str_ret  # addr str_ret -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_ret  # if a0 != zero goto .Ldispatch_ret
    mv a0, s5  # s5 -> a0
    la a1, str_li  # addr str_li -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_li  # if a0 != zero goto .Ldispatch_li
    mv a0, s5  # s5 -> a0
    la a1, str_la  # addr str_la -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_la  # if a0 != zero goto .Ldispatch_la
    mv a0, s5  # s5 -> a0
    la a1, str_lw  # addr str_lw -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_lw  # if a0 != zero goto .Ldispatch_lw
    mv a0, s5  # s5 -> a0
    la a1, str_lwu  # addr str_lwu -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_lwu  # if a0 != zero goto .Ldispatch_lwu
    mv a0, s5  # s5 -> a0
    la a1, str_sw  # addr str_sw -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_sw  # if a0 != zero goto .Ldispatch_sw
    mv a0, s5  # s5 -> a0
    la a1, str_slli  # addr str_slli -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_slli  # if a0 != zero goto .Ldispatch_slli
    mv a0, s5  # s5 -> a0
    la a1, str_srli  # addr str_srli -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_srli  # if a0 != zero goto .Ldispatch_srli
    mv a0, s5  # s5 -> a0
    la a1, str_andi  # addr str_andi -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_andi  # if a0 != zero goto .Ldispatch_andi
    mv a0, s5  # s5 -> a0
    la a1, str_mul  # addr str_mul -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_mul  # if a0 != zero goto .Ldispatch_mul
    mv a0, s5  # s5 -> a0
    la a1, str_neg  # addr str_neg -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_neg  # if a0 != zero goto .Ldispatch_neg
    mv a0, s5  # s5 -> a0
    la a1, str_negw  # addr str_negw -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_negw  # if a0 != zero goto .Ldispatch_negw
    mv a0, s5  # s5 -> a0
    la a1, str_not  # addr str_not -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_not  # if a0 != zero goto .Ldispatch_not
    mv a0, s5  # s5 -> a0
    la a1, str_seqz  # addr str_seqz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_seqz  # if a0 != zero goto .Ldispatch_seqz
    mv a0, s5  # s5 -> a0
    la a1, str_snez  # addr str_snez -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_snez  # if a0 != zero goto .Ldispatch_snez
    mv a0, s5  # s5 -> a0
    la a1, str_sgtz  # addr str_sgtz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_sgtz  # if a0 != zero goto .Ldispatch_sgtz
    mv a0, s5  # s5 -> a0
    la a1, str_sltz  # addr str_sltz -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Ldispatch_sltz  # if a0 != zero goto .Ldispatch_sltz
    li a0, 0  # 0 -> a0
    j .Lemit_instruction_done  # goto .Lemit_instruction_done

.Ldispatch_addi:
    call emit_addi  # call emit_addi
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_sd:
    call emit_sd  # call emit_sd
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_ld:
    call emit_ld  # call emit_ld
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_add:
    call emit_add  # call emit_add
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_sub:
    call emit_sub  # call emit_sub
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_beq:
    call emit_beq  # call emit_beq
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_jal:
    call emit_jal  # call emit_jal
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_jalr:
    call emit_jalr  # call emit_jalr
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_lui:
    call emit_lui  # call emit_lui
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_lbu:
    call emit_lbu  # call emit_lbu
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_and:
    call emit_and  # call emit_and
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bge:
    li a1, RV_MATCH_BGE  # RV_MATCH_BGE -> a1
    call emit_b_common  # call emit_b_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bgeu:
    li a1, RV_MATCH_BGEU  # RV_MATCH_BGEU -> a1
    call emit_b_common  # call emit_b_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_blt:
    li a1, RV_MATCH_BLT  # RV_MATCH_BLT -> a1
    call emit_b_common  # call emit_b_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bltu:
    li a1, RV_MATCH_BLTU  # RV_MATCH_BLTU -> a1
    call emit_b_common  # call emit_b_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bne:
    li a1, RV_MATCH_BNE  # RV_MATCH_BNE -> a1
    call emit_b_common  # call emit_b_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_ebreak:
    li a1, RV_MATCH_EBREAK  # RV_MATCH_EBREAK -> a1
    call emit_fixed  # call emit_fixed
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_ecall:
    li a1, RV_MATCH_ECALL  # RV_MATCH_ECALL -> a1
    call emit_fixed  # call emit_fixed
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_fence:
    li a1, RV_MATCH_FENCE  # RV_MATCH_FENCE -> a1
    call emit_fixed  # call emit_fixed
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_fence_i:
    li a1, RV_MATCH_FENCE_I  # RV_MATCH_FENCE_I -> a1
    call emit_fixed  # call emit_fixed
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_or:
    call emit_or  # call emit_or
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_slt:
    call emit_slt  # call emit_slt
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_sltiu:
    li a1, RV_MATCH_SLTIU  # RV_MATCH_SLTIU -> a1
    call emit_i_common  # call emit_i_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_sltu:
    call emit_sltu  # call emit_sltu
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_subw:
    call emit_subw  # call emit_subw
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_xor:
    call emit_xor  # call emit_xor
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_xori:
    li a1, RV_MATCH_XORI  # RV_MATCH_XORI -> a1
    call emit_i_common  # call emit_i_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_j:
    call emit_j  # call emit_j
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_jr:
    call emit_jr  # call emit_jr
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_beqz:
    li a1, RV_MATCH_BEQ  # RV_MATCH_BEQ -> a1
    call emit_b_zero_rs  # call emit_b_zero_rs
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bnez:
    li a1, RV_MATCH_BNE  # RV_MATCH_BNE -> a1
    call emit_b_zero_rs  # call emit_b_zero_rs
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_blez:
    li a1, RV_MATCH_BGE  # RV_MATCH_BGE -> a1
    call emit_b_zero_left  # call emit_b_zero_left
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bgez:
    li a1, RV_MATCH_BGE  # RV_MATCH_BGE -> a1
    call emit_b_zero_rs  # call emit_b_zero_rs
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bltz:
    li a1, RV_MATCH_BLT  # RV_MATCH_BLT -> a1
    call emit_b_zero_rs  # call emit_b_zero_rs
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bgtz:
    li a1, RV_MATCH_BLT  # RV_MATCH_BLT -> a1
    call emit_b_zero_left  # call emit_b_zero_left
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bgt:
    li a1, RV_MATCH_BLT  # RV_MATCH_BLT -> a1
    call emit_b_swap  # call emit_b_swap
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_ble:
    li a1, RV_MATCH_BGE  # RV_MATCH_BGE -> a1
    call emit_b_swap  # call emit_b_swap
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bgtu:
    li a1, RV_MATCH_BLTU  # RV_MATCH_BLTU -> a1
    call emit_b_swap  # call emit_b_swap
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_bleu:
    li a1, RV_MATCH_BGEU  # RV_MATCH_BGEU -> a1
    call emit_b_swap  # call emit_b_swap
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_call:
    li a0, 1  # 1 -> a0
    li a1, 1  # 1 -> a1
    li a2, 1  # 1 -> a2
    call emit_call_like  # call emit_call_like
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_tail:
    li a0, 0  # 0 -> a0
    li a1, 6  # 6 -> a1
    li a2, 0  # 0 -> a2
    call emit_call_like  # call emit_call_like
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_mv:
    call emit_mv  # call emit_mv
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_ret:
    call emit_ret  # call emit_ret
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_li:
    call emit_li  # call emit_li
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_la:
    call emit_la  # call emit_la
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_lw:
    li a1, RV_MATCH_LW  # RV_MATCH_LW -> a1
    call emit_load_common  # call emit_load_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_lwu:
    li a1, RV_MATCH_LWU  # RV_MATCH_LWU -> a1
    call emit_load_common  # call emit_load_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_sw:
    li a1, RV_MATCH_SW  # RV_MATCH_SW -> a1
    call emit_s_common  # call emit_s_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_slli:
    li a1, RV_MATCH_SLLI  # RV_MATCH_SLLI -> a1
    call emit_i_common  # call emit_i_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_srli:
    li a1, RV_MATCH_SRLI  # RV_MATCH_SRLI -> a1
    call emit_i_common  # call emit_i_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_andi:
    li a1, RV_MATCH_ANDI  # RV_MATCH_ANDI -> a1
    call emit_i_common  # call emit_i_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_mul:
    li a0, 1  # 1 -> a0
    li a1, RV_MATCH_MUL  # RV_MATCH_MUL -> a1
    call emit_r_common  # call emit_r_common
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_neg:
    li a1, RV_MATCH_SUB  # RV_MATCH_SUB -> a1
    call emit_zero_left_r  # call emit_zero_left_r
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_negw:
    li a1, RV_MATCH_SUBW  # RV_MATCH_SUBW -> a1
    call emit_zero_left_r  # call emit_zero_left_r
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_not:
    call emit_not  # call emit_not
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_seqz:
    call emit_seqz  # call emit_seqz
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_snez:
    li a1, RV_MATCH_SLTU  # RV_MATCH_SLTU -> a1
    call emit_zero_left_r  # call emit_zero_left_r
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_sgtz:
    li a1, RV_MATCH_SLT  # RV_MATCH_SLT -> a1
    call emit_zero_left_r  # call emit_zero_left_r
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_sltz:
    li a1, RV_MATCH_SLT  # RV_MATCH_SLT -> a1
    call emit_zero_right_r  # call emit_zero_right_r
    j .Lemit_instruction_done  # goto .Lemit_instruction_done
.Ldispatch_sb:
    call emit_sb  # call emit_sb
.Lemit_instruction_done:
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return

emit_add:
    li a0, 1  # 1 -> a0
    li a1, RV_MATCH_ADD  # RV_MATCH_ADD -> a1
    j emit_r_common  # goto emit_r_common
emit_or:
    li a0, 1  # 1 -> a0
    li a1, RV_MATCH_OR  # RV_MATCH_OR -> a1
    j emit_r_common  # goto emit_r_common
emit_slt:
    li a0, 1  # 1 -> a0
    li a1, RV_MATCH_SLT  # RV_MATCH_SLT -> a1
    j emit_r_common  # goto emit_r_common
emit_sltu:
    li a0, 1  # 1 -> a0
    li a1, RV_MATCH_SLTU  # RV_MATCH_SLTU -> a1
    j emit_r_common  # goto emit_r_common
emit_sub:
    li a0, 1  # 1 -> a0
    li a1, RV_MATCH_SUB  # RV_MATCH_SUB -> a1
    j emit_r_common  # goto emit_r_common
emit_subw:
    li a0, 1  # 1 -> a0
    li a1, RV_MATCH_SUBW  # RV_MATCH_SUBW -> a1
    j emit_r_common  # goto emit_r_common
emit_and:
    li a0, 1  # 1 -> a0
    li a1, RV_MATCH_AND  # RV_MATCH_AND -> a1
    j emit_r_common  # goto emit_r_common
emit_xor:
    li a0, 1  # 1 -> a0
    li a1, RV_MATCH_XOR  # RV_MATCH_XOR -> a1
    j emit_r_common  # goto emit_r_common

emit_r_common:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 4  # 4 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li a0, 3  # 3 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 8(sp)  # u32 a1 -> 8(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    lw t3, 8(sp)  # i32 8(sp) -> t3
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 15  # t2 << 15 -> t2
    slli t3, t3, 20  # t3 << 20 -> t3
    or t0, s6, t1  # s6 | t1 -> t0
    or t0, t0, t2  # t0 | t2 -> t0
    or a0, t0, t3  # t0 | t3 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_addi:
    li a1, RV_MATCH_ADDI  # RV_MATCH_ADDI -> a1
    j emit_i_common  # goto emit_i_common
emit_jalr:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 2  # 2 -> t0
    beq s4, t0, .Lemit_jalr_one  # if s4 == t0 goto .Lemit_jalr_one
    li t0, 4  # 4 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    li a1, RV_MATCH_JALR  # RV_MATCH_JALR -> a1
    call emit_i_common  # call emit_i_common
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return
.Lemit_jalr_one:
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li t1, 1  # 1 -> t1
    sw t1, 0(sp)  # u32 t1 -> 0(sp)
    sw zero, 8(sp)  # u32 zero -> 8(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    lw t3, 8(sp)  # i32 8(sp) -> t3
    li t4, 0xfff  # 0xfff -> t4
    and t3, t3, t4  # t3 & t4 -> t3
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 15  # t2 << 15 -> t2
    slli t3, t3, 20  # t3 << 20 -> t3
    li t4, RV_MATCH_JALR  # RV_MATCH_JALR -> t4
    or t0, t4, t1  # t4 | t1 -> t0
    or t0, t0, t2  # t0 | t2 -> t0
    or a0, t0, t3  # t0 | t3 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return
emit_ld:
    li a1, RV_MATCH_LD  # RV_MATCH_LD -> a1
    j emit_load_common  # goto emit_load_common
emit_lbu:
    li a1, RV_MATCH_LBU  # RV_MATCH_LBU -> a1
    j emit_load_common  # goto emit_load_common
emit_lui:
    li a1, RV_MATCH_LUI  # RV_MATCH_LUI -> a1
    j emit_u_common  # goto emit_u_common

emit_mv:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 15  # t2 << 15 -> t2
    li t3, RV_MATCH_ADDI  # RV_MATCH_ADDI -> t3
    or t0, t3, t1  # t3 | t1 -> t0
    or a0, t0, t2  # t0 | t2 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_ret:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 1  # 1 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    li t1, 1  # 1 -> t1
    slli t1, t1, 15  # t1 << 15 -> t1
    li t2, RV_MATCH_JALR  # RV_MATCH_JALR -> t2
    or a0, t2, t1  # t2 | t1 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_li:
    addi sp, sp, -48  # sp += -48
    sd ra, 40(sp)  # u64 ra -> 40(sp)
    li t0, 3  # 3 -> t0
    beq s4, t0, .Lemit_li_parse  # if s4 == t0 goto .Lemit_li_parse
    li t0, 5  # 5 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
.Lemit_li_parse:
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 24(sp)  # u32 a1 -> 24(sp)
    li t0, 3  # 3 -> t0
    beq s4, t0, .Lemit_li_one  # if s4 == t0 goto .Lemit_li_one
    li a0, 2  # 2 -> a0
    li a1, 3  # 3 -> a1
    call eval_expr_range  # call eval_expr_range
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    j .Lemit_li_have_imm  # goto .Lemit_li_have_imm
.Lemit_li_one:
    li a0, 2  # 2 -> a0
    li a1, 1  # 1 -> a1
    call eval_expr_range  # call eval_expr_range
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
.Lemit_li_have_imm:
    sw a1, 20(sp)  # u32 a1 -> 20(sp)
    li t0, -2048  # -2048 -> t0
    blt a1, t0, .Lemit_li_wide  # if a1 < t0 goto .Lemit_li_wide
    li t0, 2048  # 2048 -> t0
    bge a1, t0, .Lemit_li_wide  # if a1 >= t0 goto .Lemit_li_wide
    lw t1, 24(sp)  # i32 24(sp) -> t1
    lw t2, 20(sp)  # i32 20(sp) -> t2
    li t3, 0xfff  # 0xfff -> t3
    and t2, t2, t3  # t2 & t3 -> t2
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 20  # t2 << 20 -> t2
    li t3, RV_MATCH_ADDI  # RV_MATCH_ADDI -> t3
    or t0, t3, t1  # t3 | t1 -> t0
    or a0, t0, t2  # t0 | t2 -> a0
    call emit_word  # call emit_word
    ld ra, 40(sp)  # u64 40(sp) -> ra
    addi sp, sp, 48  # sp += 48
    ret  # return
.Lemit_li_wide:
    lw t0, 20(sp)  # i32 20(sp) -> t0
    li t1, 0xfff  # 0xfff -> t1
    and t2, t0, t1  # t0 & t1 -> t2
    li t3, 0xfffff000  # 0xfffff000 -> t3
    and t4, t0, t3  # t0 & t3 -> t4
    li t5, 0x800  # 0x800 -> t5
    bltu t2, t5, .Lemit_li_hi_ready  # if t2 <u t5 goto .Lemit_li_hi_ready
    li t5, 0x1000  # 0x1000 -> t5
    add t4, t4, t5  # t4 + t5 -> t4
.Lemit_li_hi_ready:
    lw t1, 24(sp)  # i32 24(sp) -> t1
    slli t1, t1, 7  # t1 << 7 -> t1
    srli t5, t4, 12  # t4 >> 12 -> t5
    slli t5, t5, 12  # t5 << 12 -> t5
    li t6, RV_MATCH_LUI  # RV_MATCH_LUI -> t6
    or t6, t6, t1  # t6 | t1 -> t6
    or a0, t6, t5  # t6 | t5 -> a0
    call emit_word  # call emit_word
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    beq t2, zero, .Lemit_li_done  # if t2 == zero goto .Lemit_li_done
    lw t1, 24(sp)  # i32 24(sp) -> t1
    lw t2, 20(sp)  # i32 20(sp) -> t2
    li t3, 0xfff  # 0xfff -> t3
    and t2, t2, t3  # t2 & t3 -> t2
    slli t1, t1, 7  # t1 << 7 -> t1
    lw t4, 24(sp)  # i32 24(sp) -> t4
    slli t4, t4, 15  # t4 << 15 -> t4
    slli t2, t2, 20  # t2 << 20 -> t2
    li t5, RV_MATCH_ADDIW  # RV_MATCH_ADDIW -> t5
    or t0, t5, t1  # t5 | t1 -> t0
    or t0, t0, t4  # t0 | t4 -> t0
    or a0, t0, t2  # t0 | t2 -> a0
    call emit_word  # call emit_word
.Lemit_li_done:
    ld ra, 40(sp)  # u64 40(sp) -> ra
    addi sp, sp, 48  # sp += 48
    ret  # return

emit_la:
    addi sp, sp, -48  # sp += -48
    sd ra, 40(sp)  # u64 ra -> 40(sp)
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 24(sp)  # u32 a1 -> 24(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sub t0, a1, s3  # a1 - s3 -> t0
    li t1, 0xfff  # 0xfff -> t1
    and t2, t0, t1  # t0 & t1 -> t2
    li t3, 0xfffff000  # 0xfffff000 -> t3
    and t4, t0, t3  # t0 & t3 -> t4
    li t5, 0x800  # 0x800 -> t5
    bltu t2, t5, .Lemit_la_hi_ready  # if t2 <u t5 goto .Lemit_la_hi_ready
    li t5, 0x1000  # 0x1000 -> t5
    add t4, t4, t5  # t4 + t5 -> t4
.Lemit_la_hi_ready:
    lw t1, 24(sp)  # i32 24(sp) -> t1
    slli t1, t1, 7  # t1 << 7 -> t1
    srli t5, t4, 12  # t4 >> 12 -> t5
    slli t5, t5, 12  # t5 << 12 -> t5
    li t6, RV_MATCH_AUIPC  # RV_MATCH_AUIPC -> t6
    or t6, t6, t1  # t6 | t1 -> t6
    or a0, t6, t5  # t6 | t5 -> a0
    call emit_word  # call emit_word
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    lw t1, 24(sp)  # i32 24(sp) -> t1
    slli t1, t1, 7  # t1 << 7 -> t1
    lw t3, 24(sp)  # i32 24(sp) -> t3
    slli t3, t3, 15  # t3 << 15 -> t3
    li t4, 0xfff  # 0xfff -> t4
    and t2, t2, t4  # t2 & t4 -> t2
    slli t2, t2, 20  # t2 << 20 -> t2
    li t5, RV_MATCH_ADDI  # RV_MATCH_ADDI -> t5
    or t0, t5, t1  # t5 | t1 -> t0
    or t0, t0, t3  # t0 | t3 -> t0
    or a0, t0, t2  # t0 | t2 -> a0
    call emit_word  # call emit_word
    ld ra, 40(sp)  # u64 40(sp) -> ra
    addi sp, sp, 48  # sp += 48
    ret  # return

emit_i_common:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 4  # 4 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li a0, 3  # 3 -> a0
    li a1, 1  # 1 -> a1
    call eval_expr_range  # call eval_expr_range
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 8(sp)  # u32 a1 -> 8(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    lw t3, 8(sp)  # i32 8(sp) -> t3
    li t4, 0xfff  # 0xfff -> t4
    and t3, t3, t4  # t3 & t4 -> t3
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 15  # t2 << 15 -> t2
    slli t3, t3, 20  # t3 << 20 -> t3
    or t0, s6, t1  # s6 | t1 -> t0
    or t0, t0, t2  # t0 | t2 -> t0
    or a0, t0, t3  # t0 | t3 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_load_common:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 4  # 4 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_value  # call parse_value
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 8(sp)  # u32 a1 -> 8(sp)
    li a0, 3  # 3 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    lw t3, 8(sp)  # i32 8(sp) -> t3
    li t4, 0xfff  # 0xfff -> t4
    and t3, t3, t4  # t3 & t4 -> t3
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 15  # t2 << 15 -> t2
    slli t3, t3, 20  # t3 << 20 -> t3
    or t0, s6, t1  # s6 | t1 -> t0
    or t0, t0, t2  # t0 | t2 -> t0
    or a0, t0, t3  # t0 | t3 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_sd:
    li a1, RV_MATCH_SD  # RV_MATCH_SD -> a1
    j emit_s_common  # goto emit_s_common
emit_sb:
    li a1, RV_MATCH_SB  # RV_MATCH_SB -> a1
    j emit_s_common  # goto emit_s_common

emit_s_common:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 4  # 4 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_value  # call parse_value
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 8(sp)  # u32 a1 -> 8(sp)
    li a0, 3  # 3 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    lw t3, 8(sp)  # i32 8(sp) -> t3
    srli t4, t3, 5  # t3 >> 5 -> t4
    andi t4, t4, 0x7f  # t4 & 0x7f -> t4
    slli t4, t4, 25  # t4 << 25 -> t4
    andi t5, t3, 0x1f  # t3 & 0x1f -> t5
    slli t5, t5, 7  # t5 << 7 -> t5
    slli t1, t1, 15  # t1 << 15 -> t1
    slli t2, t2, 20  # t2 << 20 -> t2
    or t0, s6, t4  # s6 | t4 -> t0
    or t0, t0, t5  # t0 | t5 -> t0
    or t0, t0, t1  # t0 | t1 -> t0
    or a0, t0, t2  # t0 | t2 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_beq:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 4  # 4 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    li s6, RV_MATCH_BEQ  # RV_MATCH_BEQ -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li a0, 3  # 3 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    sub t3, a1, s3  # a1 - s3 -> t3
    srli t4, t3, 12  # t3 >> 12 -> t4
    andi t4, t4, 1  # t4 & 1 -> t4
    slli t4, t4, 31  # t4 << 31 -> t4
    srli t5, t3, 5  # t3 >> 5 -> t5
    andi t5, t5, 0x3f  # t5 & 0x3f -> t5
    slli t5, t5, 25  # t5 << 25 -> t5
    srli t6, t3, 1  # t3 >> 1 -> t6
    andi t6, t6, 0xf  # t6 & 0xf -> t6
    slli t6, t6, 8  # t6 << 8 -> t6
    srli a2, t3, 11  # t3 >> 11 -> a2
    andi a2, a2, 1  # a2 & 1 -> a2
    slli a2, a2, 7  # a2 << 7 -> a2
    slli t1, t1, 15  # t1 << 15 -> t1
    slli t2, t2, 20  # t2 << 20 -> t2
    or t0, s6, t4  # s6 | t4 -> t0
    or t0, t0, t5  # t0 | t5 -> t0
    or t0, t0, t6  # t0 | t6 -> t0
    or t0, t0, a2  # t0 | a2 -> t0
    or t0, t0, t1  # t0 | t1 -> t0
    or a0, t0, t2  # t0 | t2 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_jal:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    lw t1, 0(sp)  # i32 0(sp) -> t1
    sub t2, a1, s3  # a1 - s3 -> t2
    srli t3, t2, 20  # t2 >> 20 -> t3
    andi t3, t3, 1  # t3 & 1 -> t3
    slli t3, t3, 31  # t3 << 31 -> t3
    srli t4, t2, 1  # t2 >> 1 -> t4
    andi t4, t4, 0x3ff  # t4 & 0x3ff -> t4
    slli t4, t4, 21  # t4 << 21 -> t4
    srli t5, t2, 11  # t2 >> 11 -> t5
    andi t5, t5, 1  # t5 & 1 -> t5
    slli t5, t5, 20  # t5 << 20 -> t5
    srli t6, t2, 12  # t2 >> 12 -> t6
    andi t6, t6, 0xff  # t6 & 0xff -> t6
    slli t6, t6, 12  # t6 << 12 -> t6
    slli t1, t1, 7  # t1 << 7 -> t1
    or t0, t1, t3  # t1 | t3 -> t0
    or t0, t0, t4  # t0 | t4 -> t0
    or t0, t0, t5  # t0 | t5 -> t0
    or t0, t0, t6  # t0 | t6 -> t0
    li t1, RV_MATCH_JAL  # RV_MATCH_JAL -> t1
    or a0, t0, t1  # t0 | t1 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_u_common:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_value  # call parse_value
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 12  # t2 << 12 -> t2
    or t0, s6, t1  # s6 | t1 -> t0
    or a0, t0, t2  # t0 | t2 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_fixed:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 1  # 1 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv a0, a1  # a1 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_b_common:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 4  # 4 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li a0, 3  # 3 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    j emit_b_with_regs  # goto emit_b_with_regs

emit_b_zero_rs:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    lw t1, 0(sp)  # i32 0(sp) -> t1
    li t2, 0  # 0 -> t2
    j emit_b_with_regs  # goto emit_b_with_regs

emit_b_zero_left:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    li t1, 0  # 0 -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    j emit_b_with_regs  # goto emit_b_with_regs

emit_b_swap:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 4  # 4 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 3  # 3 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    j emit_b_with_regs  # goto emit_b_with_regs

emit_b_with_regs:
    sub t3, a1, s3  # a1 - s3 -> t3
    srli t4, t3, 12  # t3 >> 12 -> t4
    andi t4, t4, 1  # t4 & 1 -> t4
    slli t4, t4, 31  # t4 << 31 -> t4
    srli t5, t3, 5  # t3 >> 5 -> t5
    andi t5, t5, 0x3f  # t5 & 0x3f -> t5
    slli t5, t5, 25  # t5 << 25 -> t5
    srli t6, t3, 1  # t3 >> 1 -> t6
    andi t6, t6, 0xf  # t6 & 0xf -> t6
    slli t6, t6, 8  # t6 << 8 -> t6
    srli a2, t3, 11  # t3 >> 11 -> a2
    andi a2, a2, 1  # a2 & 1 -> a2
    slli a2, a2, 7  # a2 << 7 -> a2
    slli t1, t1, 15  # t1 << 15 -> t1
    slli t2, t2, 20  # t2 << 20 -> t2
    or t0, s6, t4  # s6 | t4 -> t0
    or t0, t0, t5  # t0 | t5 -> t0
    or t0, t0, t6  # t0 | t6 -> t0
    or t0, t0, a2  # t0 | a2 -> t0
    or t0, t0, t1  # t0 | t1 -> t0
    or a0, t0, t2  # t0 | t2 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_j:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 2  # 2 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    li t1, 0  # 0 -> t1
    sw t1, 0(sp)  # u32 t1 -> 0(sp)
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    lw t1, 0(sp)  # i32 0(sp) -> t1
    sub t2, a1, s3  # a1 - s3 -> t2
    j emit_j_with_rd  # goto emit_j_with_rd

emit_jr:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 2  # 2 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    li a1, RV_MATCH_JALR  # RV_MATCH_JALR -> a1
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li t1, 0  # 0 -> t1
    sw t1, 0(sp)  # u32 t1 -> 0(sp)
    sw t1, 8(sp)  # u32 t1 -> 8(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    lw t3, 8(sp)  # i32 8(sp) -> t3
    li t4, 0xfff  # 0xfff -> t4
    and t3, t3, t4  # t3 & t4 -> t3
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 15  # t2 << 15 -> t2
    slli t3, t3, 20  # t3 << 20 -> t3
    or t0, s6, t1  # s6 | t1 -> t0
    or t0, t0, t2  # t0 | t2 -> t0
    or a0, t0, t3  # t0 | t3 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_call_like:
    addi sp, sp, -48  # sp += -48
    sd ra, 40(sp)  # u64 ra -> 40(sp)
    sw a0, 24(sp)  # u32 a0 -> 24(sp)
    sw a1, 20(sp)  # u32 a1 -> 20(sp)
    sw a2, 16(sp)  # u32 a2 -> 16(sp)
    li t0, 2  # 2 -> t0
    bne s4, t0, .Lemit_call_fail  # if s4 != t0 goto .Lemit_call_fail
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_call_fail  # if a0 == zero goto .Lemit_call_fail
    sw a1, 12(sp)  # u32 a1 -> 12(sp)
    lw t0, 12(sp)  # i32 12(sp) -> t0
    sub t0, t0, s3  # t0 - s3 -> t0
    li t1, 0xfff  # 0xfff -> t1
    and t2, t0, t1  # t0 & t1 -> t2
    sw t2, 8(sp)  # u32 t2 -> 8(sp)
    li t3, 0xfffff000  # 0xfffff000 -> t3
    and t4, t0, t3  # t0 & t3 -> t4
    li t5, 0x800  # 0x800 -> t5
    bltu t2, t5, .Lemit_call_hi_ready  # if t2 <u t5 goto .Lemit_call_hi_ready
    li t5, 0x1000  # 0x1000 -> t5
    add t4, t4, t5  # t4 + t5 -> t4
.Lemit_call_hi_ready:
    lw t1, 20(sp)  # i32 20(sp) -> t1
    slli t1, t1, 7  # t1 << 7 -> t1
    srli t5, t4, 12  # t4 >> 12 -> t5
    slli t5, t5, 12  # t5 << 12 -> t5
    li t6, RV_MATCH_AUIPC  # RV_MATCH_AUIPC -> t6
    or t6, t6, t1  # t6 | t1 -> t6
    or a0, t6, t5  # t6 | t5 -> a0
    call emit_word  # call emit_word
    beq a0, zero, .Lemit_call_fail  # if a0 == zero goto .Lemit_call_fail
    lw t1, 24(sp)  # i32 24(sp) -> t1
    slli t1, t1, 7  # t1 << 7 -> t1
    lw t3, 16(sp)  # i32 16(sp) -> t3
    slli t3, t3, 15  # t3 << 15 -> t3
    lw t2, 8(sp)  # i32 8(sp) -> t2
    li t4, 0xfff  # 0xfff -> t4
    and t2, t2, t4  # t2 & t4 -> t2
    slli t2, t2, 20  # t2 << 20 -> t2
    li t0, RV_MATCH_JALR  # RV_MATCH_JALR -> t0
    or t0, t0, t1  # t0 | t1 -> t0
    or t0, t0, t3  # t0 | t3 -> t0
    or a0, t0, t2  # t0 | t2 -> a0
    call emit_word  # call emit_word
    j .Lemit_call_done  # goto .Lemit_call_done
.Lemit_call_fail:
    li a0, 0  # 0 -> a0
.Lemit_call_done:
    ld ra, 40(sp)  # u64 40(sp) -> ra
    addi sp, sp, 48  # sp += 48
    ret  # return

emit_j_with_rd:
    srli t3, t2, 20  # t2 >> 20 -> t3
    andi t3, t3, 1  # t3 & 1 -> t3
    slli t3, t3, 31  # t3 << 31 -> t3
    srli t4, t2, 1  # t2 >> 1 -> t4
    andi t4, t4, 0x3ff  # t4 & 0x3ff -> t4
    slli t4, t4, 21  # t4 << 21 -> t4
    srli t5, t2, 11  # t2 >> 11 -> t5
    andi t5, t5, 1  # t5 & 1 -> t5
    slli t5, t5, 20  # t5 << 20 -> t5
    srli t6, t2, 12  # t2 >> 12 -> t6
    andi t6, t6, 0xff  # t6 & 0xff -> t6
    slli t6, t6, 12  # t6 << 12 -> t6
    slli t1, t1, 7  # t1 << 7 -> t1
    or t0, t1, t3  # t1 | t3 -> t0
    or t0, t0, t4  # t0 | t4 -> t0
    or t0, t0, t5  # t0 | t5 -> t0
    or t0, t0, t6  # t0 | t6 -> t0
    li t1, RV_MATCH_JAL  # RV_MATCH_JAL -> t1
    or a0, t0, t1  # t0 | t1 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_zero_left_r:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 8(sp)  # u32 a1 -> 8(sp)
    li t0, 0  # 0 -> t0
    sw t0, 4(sp)  # u32 t0 -> 4(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    lw t3, 8(sp)  # i32 8(sp) -> t3
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 15  # t2 << 15 -> t2
    slli t3, t3, 20  # t3 << 20 -> t3
    or t0, s6, t1  # s6 | t1 -> t0
    or t0, t0, t2  # t0 | t2 -> t0
    or a0, t0, t3  # t0 | t3 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_zero_right_r:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li t0, 0  # 0 -> t0
    sw t0, 8(sp)  # u32 t0 -> 8(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    lw t3, 8(sp)  # i32 8(sp) -> t3
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 15  # t2 << 15 -> t2
    slli t3, t3, 20  # t3 << 20 -> t3
    or t0, s6, t1  # s6 | t1 -> t0
    or t0, t0, t2  # t0 | t2 -> t0
    or a0, t0, t3  # t0 | t3 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_not:
    li a1, RV_MATCH_XORI  # RV_MATCH_XORI -> a1
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li t0, -1  # -1 -> t0
    sw t0, 8(sp)  # u32 t0 -> 8(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    lw t3, 8(sp)  # i32 8(sp) -> t3
    li t4, 0xfff  # 0xfff -> t4
    and t3, t3, t4  # t3 & t4 -> t3
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 15  # t2 << 15 -> t2
    slli t3, t3, 20  # t3 << 20 -> t3
    or t0, s6, t1  # s6 | t1 -> t0
    or t0, t0, t2  # t0 | t2 -> t0
    or a0, t0, t3  # t0 | t3 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_seqz:
    li a1, RV_MATCH_SLTIU  # RV_MATCH_SLTIU -> a1
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 3  # 3 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    mv s6, a1  # a1 -> s6
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    call parse_register  # call parse_register
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    li t0, 1  # 1 -> t0
    sw t0, 8(sp)  # u32 t0 -> 8(sp)
    lw t1, 0(sp)  # i32 0(sp) -> t1
    lw t2, 4(sp)  # i32 4(sp) -> t2
    lw t3, 8(sp)  # i32 8(sp) -> t3
    li t4, 0xfff  # 0xfff -> t4
    and t3, t3, t4  # t3 & t4 -> t3
    slli t1, t1, 7  # t1 << 7 -> t1
    slli t2, t2, 15  # t2 << 15 -> t2
    slli t3, t3, 20  # t3 << 20 -> t3
    or t0, s6, t1  # s6 | t1 -> t0
    or t0, t0, t2  # t0 | t2 -> t0
    or a0, t0, t3  # t0 | t3 -> a0
    call emit_word  # call emit_word
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

.Lemit_fail:
    li a0, 0  # 0 -> a0
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_dot_byte:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 2  # 2 -> t0
    bltu s4, t0, .Lemit_fail  # if s4 <u t0 goto .Lemit_fail
    li t1, 1  # 1 -> t1
    sw t1, 16(sp)  # u32 t1 -> 16(sp)
.Lemit_dot_byte_loop:
    lw t1, 16(sp)  # i32 16(sp) -> t1
    bgeu t1, s4, .Lemit_dot_byte_done  # if t1 >=u s4 goto .Lemit_dot_byte_done
    mv a0, t1  # t1 -> a0
    call token_ptr  # call token_ptr
    call parse_value  # call parse_value
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    andi a0, a1, 0xff  # a1 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    lw t1, 16(sp)  # i32 16(sp) -> t1
    addi t1, t1, 1  # t1 + 1 -> t1
    sw t1, 16(sp)  # u32 t1 -> 16(sp)
    j .Lemit_dot_byte_loop  # goto .Lemit_dot_byte_loop
.Lemit_dot_byte_done:
    li a0, 1  # 1 -> a0
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_dot_word:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 2  # 2 -> t0
    bltu s4, t0, .Lemit_fail  # if s4 <u t0 goto .Lemit_fail
    li t0, 2  # 2 -> t0
    beq s4, t0, .Lemit_dot_word_single  # if s4 == t0 goto .Lemit_dot_word_single
    li t0, 4  # 4 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    li a0, 2  # 2 -> a0
    call token_ptr  # call token_ptr
    la a1, str_minus  # addr str_minus -> a1
    call strings_equal  # call strings_equal
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    sw a1, 0(sp)  # u32 a1 -> 0(sp)
    li a0, 3  # 3 -> a0
    call token_ptr  # call token_ptr
    la a1, str_dot  # addr str_dot -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lemit_dot_word_here  # if a0 != zero goto .Lemit_dot_word_here
    li a0, 3  # 3 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    lw t0, 0(sp)  # i32 0(sp) -> t0
    sub a0, t0, a1  # t0 - a1 -> a0
    call emit_word  # call emit_word
    j .Lemit_dot_word_done  # goto .Lemit_dot_word_done
.Lemit_dot_word_here:
    lw t0, 0(sp)  # i32 0(sp) -> t0
    sub a0, t0, s3  # t0 - s3 -> a0
    call emit_word  # call emit_word
    j .Lemit_dot_word_done  # goto .Lemit_dot_word_done
.Lemit_dot_word_single:
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_value  # call parse_value
    bne a0, zero, .Lemit_dot_word_emit  # if a0 != zero goto .Lemit_dot_word_emit
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
.Lemit_dot_word_emit:
    mv a0, a1  # a1 -> a0
    call emit_word  # call emit_word
.Lemit_dot_word_done:
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_dot_dword:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 2  # 2 -> t0
    bltu s4, t0, .Lemit_fail  # if s4 <u t0 goto .Lemit_fail
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call parse_value  # call parse_value
    bne a0, zero, .Lemit_dot_dword_emit  # if a0 != zero goto .Lemit_dot_dword_emit
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    call lookup_label  # call lookup_label
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
.Lemit_dot_dword_emit:
    mv a0, a1  # a1 -> a0
    call emit_dword  # call emit_dword
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_dot_string:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    li t0, 2  # 2 -> t0
    bne s4, t0, .Lemit_fail  # if s4 != t0 goto .Lemit_fail
    li a0, 1  # 1 -> a0
    call token_ptr  # call token_ptr
    mv t1, a0  # a0 -> t1
    sd t1, 16(sp)  # u64 t1 -> 16(sp)
.Lemit_dot_string_loop:
    ld t1, 16(sp)  # u64 16(sp) -> t1
    lbu t0, 0(t1)  # u8 0(t1) -> t0
    beq t0, zero, .Lemit_dot_string_done  # if t0 == zero goto .Lemit_dot_string_done
    mv a0, t0  # t0 -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    ld t1, 16(sp)  # u64 16(sp) -> t1
    addi t1, t1, 1  # t1 + 1 -> t1
    sd t1, 16(sp)  # u64 t1 -> 16(sp)
    j .Lemit_dot_string_loop  # goto .Lemit_dot_string_loop
.Lemit_dot_string_done:
    li a0, 0  # 0 -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    li a0, 1  # 1 -> a0
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_dot_align:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    andi t0, s3, 3  # s3 & 3 -> t0
    beq t0, zero, .Lemit_dot_align_done  # if t0 == zero goto .Lemit_dot_align_done
    li t1, 4  # 4 -> t1
    sub t1, t1, t0  # t1 - t0 -> t1
    sw t1, 16(sp)  # u32 t1 -> 16(sp)
.Lemit_dot_align_loop:
    lw t1, 16(sp)  # i32 16(sp) -> t1
    beq t1, zero, .Lemit_dot_align_done  # if t1 == zero goto .Lemit_dot_align_done
    li a0, 0  # 0 -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_fail  # if a0 == zero goto .Lemit_fail
    lw t1, 16(sp)  # i32 16(sp) -> t1
    addi t1, t1, -1  # t1 + -1 -> t1
    sw t1, 16(sp)  # u32 t1 -> 16(sp)
    j .Lemit_dot_align_loop  # goto .Lemit_dot_align_loop
.Lemit_dot_align_done:
    li a0, 1  # 1 -> a0
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

emit_word:
    addi sp, sp, -16  # sp += -16
    sd ra, 8(sp)  # u64 ra -> 8(sp)
    sd a0, 0(sp)  # u64 a0 -> 0(sp)
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_word_fail  # if a0 == zero goto .Lemit_word_fail
    ld t0, 0(sp)  # u64 0(sp) -> t0
    srli a0, t0, 8  # t0 >> 8 -> a0
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_word_fail  # if a0 == zero goto .Lemit_word_fail
    ld t0, 0(sp)  # u64 0(sp) -> t0
    srli a0, t0, 16  # t0 >> 16 -> a0
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_word_fail  # if a0 == zero goto .Lemit_word_fail
    ld t0, 0(sp)  # u64 0(sp) -> t0
    srli a0, t0, 24  # t0 >> 24 -> a0
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return
.Lemit_word_fail:
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return

emit_dword:
    addi sp, sp, -16  # sp += -16
    sd ra, 8(sp)  # u64 ra -> 8(sp)
    sd a0, 0(sp)  # u64 a0 -> 0(sp)
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_dword_fail  # if a0 == zero goto .Lemit_dword_fail
    ld t0, 0(sp)  # u64 0(sp) -> t0
    srli a0, t0, 8  # t0 >> 8 -> a0
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_dword_fail  # if a0 == zero goto .Lemit_dword_fail
    ld t0, 0(sp)  # u64 0(sp) -> t0
    srli a0, t0, 16  # t0 >> 16 -> a0
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_dword_fail  # if a0 == zero goto .Lemit_dword_fail
    ld t0, 0(sp)  # u64 0(sp) -> t0
    srli a0, t0, 24  # t0 >> 24 -> a0
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_dword_fail  # if a0 == zero goto .Lemit_dword_fail
    ld t0, 0(sp)  # u64 0(sp) -> t0
    srli a0, t0, 32  # t0 >> 32 -> a0
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_dword_fail  # if a0 == zero goto .Lemit_dword_fail
    ld t0, 0(sp)  # u64 0(sp) -> t0
    srli a0, t0, 40  # t0 >> 40 -> a0
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_dword_fail  # if a0 == zero goto .Lemit_dword_fail
    ld t0, 0(sp)  # u64 0(sp) -> t0
    srli a0, t0, 48  # t0 >> 48 -> a0
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    beq a0, zero, .Lemit_dword_fail  # if a0 == zero goto .Lemit_dword_fail
    ld t0, 0(sp)  # u64 0(sp) -> t0
    srli a0, t0, 56  # t0 >> 56 -> a0
    andi a0, a0, 0xff  # a0 & 0xff -> a0
    call emit_byte  # call emit_byte
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return
.Lemit_dword_fail:
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return

emit_byte:
    addi sp, sp, -16  # sp += -16
    sd ra, 8(sp)  # u64 ra -> 8(sp)
    sb a0, 0(sp)  # u8 a0 -> 0(sp)
    ld a5, 8(s1)  # u64 8(s1) -> a5
    mv a0, s1  # s1 -> a0
    lbu a1, 0(sp)  # u8 0(sp) -> a1
    jalr a5  # goto *a5
    addi s3, s3, 1  # s3 + 1 -> s3
    li a0, 1  # 1 -> a0
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return

add_label:
    addi sp, sp, -48  # sp += -48
    sd ra, 40(sp)  # u64 ra -> 40(sp)
    sd a0, 32(sp)  # u64 a0 -> 32(sp)
    sw a1, 28(sp)  # u32 a1 -> 28(sp)
    la t0, label_count_addr  # addr label_count_addr -> t0
    ld t0, 0(t0)  # u64 0(t0) -> t0
    lw t1, 0(t0)  # i32 0(t0) -> t1
    li t2, LABEL_MAX  # LABEL_MAX -> t2
    bgeu t1, t2, .Ladd_label_fail  # if t1 >=u t2 goto .Ladd_label_fail
    li t2, LABEL_ENTRY_SIZE  # LABEL_ENTRY_SIZE -> t2
    mul t3, t1, t2  # t1 * t2 -> t3
    la t4, labels_addr  # addr labels_addr -> t4
    ld t4, 0(t4)  # u64 0(t4) -> t4
    add t4, t4, t3  # t4 + t3 -> t4
    sd t0, 16(sp)  # u64 t0 -> 16(sp)
    sw t1, 12(sp)  # u32 t1 -> 12(sp)
    sd t4, 0(sp)  # u64 t4 -> 0(sp)
    ld a1, 32(sp)  # u64 32(sp) -> a1
    mv a0, t4  # t4 -> a0
    call copy_name  # call copy_name
    lw t1, 12(sp)  # i32 12(sp) -> t1
    ld t0, 16(sp)  # u64 16(sp) -> t0
    ld t4, 0(sp)  # u64 0(sp) -> t4
    lw t5, 28(sp)  # i32 28(sp) -> t5
    sw t5, 64(t4)  # u32 t5 -> 64(t4)
    addi t1, t1, 1  # t1 + 1 -> t1
    sw t1, 0(t0)  # u32 t1 -> 0(t0)
    li a0, 1  # 1 -> a0
    j .Ladd_label_done  # goto .Ladd_label_done
.Ladd_label_fail:
    li a0, 0  # 0 -> a0
.Ladd_label_done:
    ld ra, 40(sp)  # u64 40(sp) -> ra
    addi sp, sp, 48  # sp += 48
    ret  # return

lookup_label:
    addi sp, sp, -48  # sp += -48
    sd ra, 40(sp)  # u64 ra -> 40(sp)
    sd a0, 32(sp)  # u64 a0 -> 32(sp)
    la t0, label_count_addr  # addr label_count_addr -> t0
    ld t0, 0(t0)  # u64 0(t0) -> t0
    lw t1, 0(t0)  # i32 0(t0) -> t1
    la t2, labels_addr  # addr labels_addr -> t2
    ld t2, 0(t2)  # u64 0(t2) -> t2
    li t3, 0  # 0 -> t3
.Llookup_loop:
    bgeu t3, t1, .Llookup_fail  # if t3 >=u t1 goto .Llookup_fail
    sd t1, 24(sp)  # u64 t1 -> 24(sp)
    sd t2, 16(sp)  # u64 t2 -> 16(sp)
    sd t3, 8(sp)  # u64 t3 -> 8(sp)
    ld t4, 32(sp)  # u64 32(sp) -> t4
    mv a0, t2  # t2 -> a0
    mv a1, t4  # t4 -> a1
    call strings_equal  # call strings_equal
    ld t1, 24(sp)  # u64 24(sp) -> t1
    ld t2, 16(sp)  # u64 16(sp) -> t2
    ld t3, 8(sp)  # u64 8(sp) -> t3
    bne a0, zero, .Llookup_hit  # if a0 != zero goto .Llookup_hit
    addi t2, t2, LABEL_ENTRY_SIZE  # t2 + LABEL_ENTRY_SIZE -> t2
    addi t3, t3, 1  # t3 + 1 -> t3
    j .Llookup_loop  # goto .Llookup_loop
.Llookup_hit:
    lwu a1, 64(t2)  # u32 64(t2) -> a1
    li a0, 1  # 1 -> a0
    ld ra, 40(sp)  # u64 40(sp) -> ra
    addi sp, sp, 48  # sp += 48
    ret  # return
.Llookup_fail:
    li a0, 0  # 0 -> a0
    ld ra, 40(sp)  # u64 40(sp) -> ra
    addi sp, sp, 48  # sp += 48
    ret  # return

add_define:
    addi sp, sp, -48  # sp += -48
    sd ra, 40(sp)  # u64 ra -> 40(sp)
    sd a0, 32(sp)  # u64 a0 -> 32(sp)
    sw a1, 28(sp)  # u32 a1 -> 28(sp)
    la t0, define_count_addr  # addr define_count_addr -> t0
    ld t0, 0(t0)  # u64 0(t0) -> t0
    lw t1, 0(t0)  # i32 0(t0) -> t1
    li t2, DEFINE_MAX  # DEFINE_MAX -> t2
    bgeu t1, t2, .Ladd_define_fail  # if t1 >=u t2 goto .Ladd_define_fail
    li t2, DEFINE_ENTRY_SIZE  # DEFINE_ENTRY_SIZE -> t2
    mul t3, t1, t2  # t1 * t2 -> t3
    la t4, defines_addr  # addr defines_addr -> t4
    ld t4, 0(t4)  # u64 0(t4) -> t4
    add t4, t4, t3  # t4 + t3 -> t4
    sd t0, 16(sp)  # u64 t0 -> 16(sp)
    sw t1, 12(sp)  # u32 t1 -> 12(sp)
    sd t4, 0(sp)  # u64 t4 -> 0(sp)
    ld a1, 32(sp)  # u64 32(sp) -> a1
    mv a0, t4  # t4 -> a0
    call copy_name  # call copy_name
    lw t1, 12(sp)  # i32 12(sp) -> t1
    ld t0, 16(sp)  # u64 16(sp) -> t0
    ld t4, 0(sp)  # u64 0(sp) -> t4
    lw t5, 28(sp)  # i32 28(sp) -> t5
    sw t5, 64(t4)  # u32 t5 -> 64(t4)
    addi t1, t1, 1  # t1 + 1 -> t1
    sw t1, 0(t0)  # u32 t1 -> 0(t0)
    li a0, 1  # 1 -> a0
    j .Ladd_define_done  # goto .Ladd_define_done
.Ladd_define_fail:
    li a0, 0  # 0 -> a0
.Ladd_define_done:
    ld ra, 40(sp)  # u64 40(sp) -> ra
    addi sp, sp, 48  # sp += 48
    ret  # return

lookup_define:
    addi sp, sp, -48  # sp += -48
    sd ra, 40(sp)  # u64 ra -> 40(sp)
    sd a0, 32(sp)  # u64 a0 -> 32(sp)
    la t0, define_count_addr  # addr define_count_addr -> t0
    ld t0, 0(t0)  # u64 0(t0) -> t0
    lw t1, 0(t0)  # i32 0(t0) -> t1
    la t2, defines_addr  # addr defines_addr -> t2
    ld t2, 0(t2)  # u64 0(t2) -> t2
    li t3, 0  # 0 -> t3
.Llookup_define_loop:
    bgeu t3, t1, .Llookup_define_fail  # if t3 >=u t1 goto .Llookup_define_fail
    sd t1, 24(sp)  # u64 t1 -> 24(sp)
    sd t2, 16(sp)  # u64 t2 -> 16(sp)
    sd t3, 8(sp)  # u64 t3 -> 8(sp)
    ld t4, 32(sp)  # u64 32(sp) -> t4
    mv a0, t2  # t2 -> a0
    mv a1, t4  # t4 -> a1
    call strings_equal  # call strings_equal
    ld t1, 24(sp)  # u64 24(sp) -> t1
    ld t2, 16(sp)  # u64 16(sp) -> t2
    ld t3, 8(sp)  # u64 8(sp) -> t3
    bne a0, zero, .Llookup_define_hit  # if a0 != zero goto .Llookup_define_hit
    addi t2, t2, DEFINE_ENTRY_SIZE  # t2 + DEFINE_ENTRY_SIZE -> t2
    addi t3, t3, 1  # t3 + 1 -> t3
    j .Llookup_define_loop  # goto .Llookup_define_loop
.Llookup_define_hit:
    lwu a1, 64(t2)  # u32 64(t2) -> a1
    li a0, 1  # 1 -> a0
    ld ra, 40(sp)  # u64 40(sp) -> ra
    addi sp, sp, 48  # sp += 48
    ret  # return
.Llookup_define_fail:
    li a0, 0  # 0 -> a0
    ld ra, 40(sp)  # u64 40(sp) -> ra
    addi sp, sp, 48  # sp += 48
    ret  # return

copy_name:
    li t0, LABEL_NAME_MAX - 1  # LABEL_NAME_MAX - 1 -> t0
.Lcopy_name_loop:
    beq t0, zero, .Lcopy_name_end  # if t0 == zero goto .Lcopy_name_end
    lbu t1, 0(a1)  # u8 0(a1) -> t1
    sb t1, 0(a0)  # u8 t1 -> 0(a0)
    beq t1, zero, .Lcopy_name_done  # if t1 == zero goto .Lcopy_name_done
    addi a0, a0, 1  # a0 + 1 -> a0
    addi a1, a1, 1  # a1 + 1 -> a1
    addi t0, t0, -1  # t0 + -1 -> t0
    j .Lcopy_name_loop  # goto .Lcopy_name_loop
.Lcopy_name_end:
    sb zero, 0(a0)  # u8 zero -> 0(a0)
.Lcopy_name_done:
    ret  # return

strings_equal:
.Lstrcmp_loop:
    lbu t0, 0(a0)  # u8 0(a0) -> t0
    lbu t1, 0(a1)  # u8 0(a1) -> t1
    bne t0, t1, .Lstrcmp_no  # if t0 != t1 goto .Lstrcmp_no
    beq t0, zero, .Lstrcmp_yes  # if t0 == zero goto .Lstrcmp_yes
    addi a0, a0, 1  # a0 + 1 -> a0
    addi a1, a1, 1  # a1 + 1 -> a1
    j .Lstrcmp_loop  # goto .Lstrcmp_loop
.Lstrcmp_yes:
    li a0, 1  # 1 -> a0
    ret  # return
.Lstrcmp_no:
    li a0, 0  # 0 -> a0
    ret  # return

string_length:
    li t0, 0  # 0 -> t0
.Lstrlen_loop:
    lbu t1, 0(a0)  # u8 0(a0) -> t1
    beq t1, zero, .Lstrlen_done  # if t1 == zero goto .Lstrlen_done
    addi a0, a0, 1  # a0 + 1 -> a0
    addi t0, t0, 1  # t0 + 1 -> t0
    j .Lstrlen_loop  # goto .Lstrlen_loop
.Lstrlen_done:
    mv a0, t0  # t0 -> a0
    ret  # return

parse_value:
    addi sp, sp, -16  # sp += -16
    sd ra, 8(sp)  # u64 ra -> 8(sp)
    sd a0, 0(sp)  # u64 a0 -> 0(sp)
    call parse_number  # call parse_number
    bne a0, zero, .Lparse_value_done  # if a0 != zero goto .Lparse_value_done
    ld a0, 0(sp)  # u64 0(sp) -> a0
    call parse_char_literal  # call parse_char_literal
    bne a0, zero, .Lparse_value_done  # if a0 != zero goto .Lparse_value_done
    ld a0, 0(sp)  # u64 0(sp) -> a0
    call lookup_define  # call lookup_define
.Lparse_value_done:
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return

parse_char_literal:
    li t5, 1  # 1 -> t5
    lbu t0, 0(a0)  # u8 0(a0) -> t0
    li t1, '-'  # '-' -> t1
    bne t0, t1, .Lchar_no_neg  # if t0 != t1 goto .Lchar_no_neg
    li t5, -1  # -1 -> t5
    addi a0, a0, 1  # a0 + 1 -> a0
    lbu t0, 0(a0)  # u8 0(a0) -> t0
.Lchar_no_neg:
    li t1, '\''  # '\'' -> t1
    bne t0, t1, .Lchar_fail  # if t0 != t1 goto .Lchar_fail
    lbu t2, 1(a0)  # u8 1(a0) -> t2
    li t3, '\\'  # '\\' -> t3
    beq t2, t3, .Lchar_escape  # if t2 == t3 goto .Lchar_escape
    beq t2, zero, .Lchar_fail  # if t2 == zero goto .Lchar_fail
    lbu t3, 2(a0)  # u8 2(a0) -> t3
    li t4, '\''  # '\'' -> t4
    bne t3, t4, .Lchar_fail  # if t3 != t4 goto .Lchar_fail
    lbu t3, 3(a0)  # u8 3(a0) -> t3
    bne t3, zero, .Lchar_fail  # if t3 != zero goto .Lchar_fail
    mv a1, t2  # t2 -> a1
    j .Lchar_done  # goto .Lchar_done
.Lchar_escape:
    lbu t2, 2(a0)  # u8 2(a0) -> t2
    lbu t3, 3(a0)  # u8 3(a0) -> t3
    li t4, '\''  # '\'' -> t4
    bne t3, t4, .Lchar_fail  # if t3 != t4 goto .Lchar_fail
    lbu t3, 4(a0)  # u8 4(a0) -> t3
    bne t3, zero, .Lchar_fail  # if t3 != zero goto .Lchar_fail
    li t3, 't'  # 't' -> t3
    beq t2, t3, .Lchar_tab  # if t2 == t3 goto .Lchar_tab
    li t3, 'n'  # 'n' -> t3
    beq t2, t3, .Lchar_nl  # if t2 == t3 goto .Lchar_nl
    li t3, '0'  # '0' -> t3
    beq t2, t3, .Lchar_zero  # if t2 == t3 goto .Lchar_zero
    li t3, '\\'  # '\\' -> t3
    beq t2, t3, .Lchar_backslash  # if t2 == t3 goto .Lchar_backslash
    li t3, '\''  # '\'' -> t3
    beq t2, t3, .Lchar_quote  # if t2 == t3 goto .Lchar_quote
    li t3, '"'  # '"' -> t3
    beq t2, t3, .Lchar_dquote  # if t2 == t3 goto .Lchar_dquote
    j .Lchar_fail  # goto .Lchar_fail
.Lchar_tab:
    li a1, 9  # 9 -> a1
    j .Lchar_done  # goto .Lchar_done
.Lchar_nl:
    li a1, 10  # 10 -> a1
    j .Lchar_done  # goto .Lchar_done
.Lchar_zero:
    li a1, 0  # 0 -> a1
    j .Lchar_done  # goto .Lchar_done
.Lchar_backslash:
    li a1, '\\'  # '\\' -> a1
    j .Lchar_done  # goto .Lchar_done
.Lchar_quote:
    li a1, '\''  # '\'' -> a1
    j .Lchar_done  # goto .Lchar_done
.Lchar_dquote:
    li a1, '"'  # '"' -> a1
    j .Lchar_done  # goto .Lchar_done
.Lchar_done:
    blt t5, zero, .Lchar_negate  # if t5 < zero goto .Lchar_negate
    li a0, 1  # 1 -> a0
    ret  # return
.Lchar_negate:
    neg a1, a1  # -a1 -> a1
    li a0, 1  # 1 -> a0
    ret  # return
.Lchar_fail:
    li a0, 0  # 0 -> a0
    ret  # return

eval_expr_range:
    addi sp, sp, -32  # sp += -32
    sd ra, 24(sp)  # u64 ra -> 24(sp)
    sw a0, 16(sp)  # u32 a0 -> 16(sp)
    sw a1, 12(sp)  # u32 a1 -> 12(sp)
    call token_ptr  # call token_ptr
    call parse_value  # call parse_value
    beq a0, zero, .Leval_expr_fail  # if a0 == zero goto .Leval_expr_fail
    sw a1, 8(sp)  # u32 a1 -> 8(sp)
    lw t0, 12(sp)  # i32 12(sp) -> t0
    li t1, 1  # 1 -> t1
    beq t0, t1, .Leval_expr_one  # if t0 == t1 goto .Leval_expr_one
    li t1, 3  # 3 -> t1
    bne t0, t1, .Leval_expr_fail  # if t0 != t1 goto .Leval_expr_fail
    lw t0, 16(sp)  # i32 16(sp) -> t0
    addi a0, t0, 1  # t0 + 1 -> a0
    call token_ptr  # call token_ptr
    mv t6, a0  # a0 -> t6
    lw t0, 16(sp)  # i32 16(sp) -> t0
    addi a0, t0, 2  # t0 + 2 -> a0
    call token_ptr  # call token_ptr
    call parse_value  # call parse_value
    beq a0, zero, .Leval_expr_fail  # if a0 == zero goto .Leval_expr_fail
    sw a1, 4(sp)  # u32 a1 -> 4(sp)
    mv a0, t6  # t6 -> a0
    la a1, str_plus  # addr str_plus -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Leval_expr_add  # if a0 != zero goto .Leval_expr_add
    mv a0, t6  # t6 -> a0
    la a1, str_minus  # addr str_minus -> a1
    call strings_equal  # call strings_equal
    beq a0, zero, .Leval_expr_fail  # if a0 == zero goto .Leval_expr_fail
    lw t0, 8(sp)  # i32 8(sp) -> t0
    lw t1, 4(sp)  # i32 4(sp) -> t1
    sub a1, t0, t1  # t0 - t1 -> a1
    li a0, 1  # 1 -> a0
    j .Leval_expr_done  # goto .Leval_expr_done
.Leval_expr_add:
    lw t0, 8(sp)  # i32 8(sp) -> t0
    lw t1, 4(sp)  # i32 4(sp) -> t1
    add a1, t0, t1  # t0 + t1 -> a1
    li a0, 1  # 1 -> a0
    j .Leval_expr_done  # goto .Leval_expr_done
.Leval_expr_one:
    lw a1, 8(sp)  # i32 8(sp) -> a1
    li a0, 1  # 1 -> a0
    j .Leval_expr_done  # goto .Leval_expr_done
.Leval_expr_fail:
    li a0, 0  # 0 -> a0
.Leval_expr_done:
    ld ra, 24(sp)  # u64 24(sp) -> ra
    addi sp, sp, 32  # sp += 32
    ret  # return

parse_register:
    addi sp, sp, -16  # sp += -16
    sd ra, 8(sp)  # u64 ra -> 8(sp)
    mv t6, a0  # a0 -> t6
    lbu t0, 0(a0)  # u8 0(a0) -> t0
    li t1, 'x'  # 'x' -> t1
    beq t0, t1, .Lreg_x  # if t0 == t1 goto .Lreg_x
    la a1, reg_zero  # addr reg_zero -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lreg_zero  # if a0 != zero goto .Lreg_zero
    mv a0, t6  # t6 -> a0
    la a1, reg_ra  # addr reg_ra -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lreg_ra  # if a0 != zero goto .Lreg_ra
    mv a0, t6  # t6 -> a0
    la a1, reg_sp  # addr reg_sp -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lreg_sp  # if a0 != zero goto .Lreg_sp
    mv a0, t6  # t6 -> a0
    la a1, reg_gp  # addr reg_gp -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lreg_gp  # if a0 != zero goto .Lreg_gp
    mv a0, t6  # t6 -> a0
    la a1, reg_tp  # addr reg_tp -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lreg_tp  # if a0 != zero goto .Lreg_tp
    mv a0, t6  # t6 -> a0
    la a1, reg_fp  # addr reg_fp -> a1
    call strings_equal  # call strings_equal
    bne a0, zero, .Lreg_fp  # if a0 != zero goto .Lreg_fp
    mv a0, t6  # t6 -> a0
    lbu t0, 0(a0)  # u8 0(a0) -> t0
    li t1, 't'  # 't' -> t1
    beq t0, t1, .Lreg_t  # if t0 == t1 goto .Lreg_t
    li t1, 'a'  # 'a' -> t1
    beq t0, t1, .Lreg_a  # if t0 == t1 goto .Lreg_a
    li t1, 's'  # 's' -> t1
    beq t0, t1, .Lreg_s  # if t0 == t1 goto .Lreg_s
    j .Lreg_fail  # goto .Lreg_fail
.Lreg_x:
    addi a0, a0, 1  # a0 + 1 -> a0
    call parse_number  # call parse_number
    beq a0, zero, .Lreg_fail  # if a0 == zero goto .Lreg_fail
    li t0, 32  # 32 -> t0
    bgeu a1, t0, .Lreg_fail  # if a1 >=u t0 goto .Lreg_fail
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_zero:
    li a1, 0  # 0 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_ra:
    li a1, 1  # 1 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_sp:
    li a1, 2  # 2 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_gp:
    li a1, 3  # 3 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_tp:
    li a1, 4  # 4 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_fp:
    li a1, 8  # 8 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_t:
    lbu t0, 1(a0)  # u8 1(a0) -> t0
    addi t0, t0, -'0'  # t0 + -'0' -> t0
    li t1, 7  # 7 -> t1
    bgeu t0, t1, .Lreg_fail  # if t0 >=u t1 goto .Lreg_fail
    lbu t1, 2(a0)  # u8 2(a0) -> t1
    bne t1, zero, .Lreg_fail  # if t1 != zero goto .Lreg_fail
    li t1, 3  # 3 -> t1
    bltu t0, t1, .Lreg_t_low  # if t0 <u t1 goto .Lreg_t_low
    addi a1, t0, 25  # t0 + 25 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_t_low:
    addi a1, t0, 5  # t0 + 5 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_a:
    lbu t0, 1(a0)  # u8 1(a0) -> t0
    addi t0, t0, -'0'  # t0 + -'0' -> t0
    li t1, 8  # 8 -> t1
    bgeu t0, t1, .Lreg_fail  # if t0 >=u t1 goto .Lreg_fail
    lbu t1, 2(a0)  # u8 2(a0) -> t1
    bne t1, zero, .Lreg_fail  # if t1 != zero goto .Lreg_fail
    addi a1, t0, 10  # t0 + 10 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_s:
    addi a0, a0, 1  # a0 + 1 -> a0
    call parse_number  # call parse_number
    beq a0, zero, .Lreg_fail  # if a0 == zero goto .Lreg_fail
    li t0, 2  # 2 -> t0
    bltu a1, t0, .Lreg_s_low  # if a1 <u t0 goto .Lreg_s_low
    li t0, 12  # 12 -> t0
    bgeu a1, t0, .Lreg_fail  # if a1 >=u t0 goto .Lreg_fail
    addi a1, a1, 16  # a1 + 16 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_s_low:
    addi a1, a1, 8  # a1 + 8 -> a1
    li a0, 1  # 1 -> a0
    j .Lparse_register_done  # goto .Lparse_register_done
.Lreg_fail:
    li a0, 0  # 0 -> a0
 .Lparse_register_done:
    ld ra, 8(sp)  # u64 8(sp) -> ra
    addi sp, sp, 16  # sp += 16
    ret  # return

parse_number:
    li t0, 0  # 0 -> t0
    li t1, 1  # 1 -> t1
    lbu t2, 0(a0)  # u8 0(a0) -> t2
    li t3, '-'  # '-' -> t3
    bne t2, t3, .Lpn_prefix_check  # if t2 != t3 goto .Lpn_prefix_check
    li t1, -1  # -1 -> t1
    addi a0, a0, 1  # a0 + 1 -> a0
.Lpn_prefix_check:
    lbu t2, 0(a0)  # u8 0(a0) -> t2
    li t3, '0'  # '0' -> t3
    bne t2, t3, .Lpn_dec_loop  # if t2 != t3 goto .Lpn_dec_loop
    lbu t4, 1(a0)  # u8 1(a0) -> t4
    li t5, 'x'  # 'x' -> t5
    beq t4, t5, .Lpn_hex_start  # if t4 == t5 goto .Lpn_hex_start
    li t5, 'X'  # 'X' -> t5
    beq t4, t5, .Lpn_hex_start  # if t4 == t5 goto .Lpn_hex_start
.Lpn_dec_loop:
.Lpn_loop_dec_body:
    lbu t2, 0(a0)  # u8 0(a0) -> t2
    beq t2, zero, .Lpn_done  # if t2 == zero goto .Lpn_done
    addi t2, t2, -'0'  # t2 + -'0' -> t2
    li t3, 10  # 10 -> t3
    bgeu t2, t3, .Lpn_fail  # if t2 >=u t3 goto .Lpn_fail
    li t3, 10  # 10 -> t3
    mul t0, t0, t3  # t0 * t3 -> t0
    add t0, t0, t2  # t0 + t2 -> t0
    addi a0, a0, 1  # a0 + 1 -> a0
    j .Lpn_loop_dec_body  # goto .Lpn_loop_dec_body
.Lpn_hex_start:
    addi a0, a0, 2  # a0 + 2 -> a0
.Lpn_hex_loop:
    lbu t2, 0(a0)  # u8 0(a0) -> t2
    beq t2, zero, .Lpn_done  # if t2 == zero goto .Lpn_done
    li t3, '0'  # '0' -> t3
    bltu t2, t3, .Lpn_fail  # if t2 <u t3 goto .Lpn_fail
    li t3, '9'  # '9' -> t3
    bleu t2, t3, .Lpn_hex_digit  # if t2 <=u t3 goto .Lpn_hex_digit
    li t3, 'a'  # 'a' -> t3
    bltu t2, t3, .Lpn_hex_upper_check  # if t2 <u t3 goto .Lpn_hex_upper_check
    li t3, 'f'  # 'f' -> t3
    bleu t2, t3, .Lpn_hex_lower  # if t2 <=u t3 goto .Lpn_hex_lower
.Lpn_hex_upper_check:
    li t3, 'A'  # 'A' -> t3
    bltu t2, t3, .Lpn_fail  # if t2 <u t3 goto .Lpn_fail
    li t3, 'F'  # 'F' -> t3
    bgtu t2, t3, .Lpn_fail  # if t2 >u t3 goto .Lpn_fail
    addi t2, t2, -'A'  # t2 + -'A' -> t2
    addi t2, t2, 10  # t2 + 10 -> t2
    j .Lpn_hex_accum  # goto .Lpn_hex_accum
.Lpn_hex_lower:
    addi t2, t2, -'a'  # t2 + -'a' -> t2
    addi t2, t2, 10  # t2 + 10 -> t2
    j .Lpn_hex_accum  # goto .Lpn_hex_accum
.Lpn_hex_digit:
    addi t2, t2, -'0'  # t2 + -'0' -> t2
.Lpn_hex_accum:
    slli t0, t0, 4  # t0 << 4 -> t0
    add t0, t0, t2  # t0 + t2 -> t0
    addi a0, a0, 1  # a0 + 1 -> a0
    j .Lpn_hex_loop  # goto .Lpn_hex_loop
.Lpn_done:
    mul a1, t0, t1  # t0 * t1 -> a1
    li a0, 1  # 1 -> a0
    ret  # return
.Lpn_fail:
    li a0, 0  # 0 -> a0
    ret  # return

label_count_addr:
    .dword LABEL_COUNT_PTR
define_count_addr:
    .dword DEFINE_COUNT_PTR
fail_line_addr:
    .dword FAIL_LINE_PTR
fail_phase_addr:
    .dword FAIL_PHASE_PTR
fail_stage_addr:
    .dword FAIL_STAGE_PTR
labels_addr:
    .dword LABELS_BASE
defines_addr:
    .dword DEFINES_BASE
line_addr:
    .dword LINE_BASE
token_ptrs_addr:
    .dword TOKEN_PTRS_BASE
source_base_addr:
    .dword SOURCE_BASE
stack_top_addr:
    .dword STACK_TOP

str_as0:
    .string "as0"
str_dot:
    .string "."
str_dot_align:
    .string ".align"
str_dot_byte:
    .string ".byte"
str_dot_dword:
    .string ".dword"
str_dot_equ:
    .string ".equ"
str_dot_global:
    .string ".global"
str_dot_string:
    .string ".string"
str_dot_text:
    .string ".text"
str_dot_word:
    .string ".word"
str_minus:
    .string "-"
str_plus:
    .string "+"

str_add:
    .string "add"
str_addi:
    .string "addi"
str_andi:
    .string "andi"
str_and:
    .string "and"
str_beqz:
    .string "beqz"
str_beq:
    .string "beq"
str_bge:
    .string "bge"
str_bgeu:
    .string "bgeu"
str_bgt:
    .string "bgt"
str_bgtu:
    .string "bgtu"
str_bgtz:
    .string "bgtz"
str_call:
    .string "call"
str_ble:
    .string "ble"
str_bleu:
    .string "bleu"
str_blez:
    .string "blez"
str_bgez:
    .string "bgez"
str_blt:
    .string "blt"
str_bltu:
    .string "bltu"
str_bltz:
    .string "bltz"
str_bne:
    .string "bne"
str_bnez:
    .string "bnez"
str_ebreak:
    .string "ebreak"
str_ecall:
    .string "ecall"
str_fence:
    .string "fence"
str_fence_i:
    .string "fence.i"
str_j:
    .string "j"
str_jal:
    .string "jal"
str_jalr:
    .string "jalr"
str_jr:
    .string "jr"
str_lbu:
    .string "lbu"
str_ld:
    .string "ld"
str_li:
    .string "li"
str_lui:
    .string "lui"
str_la:
    .string "la"
str_lw:
    .string "lw"
str_lwu:
    .string "lwu"
str_mul:
    .string "mul"
str_mv:
    .string "mv"
str_neg:
    .string "neg"
str_negw:
    .string "negw"
str_not:
    .string "not"
str_or:
    .string "or"
str_sb:
    .string "sb"
str_seqz:
    .string "seqz"
str_sd:
    .string "sd"
str_sgtz:
    .string "sgtz"
str_slt:
    .string "slt"
str_sltiu:
    .string "sltiu"
str_sltu:
    .string "sltu"
str_sltz:
    .string "sltz"
str_snez:
    .string "snez"
str_sub:
    .string "sub"
str_subw:
    .string "subw"
str_sw:
    .string "sw"
str_slli:
    .string "slli"
str_srli:
    .string "srli"
str_tail:
    .string "tail"
str_ret:
    .string "ret"
str_xor:
    .string "xor"
str_xori:
    .string "xori"

reg_zero:
    .string "zero"
reg_ra:
    .string "ra"
reg_sp:
    .string "sp"
reg_gp:
    .string "gp"
reg_tp:
    .string "tp"
reg_fp:
    .string "fp"
