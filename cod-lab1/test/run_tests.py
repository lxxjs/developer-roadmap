#!/usr/bin/env python3
"""用 clang/lld 汇编实验程序，再用 unicorn 模拟监控程序的运行环境进行验证。

模拟的环境与基础版监控程序一致：
  - 用户程序装载到 0x80100000，并通过 ra 返回
  - 0x10000000 处是串口，LSR(0x10000005) 的 THRE 位恒为 1
同时检查程序只用到了监控程序的 19 条指令。

依赖：clang、ld.lld、llvm-objcopy、llvm-objdump，pip install unicorn
"""
import os
import re
import struct
import subprocess
import sys
import tempfile

from unicorn import Uc, UC_ARCH_RISCV, UC_MODE_RISCV32, UC_HOOK_MEM_WRITE
from unicorn.riscv_const import UC_RISCV_REG_RA, UC_RISCV_REG_SP, UC_RISCV_REG_PC

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'src')

USER_CODE = 0x80100000
USER_DATA = 0x80400000
RETURN_ADDR = 0x80000000   # 模拟监控程序中的返回地址
COM1 = 0x10000000

SUPERVISOR_19 = {
    'add', 'addi', 'and', 'andi', 'auipc', 'beq', 'bne', 'jal', 'jalr', 'lb',
    'lui', 'lw', 'or', 'ori', 'sb', 'slli', 'srli', 'sw', 'xor',
}


def assemble(name):
    src = os.path.join(SRC, name)
    with tempfile.TemporaryDirectory() as d:
        obj, elf, bin_ = (os.path.join(d, x) for x in ('a.o', 'a.elf', 'a.bin'))
        subprocess.check_call(['clang', '--target=riscv32', '-march=rv32i',
                               '-mno-relax', '-c', src, '-o', obj])
        subprocess.check_call(['ld.lld', '-Ttext=0x%x' % USER_CODE,
                               '-e', '0x%x' % USER_CODE, obj, '-o', elf])
        subprocess.check_call(['llvm-objcopy', '-O', 'binary', '-j', '.text', elf, bin_])
        dump = subprocess.check_output(['llvm-objdump', '-d', '-M', 'no-aliases',
                                        '--no-show-raw-insn', elf]).decode()
        with open(bin_, 'rb') as f:
            return f.read(), dump


def used_mnemonics(dump):
    ops = set()
    for line in dump.splitlines():
        m = re.match(r'^\s*[0-9a-f]+:\s+(\S+)', line)
        if m:
            ops.add(m.group(1))
    return ops


def run(code, max_insns=100000):
    uc = Uc(UC_ARCH_RISCV, UC_MODE_RISCV32)
    uc.mem_map(0x80000000, 8 * 1024 * 1024)
    uc.mem_map(COM1, 0x1000)
    uc.mem_write(COM1 + 5, b'\x20')          # THRE = 1，串口始终可写
    uc.mem_write(USER_CODE, code)
    uc.reg_write(UC_RISCV_REG_RA, RETURN_ADDR)
    uc.reg_write(UC_RISCV_REG_SP, 0x807F0000)

    out = bytearray()

    def on_write(uc_, access, addr, size, value, user):
        if addr == COM1:
            out.append(value & 0xFF)

    uc.hook_add(UC_HOOK_MEM_WRITE, on_write, begin=COM1, end=COM1)
    uc.emu_start(USER_CODE, RETURN_ADDR, count=max_insns)
    assert uc.reg_read(UC_RISCV_REG_PC) == RETURN_ADDR, '程序没有通过 jr ra 返回'
    return uc, bytes(out)


def fib(n):
    a, b = 1, 1
    for _ in range(n - 1):
        a, b = b, a + b
    return a


def main():
    failed = False

    def check(title, cond, detail=''):
        nonlocal failed
        print('[%s] %s %s' % ('PASS' if cond else 'FAIL', title, detail))
        failed |= not cond

    for name in ('fib10.s', 'ascii.s', 'fib60.s'):
        code, dump = assemble(name)
        extra = used_mnemonics(dump) - SUPERVISOR_19
        check(name + ' 只使用 19 条指令', not extra, sorted(extra) if extra else '')

    code, _ = assemble('fib10.s')
    uc, _ = run(code)
    words = struct.unpack('<10I', uc.mem_read(USER_DATA, 40))
    for i, w in enumerate(words):
        print('  0x%08x: 0x%08x' % (USER_DATA + 4 * i, w))
    check('fib10 结果', list(words) == [fib(i) for i in range(1, 11)], str(list(words)))

    code, _ = assemble('ascii.s')
    _, out = run(code)
    print('  ' + out.decode())
    check('ascii 输出', out == bytes(range(0x21, 0x7F)))

    code, _ = assemble('fib60.s')
    uc, _ = run(code)
    lo, hi = struct.unpack('<2I', uc.mem_read(USER_DATA, 8))
    print('  0x%08x: 0x%08x\n  0x%08x: 0x%08x' % (USER_DATA, lo, USER_DATA + 4, hi))
    val = (hi << 32) | lo
    check('fib60 结果', val == fib(60), '%d (0x%x)' % (val, val))

    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
