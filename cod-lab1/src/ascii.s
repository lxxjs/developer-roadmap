# 实验 1-2：把 ASCII 可见字符 0x21~0x7E 输出到终端
# WRITE_SERIAL 会破坏 t0、t1，且 jal 会覆盖 ra，所以先把 ra 存到 s1
    mv s1, ra
    li s2, 0x21
    li s3, 0x7F
loop:
    mv a0, s2
    jal WRITE_SERIAL
    addi s2, s2, 1
    bne s2, s3, loop
    mv ra, s1
    jr ra
WRITE_SERIAL:
    li t0, 0x10000000
.TESTW:
    lb t1, 5(t0)
    andi t1, t1, 0x20
    beq t1, zero, .TESTW
.WSERIAL:
    sb a0, 0(t0)
    jr ra
