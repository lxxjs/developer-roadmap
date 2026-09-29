# 实验 1-3：第 60 个 Fibonacci 数（F1 = F2 = 1），64 位结果
# 结果按小端保存到 0x80400000 开始的 8 个字节（低字在前，高字在后）
# 64 位数 = {hi, lo}：a = {t1, t0}，b = {t3, t2}，c = {t6, t5}
# 只用监控程序的 19 条指令：进位不用 sltu，而用
#   carry = MSB( (a_lo & b_lo) | ((a_lo | b_lo) & ~c_lo) )
    li t0, 1
    li t1, 0
    li t2, 1
    li t3, 0
    li t4, 58
    li s2, -1
loop:
    add t5, t0, t2
    and a1, t0, t2
    or a2, t0, t2
    xor a3, t5, s2
    and a2, a2, a3
    or a1, a1, a2
    srli a1, a1, 31
    add t6, t1, t3
    add t6, t6, a1
    mv t0, t2
    mv t1, t3
    mv t2, t5
    mv t3, t6
    addi t4, t4, -1
    bne t4, zero, loop
    li a0, 0x80400000
    sw t2, 0(a0)
    sw t3, 4(a0)
    jr ra
