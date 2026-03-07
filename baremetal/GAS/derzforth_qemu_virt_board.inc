    .equ RAM_BASE_ADDR, 0x80000000
    .equ RAM_SIZE, 16 * 1024

    # The upstream program expects a ROM region, but for QEMU virt we link the
    # image directly at its runtime RAM base and skip the self-copy stage.
    .equ ROM_BASE_ADDR, RAM_BASE_ADDR
    .equ ROM_SIZE, RAM_SIZE


serial_init:
    ret


serial_getc:
    li t0, 0x10000005
1:
    lb a0, 0(t0)
    andi a0, a0, 1
    beqz a0, 1b
    li t0, 0x10000000
    lbu a0, 0(t0)
    ret


serial_putc:
    li t0, 0x10000005
1:
    lb t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 1b
    li t0, 0x10000000
    sb a0, 0(t0)
    ret
