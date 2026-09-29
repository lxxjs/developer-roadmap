const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, Table, TableRow, TableCell,
  WidthType, ShadingType, BorderStyle, LevelFormat, TableOfContents, PageBreak, Footer, PageNumber,
} = require('docx');

const SRC = path.join(__dirname, '..', 'src');
const OUT = path.join(__dirname, '..', '实验1报告.docx');

const CN = '宋体';
const HEI = '黑体';
const MONO = 'Consolas';
const CONTENT_W = 9026;

// 行内标记：`code` → 等宽，**bold** → 粗体
function runs(text, base = {}) {
  const out = [];
  const re = /(`[^`]+`|\*\*[^*]+\*\*)/g;
  let last = 0, m;
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(new TextRun({ text: text.slice(last, m.index), ...base }));
    const t = m[0];
    if (t.startsWith('`')) out.push(new TextRun({ text: t.slice(1, -1), font: MONO, ...base }));
    else out.push(new TextRun({ text: t.slice(2, -2), bold: true, ...base }));
    last = m.index + t.length;
  }
  if (last < text.length) out.push(new TextRun({ text: text.slice(last), ...base }));
  return out;
}

const p = (text, opts = {}) => new Paragraph({
  children: runs(text), spacing: { after: 120, line: 360 }, indent: opts.noIndent ? undefined : { firstLine: 480 }, ...opts.para,
});
const plain = (text) => p(text, { noIndent: true });
const h1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(t)] });
const h2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(t)] });
const h3 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_3, children: [new TextRun(t)] });
const bullet = (text, level = 0) => new Paragraph({
  numbering: { reference: 'bullets', level }, children: runs(text), spacing: { after: 60, line: 340 },
});
const num = (text, ref = 'nums') => new Paragraph({
  numbering: { reference: ref, level: 0 }, children: runs(text), spacing: { after: 60, line: 340 },
});

function code(src) {
  const lines = src.replace(/\s+$/, '').split('\n');
  return lines.map((l, i) => new Paragraph({
    children: [new TextRun({ text: l.length ? l : ' ', font: MONO, size: 18 })],
    shading: { type: ShadingType.CLEAR, fill: 'F3F4F6', color: 'auto' },
    spacing: { before: i === 0 ? 120 : 0, after: i === lines.length - 1 ? 160 : 0, line: 260 },
    indent: { left: 200, right: 200 },
    border: {
      left: { style: BorderStyle.SINGLE, size: 12, color: '9CA3AF', space: 6 },
    },
  }));
}

function table(headers, rows, widths) {
  const total = widths.reduce((a, b) => a + b, 0);
  const border = { style: BorderStyle.SINGLE, size: 4, color: '808080' };
  const borders = { top: border, bottom: border, left: border, right: border };
  const cell = (text, w, head) => new TableCell({
    width: { size: w, type: WidthType.DXA },
    borders,
    shading: head ? { type: ShadingType.CLEAR, fill: 'E5E7EB', color: 'auto' } : undefined,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    children: [new Paragraph({ children: runs(text, head ? { bold: true, size: 20 } : { size: 20 }) })],
  });
  return new Table({
    width: { size: total, type: WidthType.DXA },
    columnWidths: widths,
    rows: [
      new TableRow({ tableHeader: true, children: headers.map((h, i) => cell(h, widths[i], true)) }),
      ...rows.map((r) => new TableRow({ children: r.map((c, i) => cell(c, widths[i], false)) })),
    ],
  });
}
const gap = () => new Paragraph({ children: [], spacing: { after: 120 } });

let shotNo = 0;
function shot(title, how) {
  shotNo += 1;
  const dash = { style: BorderStyle.DASHED, size: 8, color: 'C0392B', space: 4 };
  const box = { top: dash, bottom: dash, left: dash, right: dash };
  const paras = [
    new Paragraph({
      alignment: AlignmentType.CENTER, border: box,
      shading: { type: ShadingType.CLEAR, fill: 'FDF2F2', color: 'auto' },
      spacing: { before: 160, after: 0 },
      children: [new TextRun({ text: `【在此插入截图 ${shotNo}】`, bold: true, color: 'C0392B' })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER, border: box,
      shading: { type: ShadingType.CLEAR, fill: 'FDF2F2', color: 'auto' },
      spacing: { after: 0 },
      children: [new TextRun({ text: `应包含：${how}`, color: '7F1D1D', size: 20 })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER, border: box,
      shading: { type: ShadingType.CLEAR, fill: 'FDF2F2', color: 'auto' },
      spacing: { after: 0 },
      children: [new TextRun({ text: ' ', size: 20 }), new TextRun({ break: 3 })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER, spacing: { before: 60, after: 200 },
      children: [new TextRun({ text: `图 ${shotNo}  ${title}`, size: 20 })],
    }),
  ];
  return paras;
}

const srcFile = (n) => fs.readFileSync(path.join(SRC, n), 'utf8');

// ---------------------------------------------------------------- 正文
const body = [];
const add = (...xs) => xs.flat().forEach((x) => body.push(x));

// 封面
add(
  new Paragraph({ spacing: { before: 2400 }, children: [] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 300 },
    children: [new TextRun({ text: '计算机组成原理', font: HEI, size: 44, bold: true })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 1600 },
    children: [new TextRun({ text: '实验 1：汇编语言与监控程序 实验报告', font: HEI, size: 36, bold: true })] }),
  ...['姓    名：', '学    号：', '班    级：', '日    期：'].map((t) => new Paragraph({
    alignment: AlignmentType.CENTER, spacing: { after: 200 },
    children: [new TextRun({ text: t, size: 28 }), new TextRun({ text: '________________________', size: 28 })],
  })),
  new Paragraph({ children: [new PageBreak()] }),
  new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 200 },
    children: [new TextRun({ text: '目  录', font: HEI, size: 32, bold: true })] }),
  new TableOfContents('目录', { hyperlink: true, headingStyleRange: '1-2' }),
  new Paragraph({ children: [new PageBreak()] }),
);

// 一、实验目的
add(
  h1('一、实验目的'),
  bullet('熟悉 RISC-V（RV32I）指令格式与汇编语言编程。'),
  bullet('掌握 RISC-V 交叉编译工具链与 QEMU 模拟器的使用，能在模拟器中运行监控程序（Kernel）并通过终端程序（Term）与之交互。'),
  bullet('熟练使用 Term 的 A、F、U、G、D、R 等命令，编写汇编程序并在监控程序中运行、检查结果。'),
  bullet('阅读监控程序与终端程序源代码，理解其结构以及二者通过串口交互的流程，为后续实现支持监控程序 19 条指令的五级流水线处理器打下基础。'),
);

// 二、实验环境
add(
  h1('二、实验环境'),
  table(['项目', '说明'], [
    ['硬件 / 操作系统', '（请按实际填写，例如：MacBook Air M3，macOS 15 / Ubuntu 22.04）'],
    ['模拟器', 'QEMU（qemu-system-riscv32），`brew install qemu` 或 `apt install qemu-system-misc`'],
    ['交叉编译工具链', 'riscv64-elf-gcc / binutils（Homebrew），或 riscv64-unknown-elf-gcc'],
    ['Python', 'Python 3 + pyserial（在 venv 中安装）'],
    ['监控程序', 'thu-cs-lab/supervisor-rv（commit 5010858），基础版本，RV32'],
  ], [2400, 6626]),
  gap(),
  p('监控程序与终端程序的获取与启动命令如下（Homebrew 工具链的前缀为 `riscv64-elf-`，需要通过 `GCCPREFIX` 指定；使用 `riscv64-unknown-elf-` 工具链时可省略）：'),
  ...code(`git clone https://github.com/thu-cs-lab/supervisor-rv.git
cd supervisor-rv
python3 -m venv venv && source venv/bin/activate && pip install pyserial

# 终端 1：编译 Kernel 并在 QEMU 中启动，等待 Term 连接（tcp:6666）
cd kernel && make GCCPREFIX=riscv64-elf- sim

# 终端 2：启动 Term 并连接模拟器
GCCPREFIX=riscv64-elf- python3 term/term.py -t 127.0.0.1:6666`),
);

// 三、实验内容与过程
add(
  h1('三、实验内容与过程'),
  h2('3.1 在模拟器中运行监控程序'),
  p('执行 `make sim` 后，QEMU 以 `-M virt -m 32M -kernel kernel.elf -bios none -serial tcp::6666,server` 启动监控程序，并在 6666 端口等待连接。随后运行 Term 连接，Term 首先收到监控程序输出的欢迎信息 “MONITOR for RISC-V - initialized.”，再探测到 XLEN = 4，进入命令循环：'),
  ...code(`connecting to 127.0.0.1:6666...connected
MONITOR for RISC-V - initialized.
running in 32bit, xlen = 4
>>`),
  shot('编译并在 QEMU 中启动监控程序', '终端 1 中 make sim 的输出（QEMU waiting for connection on ... 6666）'),
  shot('Term 连接监控程序', '终端 2 中 connected、MONITOR for RISC-V - initialized.、running in 32bit, xlen = 4'),

  h2('3.2 Term 常用命令'),
  table(['命令', '功能', '用法示例'], [
    ['A', '逐行输入汇编指令（支持标签、伪指令、十六进制机器码），写入指定地址，空行结束', '`A` → `addr: 0x80100000`'],
    ['F', '从文件读入汇编指令写入指定地址，格式同 A', '`F` → 文件名 → `addr: 0x80100000`'],
    ['U', '读取内存并反汇编', '`U` → `0x80100000` → `num: 64`'],
    ['G', '运行指定地址的用户程序并显示运行时间', '`G` → `0x80100000`'],
    ['D', '按字显示内存（num 为十进制且为 4 的倍数）', '`D` → `0x80400000` → `num: 40`'],
    ['R', '显示用户寄存器 x1~x31', '`R`'],
    ['Q', '退出 Term', '`Q`'],
  ], [900, 5026, 3100]),
  gap(),
  p('用户程序代码区为 0x80100000~0x803FFFFF，数据区为 0x80400000~0x807EFFFF；用户程序必须以 `jr ra` 结束才能返回监控程序。下面以 README 中的示例程序练习 A、U、G、R 命令：'),
  ...code(`>> A
addr: 0x80100000
[0x80100000] li a0, 5
[0x80100004] li t0, 0
[0x80100008] li t1, 0
[0x8010000c] loop:
[0x8010000c] add t1, t1, t0
[0x80100010] addi t0, t0, 1
[0x80100014] bne a0, t0, loop
[0x80100018] jr ra
[0x8010001c]
>> U      (addr: 0x80100000, num: 28)
>> G      (addr: 0x80100000)
>> R      (t0 = 0x00000005, t1 = 0x0000000a)`),
  shot('A / U / G / R 命令的使用', 'A 输入程序、U 反汇编结果、G 运行（elapsed time）、R 中 t0=5、t1=0xa'),

  h2('3.3 求前 10 个 Fibonacci 数'),
  h3('设计思路'),
  p('用 `t1`、`t2` 保存相邻两项 F(n)、F(n+1)，初值均为 1；每次循环先把 F(n) 存到 `t0` 指向的内存，再计算 F(n+2) = F(n) + F(n+1)，并把两项整体后移一位，`t0` 加 4，计数器 `t3` 减 1，共循环 10 次。'),
  h3('汇编代码（fib10.s）'),
  ...code(srcFile('fib10.s')),
  h3('运行与结果'),
  ...code(`>> F
>>file name: fib10.s
>>addr: 0x80100000
>> G
addr: 0x80100000
elapsed time: 0.000s
>> D
addr: 0x80400000
num: 40
0x80400000: 0x00000001
0x80400004: 0x00000001
0x80400008: 0x00000002
0x8040000c: 0x00000003
0x80400010: 0x00000005
0x80400014: 0x00000008
0x80400018: 0x0000000d
0x8040001c: 0x00000015
0x80400020: 0x00000022
0x80400024: 0x00000037`),
  p('结果依次为 1, 1, 2, 3, 5, 8, 13, 21, 34, 55，正确。'),
  shot('前 10 个 Fibonacci 数', 'F（或 A）输入程序、G 运行、D 0x80400000 40 的 10 个结果'),

  h2('3.4 输出 ASCII 可见字符'),
  h3('设计思路'),
  p('从 0x21 循环到 0x7E，每次把字符放入 `a0` 后调用实验文档提供的 `WRITE_SERIAL` 函数。该函数轮询串口状态寄存器（0x10000005）的第 5 位（THRE），可写时用 `sb` 把 `a0` 最低字节写到 0x10000000。'),
  p('需要注意两点：（1）`jal WRITE_SERIAL` 会覆盖 `ra`，因此程序开头先把返回监控程序的地址保存到 `s1`，结束前再恢复；（2）`WRITE_SERIAL` 会破坏 `t0`、`t1`，所以循环变量放在 `s2`、`s3` 中。基础版监控程序在用户程序返回后会保存全部寄存器，因此使用 s 寄存器没有问题。另外 0x21~0x7E 与 Term 使用的控制信号 0x06/0x07/0x80/0x81 不冲突，Term 会原样显示。'),
  h3('汇编代码（ascii.s）'),
  ...code(srcFile('ascii.s')),
  h3('运行与结果'),
  ...code(`>> G
addr: 0x80100000
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_\`abcdefghijklmnopqrstuvwxyz{|}~
elapsed time: 0.001s`),
  shot('输出 ASCII 可见字符', 'G 运行后输出的 !"#$...xyz{|}~ 一整行'),

  h2('3.5 求第 60 个 Fibonacci 数'),
  h3('设计思路'),
  p('F(60) = 1548008755920 = 0x0000_0168_6C83_12D0，超出 32 位范围，因此用两个 32 位寄存器 {hi, lo} 表示一个 64 位整数：a = {t1, t0}，b = {t3, t2}，c = a + b = {t6, t5}。低 32 位直接相加，高 32 位相加后再加上低位的进位：'),
  ...code(`c_lo = a_lo + b_lo
c_hi = a_hi + b_hi + carry`),
  p('求进位通常使用 `sltu carry, c_lo, a_lo`，但 SLTU 不在监控程序的 19 条指令之中。为了只使用这 19 条指令（后续实验中无需额外实现指令），本程序利用全加器最高位进位的逻辑表达式计算进位：'),
  ...code('carry = MSB( (a_lo & b_lo) | ((a_lo | b_lo) & ~c_lo) )'),
  p('即：两个加数最高位都为 1 时一定进位；只有一个为 1 时，若和的最高位变为 0 则发生了进位。其中 `~c_lo` 用与全 1 寄存器 `s2` 异或（XOR）得到，最后 `srli 31` 取出最高位。从 F(1)=F(2)=1 开始循环 58 次后 b 即为 F(60)，按小端序先存低字再存高字。'),
  h3('汇编代码（fib60.s）'),
  ...code(srcFile('fib60.s')),
  h3('运行与结果'),
  ...code(`>> D
addr: 0x80400000
num: 8
0x80400000: 0x6c8312d0
0x80400004: 0x00000168`),
  p('组合得到 0x000001686C8312D0 = 1548008755920 = F(60)，结果正确。'),
  shot('第 60 个 Fibonacci 数', 'G 运行、D 0x80400000 8 显示 0x6c8312d0 与 0x00000168'),

  h2('3.6 程序正确性的离线验证'),
  p('除了在 QEMU 中运行外，还编写了测试脚本 `test/run_tests.py`：用 clang 将三个程序汇编链接到 0x80100000，用 llvm-objdump 检查只使用了监控程序的 19 条指令，再用 unicorn 模拟执行（模拟 0x10000000 处的串口），检查存储结果和串口输出。三个程序全部通过。'),
);

// 四、代码分析
add(
  h1('四、监控程序与终端程序代码分析'),
  h2('4.1 总体结构'),
  p('监控程序分为 Kernel 和 Term 两部分。Kernel 用 RISC-V 汇编编写，运行在处理器（本实验中为 QEMU）上，负责管理硬件资源、执行命令；Term 是运行在 PC 上的 Python 程序，提供命令行界面，负责汇编、反汇编以及结果显示。二者之间只通过串口通信（在 QEMU 中串口被重定向到 TCP 6666 端口）。'),
  table(['文件', '作用'], [
    ['kernel/kern/init.S', '入口 START：清 BSS、设置栈、初始化用户 sp/fp、初始化串口、打印欢迎信息，进入 SHELL'],
    ['kernel/kern/shell.S', 'SHELL 命令循环：解析 R/D/A/G/T 命令，保存和恢复用户寄存器，运行用户程序'],
    ['kernel/kern/utils.S', '串口读写函数：WRITE_SERIAL、READ_SERIAL 及其按字、按 XLEN、字符串版本'],
    ['kernel/kern/test.S', 'UTEST_* 测试程序（CRYPTONIGHT、SPIN 等）'],
    ['kernel/kern/trap.S, evec.S', '异常/中断处理（仅扩展版本 EN_INT 使用）'],
    ['kernel/include/*.h', 'common.h（XLEN、信号常量）、serial.h（串口地址与寄存器）、exception.h（中断帧布局）'],
    ['term/term.py', '终端程序：连接、欢迎信息与 XLEN 探测、命令循环、调用 as/objcopy/objdump'],
  ], [2900, 6126]),
  gap(),
  h2('4.2 地址空间分配'),
  table(['地址区间', '用途'], [
    ['0x80000000–0x800FFFFF', '监控程序代码（入口 START）'],
    ['0x80100000–0x803FFFFF', '用户程序代码'],
    ['0x80400000–0x807EFFFF', '用户程序数据'],
    ['0x807F0000–0x807FFFFF', '监控程序数据（uregs 等），内核栈顶 0x80800000'],
    ['0x10000000–0x10000007', '串口（UART 16550）数据及状态寄存器'],
  ], [3400, 5626]),
  gap(),
  h2('4.3 Kernel 执行流程'),
  num('`START`（init.S:99）：清空 BSS；设置内核栈 `sp = KERNEL_STACK_INIT`；把用户程序的 sp、fp 初值 0x807F0000 写入 uregs；若定义 ENABLE_UART16550，则按 16550 流程初始化串口（init.S:143~163）；在内核栈上预留中断帧空间并填写 TCBT；最后跳到 WELCOME。', 'kflow'),
  num('`WELCOME`（init.S:389）：调用 `WRITE_SERIAL_STRING` 输出 “MONITOR for RISC-V - initialized.”，然后进入 SHELL。', 'kflow'),
  num('`SHELL`（shell.S:21）：调用 `READ_SERIAL` 读入一个命令字符并分发：R —— 把 uregs 中 31 个寄存器逐字节发出；D —— 读入地址和长度，把对应内存逐字节发出；A —— 读入地址和长度，每次读 4 字节并用 `sw` 写入内存；G —— 运行用户程序；T —— 发送页表地址（基础版为 -1）；其他字符 —— 回送 XLEN。处理完毕后 `j .DONE` 回到 SHELL，形成无限循环。', 'kflow'),
  num('G 命令（shell.S:165）：读入入口地址存入 s10 → 发送 0x06 → 从 uregs 恢复用户寄存器 → `la ra, .USERRET2; jr s10` 进入用户程序 → 用户程序 `jr ra` 返回到 `.USERRET2`（shell.S:297）→ 保存用户寄存器到 uregs、恢复内核栈 → 发送 0x07。', 'kflow'),
  h2('4.4 Term 执行流程'),
  num('根据参数 `-t host:port`（TCP，连接 QEMU）或 `-s 串口名`（真实串口）建立连接（term.py:530~557），并检查 as/objdump/objcopy 是否可用。', 'tflow'),
  num('`Main()`（term.py:435）：读取 33 字节欢迎信息并显示，发送 `W` 探测 XLEN，确定 rv32/rv64。', 'tflow'),
  num('`MainLoop()`（term.py:375）：读入用户命令，先清空输入缓冲区，再调用对应的 run_X 函数。', 'tflow'),
  num('`run_A` / `run_F`：把输入的汇编（支持标签和十六进制机器码）加上 `.org` 写入临时文件，调用 `as` 汇编、`objcopy -O binary` 得到机器码，每 4 字节发送一次 “`A` + 地址 + 4 + 数据”。', 'tflow'),
  num('`run_D` / `run_U`：发送 “`D` + 地址 + 长度”，接收数据后按字显示；U 还调用 `objdump -b binary` 逐条反汇编。`run_R` 发送 `R` 并接收 31×XLEN 字节。`run_G` 见思考题 3。', 'tflow'),
  h2('4.5 通信协议'),
  p('命令为 1 个 ASCII 字符；地址、长度等参数为 XLEN 字节的小端整数（Term 的 `int_to_byte_string` 与 Kernel 的 `READ_SERIAL_XLEN` 对应）；数据为原始字节流。G 命令期间使用 0x06（开始计时）、0x07（结束计时）作为控制信号，扩展版还使用 0x80（严重错误）、0x81（超时）。'),
);

// 五、思考题
add(
  h1('五、思考题'),
  h2('5.1 比较 RISC-V 指令寻址方法与 x86 指令寻址方法的异同'),
  table(['寻址方式', 'RISC-V（RV32I）', 'x86'], [
    ['立即数寻址', '`addi t0, t0, 5`（12 位有符号）；`lui`/`auipc`（高 20 位）', '`mov eax, 5`（8/16/32 位，x86-64 可 64 位）'],
    ['寄存器寻址', '`add t0, t1, t2`', '`add eax, ebx`'],
    ['直接（绝对）寻址', '无，需 `lui` + `lw` 组合', '`mov eax, [0x1234]`'],
    ['寄存器间接寻址', '`lw t0, 0(t1)`（偏移为 0 的基址寻址）', '`mov eax, [ebx]`'],
    ['基址 + 偏移', '`lw t0, 8(t1)`，是唯一的访存寻址方式', '`mov eax, [ebx+8]`'],
    ['基址 + 变址×比例 + 偏移', '无，需用 `slli`/`add` 计算地址', '`mov eax, [ebx+esi*4+8]`（SIB）'],
    ['PC 相对寻址', '`beq`（±4 KiB）、`jal`（±1 MiB）、`auipc`', '`jmp/call rel8/rel32`，x86-64 `[rip+disp32]`'],
    ['段寻址', '无（平坦地址空间）', '段:偏移（CS/DS/SS/ES/FS/GS）'],
    ['隐含寻址', '无', '栈操作（push/pop 隐含 ESP）、串操作（ESI/EDI）'],
  ], [2200, 3413, 3413]),
  gap(),
  p('**相同点：**两者都支持立即数、寄存器、基址+偏移和 PC 相对寻址；都按字节编址、采用小端序；转移和调用指令都以相对 PC 的偏移编码。'),
  p('**不同点：**'),
  num('**Load/Store 结构与存储器操作数：**RISC-V 只有 load/store 指令访问内存，运算指令的操作数只能是寄存器或立即数；x86 的运算指令可以直接使用内存操作数，如 `add eax, [ebx]`、`add [ebx], eax`。', 'q1'),
  num('**寻址方式数量：**RISC-V 的访存地址只有 `rs1 + imm12` 一种，地址计算硬件简单，便于流水线设计；x86 通过 ModR/M 和 SIB 字节组合出多种复杂寻址方式，一条指令内即可完成复杂地址计算。', 'q1'),
  num('**指令长度与立即数宽度：**RISC-V 指令定长 32 位，立即数只有 12 位（I/S 型）或 20 位（U/J 型），大常数和远地址需要 `lui+addi`、`auipc+addi/jalr` 两条指令合成（伪指令 `li`、`la`、`call`）；x86 为变长指令（1~15 字节），可直接携带 32 位偏移或立即数。', 'q1'),
  num('**条件转移：**RISC-V 的 `beq rs1, rs2, offset` 在一条指令中完成比较和转移；x86 需要先用 `cmp` 设置 FLAGS，再由 `jcc` 根据标志位转移。', 'q1'),
  num('**间接转移：**RISC-V 的 `jalr rd, imm(rs1)` 只支持寄存器+偏移；x86 还支持存储器间接转移，如 `jmp [mem]`、`call [ebx*4+table]`。', 'q1'),
  num('**段与隐含操作数：**x86 有段寄存器以及栈、串操作指令的隐含寄存器寻址，RISC-V 没有。', 'q1'),

  h2('5.2 监控程序的 19 条指令及分类'),
  p('基础版本监控程序使用的 19 条指令为（可用 `make inst` 验证）：'),
  ...code('ADD  ADDI  AND  ANDI  AUIPC  BEQ  BNE  JAL  JALR  LB\nLUI  LW    OR   ORI   SB     SLLI SRLI SW   XOR'),
  h3('（1）按功能分类'),
  table(['类别', '指令', '分类原因 / 在监控程序中的用途'], [
    ['算术逻辑运算（寄存器-寄存器）', 'ADD, AND, OR, XOR', '两个源寄存器经 ALU 运算写回 rd；如 `or s1, a0, zero` 复制寄存器、`or a0, a0, s2` 拼接字节'],
    ['算术逻辑运算（寄存器-立即数）', 'ADDI, ANDI, ORI, SLLI, SRLI', '一个操作数为 12 位立即数（移位为 5 位 shamt）；如 `addi sp, sp, -8`、`li`/`mv`、`andi t1, t1, 0x20` 取状态位、`srli a0, s0, 8` 拆字节'],
    ['高位立即数 / 地址生成', 'LUI, AUIPC', '把 20 位立即数放到高位；如 `li t0, 0x10000000`（lui）、`la a0, monitor_version`（auipc+addi）'],
    ['访存：读', 'LB, LW', '基址+偏移读内存到寄存器；`lb t1, 5(t0)` 读串口状态，`lw` 恢复寄存器'],
    ['访存：写', 'SB, SW', '寄存器写入内存；`sb a0, 0(t0)` 发送串口数据，`sw` 写入用户代码、保存寄存器'],
    ['条件转移', 'BEQ, BNE', '比较两个寄存器后按 PC 相对偏移转移；用于命令分发、循环、串口轮询'],
    ['无条件跳转', 'JAL, JALR', '`jal` 用于函数调用和 `j`；`jalr` 用于 `jr ra` 返回、`jr s10` 进入用户程序'],
  ], [2200, 2100, 4726]),
  gap(),
  h3('（2）按指令格式分类'),
  table(['格式', '指令'], [
    ['R 型', 'ADD, AND, OR, XOR'],
    ['I 型', 'ADDI, ANDI, ORI, SLLI, SRLI, LB, LW, JALR'],
    ['S 型', 'SB, SW'],
    ['B 型', 'BEQ, BNE'],
    ['U 型', 'LUI, AUIPC'],
    ['J 型', 'JAL'],
  ], [1800, 7226]),
  gap(),
  h3('（3）按处理器实现分类'),
  p('把数据通路相同的指令归为一类，只需实现 8 条代表指令，其余指令只需改变 ALU 运算类型或访存宽度即可扩展：'),
  ...code(`ADD  : ADDI, AND, ANDI, OR, ORI, SLLI, SRLI, XOR   （ALU 运算，结果写回 rd）
AUIPC:                                               （rd = PC + (imm << 12)）
BEQ  : BNE                                           （比较后 PC = PC + imm）
JAL  :                                               （rd = PC + 4，PC = PC + imm）
JALR :                                               （rd = PC + 4，PC = (rs1 + imm) & ~1）
LB   : LW                                            （读存储器，仅宽度/符号扩展不同）
LUI  :                                               （rd = imm << 12）
SB   : SW                                            （写存储器，仅宽度/字节使能不同）`),
  p('分类原因：同一类中的指令具有相同的指令格式（立即数的提取方式相同）、相同的数据通路（ALU→寄存器、访存或更新 PC）和相同的控制信号，区别只在 funct3/funct7 决定的 ALU 操作或访存宽度。后续设计五级流水线处理器时，可以按这种分类设计译码器和控制信号。'),

  h2('5.3 Term 如何实现用户程序计时'),
  p('基础版 Kernel 不使用计时器（mtime 等 CSR），因此**计时由 PC 端的 Term 完成，Kernel 只负责发送开始和结束信号**。信号定义于 `kernel/include/common.h:14~17`：'),
  ...code(`#define SIG_TIMERSET    0x06   // ACK，启动计时
#define SIG_TIMETOKEN   0x07   // BEL，停止计时
#define SIG_FATAL       0x80   // 严重错误（扩展版）
#define SIG_TIMEOUT     0x81   // 超时（扩展版）`),
  p('**Kernel 端（kern/shell.S，.OP_G）：**'),
  num('shell.S:168 调用 `READ_SERIAL_XLEN` 读入用户程序地址，保存到 s10；', 'q3k'),
  num('shell.S:174~175 执行 `li a0, SIG_TIMERSET; jal WRITE_SERIAL`，发送 0x06，通知 Term 开始计时；', 'q3k'),
  num('从 uregs 恢复用户寄存器，`la ra, .USERRET2; jr s10` 跳转执行用户程序；', 'q3k'),
  num('用户程序 `jr ra` 返回 `.USERRET2`（shell.S:297），保存用户寄存器、恢复内核栈；', 'q3k'),
  num('shell.S:341~343 执行 `li a0, SIG_TIMETOKEN; jal WRITE_SERIAL`，发送 0x07，通知 Term 程序结束。', 'q3k'),
  p('**Term 端（term/term.py:332~372，run_G）：**'),
  num('发送 `G` 和 XLEN 字节的地址；', 'q3t'),
  num('读 1 字节，确认为 0x06 后执行 `time_start = timer()`（timeit.default_timer，即 time.perf_counter）；', 'q3t'),
  num('循环逐字节读取：0x07 表示结束；0x81 显示 “killed timeout program.”；0x80 读取 mepc/mcause/mtval 并报告异常；其他字节视为用户程序输出直接显示；', 'q3t'),
  num('计算 `elapse = timer() - time_start`，输出 `elapsed time: %.3fs`。', 'q3t'),
  p('因此测得的时间是 Term 收到 0x06 到收到 0x07 之间的 PC 时间，其中包含串口传输延迟、用户程序输出字符的传输时间以及寄存器恢复/保存的时间，精度为毫秒级。扩展版（EN_INT）还会在进入用户程序前设置 mtimecmp（shell.S:185~204），超时时发送 SIG_TIMEOUT 终止程序。'),

  h2('5.4 Kernel 如何使用串口'),
  num('**内存映射 I/O：**串口为 16550 兼容设备，基地址 `COM1 = 0x10000000`（include/serial.h:5），Kernel 用普通的 `lb`/`sb` 指令访问其寄存器：偏移 0 为 RBR/THR（读为接收数据，写为发送数据）；偏移 5 为 LSR，第 5 位 THRE（0x20）表示可以发送，第 0 位 DR（0x01）表示收到数据（serial.h:31、36）。', 'q4'),
  num('**初始化（init.S:143~163，ENABLE_UART16550）：**FCR 写 0x7（开启并清空 FIFO）→ LCR 置 DLAB → 向 DLL/DLM 写分频值（115200/9600）→ LCR 设为 8 位数据、清 DLAB → MCR 写 0 → IER 写 RDI（接收中断使能；基础版 CPU 不开中断，实际仍为轮询）。', 'q4'),
  num('**轮询方式收发（kern/utils.S）：**`WRITE_SERIAL`（utils.S:14）用 `lb t1, 5(t0)` 读 LSR，`andi 0x20` 为 0 时忙等待，可写时 `sb a0, 0(t0)` 发送 a0 的低 8 位；`READ_SERIAL`（utils.S:78）等待 LSR 第 0 位为 1 后用 `lb a0, 0(t0)` 读入一个字节。', 'q4'),
  num('**上层封装：**`WRITE_SERIAL_WORD`/`WRITE_SERIAL_XLEN`（utils.S:25、54）从低字节到高字节（小端）发送 32 位/XLEN 位数据；`READ_SERIAL_WORD`/`READ_SERIAL_XLEN`（utils.S:89、126）接收 4/XLEN 个字节并用 `sll`、`or` 拼接；`WRITE_SERIAL_STRING`（utils.S:68）发送以 \\0 结尾的字符串（欢迎信息）。', 'q4'),
  num('**使用场景：**SHELL 用 `READ_SERIAL` 读命令字符，`READ_SERIAL_XLEN` 读地址与长度，`READ_SERIAL_WORD` 读 A 命令写入的机器码；用 `WRITE_SERIAL` 发送内存/寄存器内容、XLEN 和计时信号。', 'q4'),
  num('**在 QEMU 中：**`make sim` 的 `-serial tcp::6666,server` 把虚拟串口重定向到 TCP 端口，Term 的 `tcp_wrapper` 把它当作串口使用。', 'q4'),

  h2('5.5 Term 如何检查 Kernel 已经正确连入'),
  p('检查分两步完成：'),
  p('**第一步：欢迎信息（确认 Kernel 已启动）**'),
  bullet('Kernel：`kern/init.S:90~91` 定义 `monitor_version: .asciz "MONITOR for RISC-V - initialized."`（共 33 个字符）；初始化完成后在 `init.S:389~392` 的 WELCOME 处执行 `la a0, monitor_version; jal WRITE_SERIAL_STRING` 输出。'),
  bullet('Term：`term/term.py:438~440` 的 `Main()` 中执行 `output_binary(inp.read(33))`，恰好读取 33 字节并显示。使用 `-c/--continued` 参数时跳过这一步（用于重新连接已经启动的 Kernel）。'),
  p('**第二步：XLEN 探测（确认 Kernel 能响应命令）**'),
  bullet('Term：`term/term.py:442~456` 发送 Kernel 无法识别的命令 `W`，然后读取 1 字节：为 4 则输出 “running in 32bit, xlen = 4” 并设置 arch = rv32；为 8 则为 rv64；为其他小于 20 的值则报 “Got unexpected XLEN” 并退出；大于等于 20（残留的可见字符）则忽略并继续读取。'),
  bullet('Kernel：`kern/shell.S:21~41` 的 SHELL 读入命令字符，若不是 R/D/A/G/T 中的任何一个，则执行 shell.S:37~41：'),
  ...code(`// 错误的操作符，输出 XLEN，用于区分 RV32 和 RV64
li a0, XLEN
jal WRITE_SERIAL
j .DONE`),
  p('收到 4 或 8 说明 Kernel 已进入 SHELL 循环并能正确收发数据，同时 Term 确定了后续传输地址/长度所用的 XLEN 以及汇编器的 `-march` 参数。之后 Term 才进入 `MainLoop()`（term.py:457）。'),
);

// 六、总结
add(
  h1('六、实验总结'),
  p('本实验搭建了 RISC-V 交叉编译与 QEMU 模拟环境，运行了监控程序并使用 Term 完成了汇编程序的输入、反汇编、运行和结果检查。通过编写 Fibonacci 数列和串口输出程序，熟悉了 RV32I 的指令格式、伪指令展开（`li`、`mv`、`jr`）、函数调用时 `ra` 与临时寄存器的保存，以及用两个 32 位寄存器实现 64 位加法的方法；为了只使用监控程序的 19 条指令，用逻辑运算代替 SLTU 计算进位。阅读监控程序与终端程序源代码后，理解了二者基于串口的命令协议、计时方式和连接检查机制，为后续实现支持这 19 条指令的处理器打下了基础。'),
  p('（可在此补充个人在实验中遇到的问题与解决方法。）'),
);

// ---------------------------------------------------------------- 文档
const numberingRef = (ref) => ({
  reference: ref,
  levels: [{ level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT,
    style: { paragraph: { indent: { left: 480, hanging: 360 } } } }],
});

const doc = new Document({
  creator: 'student',
  title: '实验 1：汇编语言与监控程序 实验报告',
  styles: {
    default: {
      document: { run: { font: { ascii: 'Times New Roman', hAnsi: 'Times New Roman', eastAsia: CN }, size: 22 } },
    },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: { ascii: 'Arial', hAnsi: 'Arial', eastAsia: HEI }, size: 32, bold: true },
        paragraph: { spacing: { before: 360, after: 200 }, outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: { ascii: 'Arial', hAnsi: 'Arial', eastAsia: HEI }, size: 28, bold: true },
        paragraph: { spacing: { before: 280, after: 140 }, outlineLevel: 1 } },
      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { font: { ascii: 'Arial', hAnsi: 'Arial', eastAsia: HEI }, size: 24, bold: true },
        paragraph: { spacing: { before: 200, after: 100 }, outlineLevel: 2 } },
    ],
  },
  numbering: {
    config: [
      { reference: 'bullets', levels: [
        { level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 480, hanging: 300 } } } },
        { level: 1, format: LevelFormat.BULLET, text: '◦', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 960, hanging: 300 } } } },
      ] },
      ...['nums', 'kflow', 'tflow', 'q1', 'q3k', 'q3t', 'q4'].map(numberingRef),
    ],
  },
  features: { updateFields: true },
  sections: [{
    properties: { page: { size: { width: 11906, height: 16838 },
      margin: { top: 1440, bottom: 1440, left: 1440, right: 1440 } } },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER,
      children: [new TextRun({ children: [PageNumber.CURRENT] })] })] }) },
    children: body,
  }],
});

Packer.toBuffer(doc).then((buf) => { fs.writeFileSync(OUT, buf); console.log('wrote', OUT); });
