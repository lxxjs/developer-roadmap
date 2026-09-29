# 实验 1-1：前 10 个 Fibonacci 数（F1 = F2 = 1）
# 结果依次保存到 0x80400000 开始的 10 个字中
# 用法：term 中 F 命令，地址 0x80100000；然后 G 0x80100000，D 0x80400000 40
    li t0, 0x80400000
    li t1, 1
    li t2, 1
    li t3, 10
loop:
    sw t1, 0(t0)
    add t4, t1, t2
    mv t1, t2
    mv t2, t4
    addi t0, t0, 4
    addi t3, t3, -1
    bne t3, zero, loop
    jr ra
