# 실험 1: 어셈블리 언어와 감독 프로그램 (Lab 1 — Assembly & Supervisor)

칭화대 컴퓨터 구성 원리(计算机组成原理) 실험 1 풀이입니다.
참고한 소스: [thu-cs-lab/supervisor-rv](https://github.com/thu-cs-lab/supervisor-rv) (commit `5010858`, 기본 버전 kernel). 아래 줄 번호는 모두 이 커밋 기준입니다.

```
cod-lab1/
├── src/
│   ├── fib10.s    # 1) 처음 10개 Fibonacci 수 → 0x80400000 부터 10 word
│   ├── ascii.s    # 2) ASCII 0x21~0x7E 를 터미널로 출력
│   └── fib60.s    # 3) 60번째 Fibonacci 수 (64bit) → 0x80400000 부터 8 byte
└── test/
    └── run_tests.py   # clang 으로 어셈블 + unicorn 으로 실행해 결과 검증
```

세 프로그램 모두 **감독 프로그램의 19개 명령어만** 사용합니다(`run_tests.py`가 역어셈블 결과로 확인). 따라서 이후 실험 5에서 추가 명령어를 구현할 필요가 없습니다.

---

## 1. 실험 환경과 실행 방법

### 1.1 환경 구축

```bash
# 교차 컴파일러 (Ubuntu 예시; riscv64-unknown-elf-* 를 PATH 에 두면 됨)
sudo apt install gcc-riscv64-unknown-elf qemu-system-misc python3-serial

git clone https://github.com/thu-cs-lab/supervisor-rv.git
cd supervisor-rv/kernel
make sim            # kernel.elf 빌드 후 QEMU 실행, tcp:6666 에서 term 접속 대기
```

다른 창에서:

```bash
cd supervisor-rv/term
python3 term.py -t 127.0.0.1:6666
# connecting to 127.0.0.1:6666...connected
# MONITOR for RISC-V - initialized.
# running in 32bit, xlen = 4
```

### 1.2 Term 명령 요약

| 명령 | 기능 | 예 |
| --- | --- | --- |
| `A` | 어셈블리를 한 줄씩 입력해 지정 주소에 기록 (빈 줄로 종료) | `A` → `addr: 0x80100000` |
| `F` | 파일에서 어셈블리를 읽어 지정 주소에 기록 | `F` → `file name: fib10.s` → `addr: 0x80100000` |
| `U` | 메모리를 읽어 역어셈블 | `U` → `0x80100000` → `num: 64` |
| `G` | 지정 주소의 사용자 프로그램 실행, 실행 시간 출력 | `G` → `0x80100000` |
| `D` | 메모리 내용을 word 단위로 출력 (num 은 4의 배수, **10진수**) | `D` → `0x80400000` → `40` |
| `R` | 사용자 레지스터 x1~x31 출력 | `R` |
| `Q` | 종료 | |

사용자 프로그램은 코드 영역 `0x80100000~0x803FFFFF` 에 두고, 반드시 `jr ra` 로 끝나야 감독 프로그램으로 돌아옵니다. 데이터 영역은 `0x80400000~0x807EFFFF` 입니다.

### 1.3 오프라인 검증 (선택)

QEMU 없이도 코드 자체를 검증할 수 있습니다.

```bash
pip install unicorn          # clang, ld.lld, llvm-objcopy, llvm-objdump 필요
python3 cod-lab1/test/run_tests.py
```

`0x80100000` 에 프로그램을 올리고 `ra` 를 가짜 복귀 주소로 둔 뒤 실행하며, 0x10000000 에 쓰인 바이트를 가로채 출력으로 모읍니다. 실행 결과:

```
[PASS] fib10.s 只使用 19 条指令
[PASS] ascii.s 只使用 19 条指令
[PASS] fib60.s 只使用 19 条指令
[PASS] fib10 结果 [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
  !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~
[PASS] ascii 输出
[PASS] fib60 结果 1548008755920 (0x1686c8312d0)
```

> 보고서에 넣을 스크린샷은 실제 QEMU + term 에서 아래 절차대로 실행해 캡처하세요.

---

## 2. 실험 내용별 코드

### 2.1 처음 10개의 Fibonacci 수 (`src/fib10.s`)

`t1`, `t2` 에 연속된 두 항을 두고, 매 반복마다 `t1` 을 저장한 뒤 한 칸씩 앞으로 밉니다.

```asm
    li t0, 0x80400000     # 저장 주소 (lui 한 개로 번역)
    li t1, 1              # F(n)
    li t2, 1              # F(n+1)
    li t3, 10             # 남은 개수
loop:
    sw t1, 0(t0)          # F(n) 저장
    add t4, t1, t2        # F(n+2)
    mv t1, t2
    mv t2, t4
    addi t0, t0, 4
    addi t3, t3, -1
    bne t3, zero, loop
    jr ra
```

실행 및 확인:

```
>> F
>>file name: cod-lab1/src/fib10.s
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
0x80400024: 0x00000037
```

1, 1, 2, 3, 5, 8, 13, 21, 34, 55 로 정확합니다.

### 2.2 ASCII 가시 문자 출력 (`src/ascii.s`)

```asm
    mv s1, ra             # jal 이 ra 를 덮어쓰므로 감독 프로그램 복귀 주소 보존
    li s2, 0x21           # 현재 문자
    li s3, 0x7F           # 끝(미포함)
loop:
    mv a0, s2
    jal WRITE_SERIAL      # t0, t1 이 파괴됨 → 루프 변수는 s 레지스터에 둠
    addi s2, s2, 1
    bne s2, s3, loop
    mv ra, s1
    jr ra
WRITE_SERIAL:             # 실험 문서에서 제공한 함수
    li t0, 0x10000000
.TESTW:
    lb t1, 5(t0)          # LSR
    andi t1, t1, 0x20     # THRE: 송신 가능?
    beq t1, zero, .TESTW
.WSERIAL:
    sb a0, 0(t0)          # THR 에 한 바이트 기록
    jr ra
```

주의점:
- `jal WRITE_SERIAL` 이 `ra` 를 바꾸므로, 마지막 `jr ra` 가 감독 프로그램으로 돌아가려면 원래 `ra` 를 따로 저장해야 합니다(여기서는 `s1`). 기본 버전 kernel 은 사용자 프로그램 종료 후 모든 레지스터를 `uregs` 에 저장하므로 s 레지스터를 써도 문제없습니다.
- 출력 범위 0x21~0x7E 는 term 이 제어 신호로 쓰는 0x06/0x07/0x80/0x81 과 겹치지 않으므로 term 이 그대로 화면에 출력합니다.

실행 결과:

```
>> G
addr: 0x80100000
!"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz{|}~
elapsed time: 0.001s
```

### 2.3 60번째 Fibonacci 수 (`src/fib60.s`)

F(60) = 1 548 008 755 920 = `0x0000_0168_6C83_12D0` 로 32비트를 넘으므로 64비트 정수를 두 개의 32비트 레지스터 `{hi, lo}` 로 표현합니다.

- a = `{t1, t0}`, b = `{t3, t2}`, c = a + b = `{t6, t5}`
- 하위 32비트: `c_lo = a_lo + b_lo`
- 상위 32비트: `c_hi = a_hi + b_hi + carry`

보통 carry 는 `sltu carry, c_lo, a_lo` 한 줄로 구하지만 `sltu` 는 19개 명령어에 없습니다. 그래서 전가산기의 최상위 비트 carry-out 식을 비트 연산으로 계산했습니다.

```
carry = MSB( (a & b) | ((a | b) & ~sum) )
```

(두 최상위 비트가 모두 1이면 반드시 carry, 하나만 1이면 합의 최상위 비트가 0 이 되었을 때 carry.) `~sum` 은 `xor sum, sum, -1` 로 구합니다.

```asm
    li t0, 1              # a = F(1) = {t1, t0}
    li t1, 0
    li t2, 1              # b = F(2) = {t3, t2}
    li t3, 0
    li t4, 58             # 58번 더하면 b = F(60)
    li s2, -1             # 0xFFFFFFFF, NOT 용
loop:
    add t5, t0, t2        # c_lo
    and a1, t0, t2        # a & b
    or  a2, t0, t2        # a | b
    xor a3, t5, s2        # ~c_lo
    and a2, a2, a3
    or  a1, a1, a2
    srli a1, a1, 31       # carry (0/1)
    add t6, t1, t3
    add t6, t6, a1        # c_hi
    mv t0, t2             # a = b
    mv t1, t3
    mv t2, t5             # b = c
    mv t3, t6
    addi t4, t4, -1
    bne t4, zero, loop
    li a0, 0x80400000
    sw t2, 0(a0)          # 리틀 엔디언: 하위 word 먼저
    sw t3, 4(a0)
    jr ra
```

확인:

```
>> D
addr: 0x80400000
num: 8
0x80400000: 0x6c8312d0
0x80400004: 0x00000168
```

→ `0x000001686C8312D0` = 1548008755920 = F(60). ✔

---

## 3. 감독 프로그램(kernel)과 Term 코드 분석

### 3.1 전체 구조

```
 ┌────────── PC (host) ──────────┐          ┌──────── Thinpad / QEMU ────────┐
 │ term.py                        │  UART    │ kernel (RISC-V asm)             │
 │  ├ MainLoop: 명령 입력          │◀───────▶│  init.S : START → 초기화 → WELCOME│
 │  ├ run_A/F: riscv-as 로 어셈블  │  (QEMU:  │  shell.S: SHELL 명령 루프        │
 │  ├ run_U : riscv-objdump 역어셈 │ tcp:6666)│  utils.S: 직렬 포트 읽기/쓰기     │
 │  └ run_R/D/G: 결과 표시/계시    │          │  test.S : UTEST_* 테스트 프로그램 │
 └───────────────────────────────┘          └─────────────────────────────────┘
```

**메모리 배치** (README / `kern/kernel32.ld`)

| 주소 | 용도 |
| --- | --- |
| 0x80000000–0x800FFFFF | kernel 코드 (`.text`, 진입점 `START`) |
| 0x80100000–0x803FFFFF | 사용자 코드 |
| 0x80400000–0x807EFFFF | 사용자 데이터 |
| 0x807F0000–0x807FFFFF | kernel 데이터 (`.bss`: `uregs`, TCBT 등), 커널 스택 top = 0x80800000 |
| 0x10000000–0x10000007 | UART 16550 레지스터 |

### 3.2 Kernel 흐름

1. **`START` (`kern/init.S:99`)**: BSS 초기화 → (EN_INT 시 mtvec/mie 설정) → 커널 스택 `sp = KERNEL_STACK_INIT` → 사용자 `sp`, `fp` 초기값(0x807F0000)을 `uregs` 에 기록 → UART16550 초기화(`init.S:143~163`) → TCBT/중단 프레임 공간 확보 → `WELCOME`.
2. **`WELCOME` (`init.S:389`)**: `monitor_version` 문자열 `"MONITOR for RISC-V - initialized."` 을 `WRITE_SERIAL_STRING` 으로 출력 후 `SHELL` 로.
3. **`SHELL` (`kern/shell.S:21`)**: `READ_SERIAL` 로 명령 한 바이트를 읽어 분기.
   - `R` (`.OP_R`): `uregs` 의 31×XLEN 바이트를 그대로 직렬 포트로 전송.
   - `D` (`.OP_D`): 주소, 길이(각 XLEN 바이트, 리틀 엔디언) 수신 → 해당 메모리를 바이트 단위로 전송.
   - `A` (`.OP_A`): 주소, 길이 수신 → 4바이트씩 `READ_SERIAL_WORD` 로 받아 `sw` 로 메모리 기록.
   - `G` (`.OP_G`, `shell.S:165`): 주소 수신 → `0x06` 전송 → `uregs` 에서 사용자 레지스터 복원 → `ra = .USERRET2`, `jr s10` 으로 사용자 코드 진입 → 사용자 `jr ra` 로 `.USERRET2`(`shell.S:297`) 복귀 → 레지스터를 `uregs` 에 저장, 커널 `sp` 복원 → `0x07` 전송.
   - `T`: 페이지 테이블 주소 전송(기본 버전은 -1).
   - 그 밖의 문자: XLEN(4 또는 8) 한 바이트 전송.
   - `.DONE` → 다시 `SHELL` (무한 루프).

### 3.3 Term 흐름

1. `-t host:port`(TCP, QEMU) 또는 `-s COMx`(실제 직렬 포트)로 연결 (`term.py:530~557`).
2. `test_programs()` 로 `riscv64-unknown-elf-as/objdump/objcopy` 존재 확인.
3. `Main()` (`term.py:435`): 환영 메시지 33바이트 수신 → `'W'` 전송하여 XLEN 탐지.
4. `MainLoop()` (`term.py:375`): 사용자 명령마다 입력 버퍼를 비우고(`EmptyBuf`) 해당 `run_X` 호출.
   - `run_A`/`run_F`: 입력한 어셈블리(라벨, 16진 기계어 허용)를 `.org` 와 함께 임시 파일로 모아 `as` → `objcopy -O binary` 로 기계어 생성, 4바이트마다 `'A' + addr + 4 + word` 로 kernel 에 전송.
   - `run_D`/`run_U`: `'D' + addr + num` 전송 후 num 바이트 수신, U 는 각 word 를 `objdump -b binary` 로 역어셈블.
   - `run_R`: `'R'` 전송 후 31×XLEN 바이트 수신해 표 형태로 출력.
   - `run_G`: 아래 사고문제 3 참고.

**통신 프로토콜**: 명령은 ASCII 한 글자, 인자(주소·길이)는 XLEN 바이트 리틀 엔디언 정수(`int_to_byte_string` ↔ `READ_SERIAL_XLEN`), 데이터는 원시 바이트열입니다.

---

## 4. 사고문제 (思考题) 답안

### 4.1 RISC-V 와 x86 의 주소 지정 방식 비교

| 주소 지정 방식 | RISC-V (RV32I) | x86 |
| --- | --- | --- |
| 즉시값 | `addi t0, t0, 5` (12비트 부호 확장), `lui`/`auipc` (상위 20비트) | `mov eax, 5` (8/16/32비트, x86-64 는 64비트 `movabs`) |
| 레지스터 | `add t0, t1, t2` | `add eax, ebx` |
| 직접(절대) 주소 | **없음** — `lui`+`lw` 로 합성 | `mov eax, [0x1234]` |
| 레지스터 간접 | `lw t0, 0(t1)` (오프셋 0 인 base+offset 의 특수형) | `mov eax, [ebx]` |
| 베이스 + 변위 | `lw t0, 8(t1)` — **유일한 메모리 주소 지정 방식** | `mov eax, [ebx+8]` |
| 베이스 + 인덱스×배율 + 변위 | **없음** — `slli`/`add` 로 계산 | `mov eax, [ebx+esi*4+8]` (SIB 바이트) |
| PC 상대 | 분기 `beq`(±4KiB), `jal`(±1MiB), `auipc` | `jmp/call rel8/rel32`, x86-64 `[rip+disp32]` |
| 세그먼트 | 없음 (평면 주소 공간) | `seg:offset` (CS/DS/SS/ES/FS/GS) |
| 암묵적 주소 | 없음 | 스택(`push/pop`: ESP), 문자열 명령(`movs`: ESI/EDI) |

**공통점**
- 즉시값, 레지스터, 베이스+변위, PC 상대 주소 지정을 모두 지원합니다.
- 두 ISA 모두 바이트 주소, 리틀 엔디언이며 분기/호출은 PC 상대 오프셋으로 인코딩됩니다.

**차이점**
1. **Load/Store 구조 vs 메모리 피연산자**: RISC-V 는 `load/store` 만 메모리에 접근하고 연산 명령의 피연산자는 모두 레지스터/즉시값입니다. x86 은 `add eax, [ebx]`, `add [ebx], eax` 처럼 연산 명령이 직접 메모리 피연산자를 가질 수 있습니다.
2. **방식의 수**: RISC-V 의 메모리 주소는 `rs1 + imm12` 한 가지뿐이라 하드웨어(AGU)가 단순하고 파이프라인 설계가 쉽습니다. x86 은 ModR/M + SIB 조합으로 다양한 복합 주소를 한 명령에서 계산합니다.
3. **즉시값/변위 폭과 명령어 길이**: RISC-V 는 32비트 고정 길이라 즉시값이 12비트(I/S형) 또는 20비트(U/J형)로 제한되어 큰 상수·주소는 `lui+addi`, `auipc+addi/jalr` 두 명령으로 만듭니다(`li`, `la`, `call` 가상 명령). x86 은 가변 길이(1~15바이트)여서 32비트 변위/즉시값을 한 명령에 담습니다.
4. **분기 방식**: RISC-V 는 `beq rs1, rs2, offset` 처럼 비교와 분기가 한 명령이고 오프셋은 2바이트 단위입니다. x86 은 `cmp` 로 FLAGS 를 설정한 뒤 `jcc` 가 FLAGS 를 보고 분기합니다.
5. **간접 점프**: RISC-V `jalr rd, imm(rs1)` 은 레지스터+오프셋, x86 `jmp [mem]`/`call [ebx*4+table]` 은 메모리 간접도 가능합니다.
6. **세그먼트, 암묵적 피연산자**: x86 에는 세그먼트 레지스터, 스택/문자열 명령의 암묵적 레지스터 사용이 있지만 RISC-V 에는 없습니다.

### 4.2 감독 프로그램의 19개 명령어와 분류

기본 버전 kernel 이 쓰는 명령어(`make inst` 로 확인 가능):

`ADD ADDI AND ANDI AUIPC BEQ BNE JAL JALR LB LUI LW OR ORI SB SLLI SRLI SW XOR`

**(1) 기능에 따른 분류**

| 분류 | 명령어 | 이유 / kernel 에서의 용도 |
| --- | --- | --- |
| 산술·논리 (레지스터-레지스터) | `ADD`, `AND`, `OR`, `XOR` | 두 레지스터를 ALU 로 연산해 rd 에 기록. `or s1, a0, zero` 로 레지스터 복사, `or a0, a0, s2` 로 바이트 조립 |
| 산술·논리 (레지스터-즉시값) | `ADDI`, `ANDI`, `ORI`, `SLLI`, `SRLI` | 한 피연산자가 12비트 즉시값(시프트는 5비트 shamt). `addi sp, sp, -8`, `li`/`mv`, `andi t1, t1, 0x20`(상태 비트 추출), `srli a0, s0, 8`(바이트 분해) |
| 상위 즉시값 / 주소 생성 | `LUI`, `AUIPC` | 20비트 즉시값을 상위에 둠. `li t0, 0x10000000`(lui), `la a0, monitor_version`(auipc+addi) |
| 메모리 읽기 | `LB`, `LW` | base+offset 으로 메모리→레지스터. `lb t1, 5(t0)` 로 UART LSR, `lw` 로 레지스터 복원 |
| 메모리 쓰기 | `SB`, `SW` | 레지스터→메모리. `sb a0, 0(t0)` 로 UART 송신, `sw` 로 사용자 코드·레지스터 저장 |
| 조건 분기 | `BEQ`, `BNE` | 두 레지스터 비교 후 PC 상대 분기. 명령 디스패치, 루프, 직렬 포트 폴링 |
| 무조건 점프 | `JAL`, `JALR` | `jal` = 함수 호출/`j`, `jalr` = `jr ra`(복귀), `jr s10`(사용자 프로그램 진입) |

**(2) 명령어 형식(인코딩)에 따른 분류**

| 형식 | 명령어 |
| --- | --- |
| R-type | ADD, AND, OR, XOR |
| I-type | ADDI, ANDI, ORI, SLLI, SRLI, LB, LW, JALR |
| S-type | SB, SW |
| B-type | BEQ, BNE |
| U-type | LUI, AUIPC |
| J-type | JAL |

**(3) CPU 구현 관점의 분류 (README 참고)**
데이터 경로가 같은 명령끼리 묶으면 대표 8개만 구현하면 나머지는 ALU 연산 종류나 접근 폭만 바꿔 확장할 수 있습니다.

```
ADD  : ADDI, AND, ANDI, OR, ORI, SLLI, SRLI, XOR   (ALU 연산, 결과 rd 로 되씀)
AUIPC:                                               (PC + imm<<12)
BEQ  : BNE                                           (비교 후 PC+imm)
JAL  :                                               (rd=PC+4, PC+=imm)
JALR :                                               (rd=PC+4, PC=(rs1+imm)&~1)
LB   : LW                                            (메모리 읽기, 폭/부호확장만 다름)
LUI  :                                               (imm<<12)
SB   : SW                                            (메모리 쓰기, 폭/바이트 enable 만 다름)
```

이렇게 나눈 이유: 같은 분류 안의 명령은 **명령어 형식(즉시값 추출 방식)**, **데이터 경로(ALU→레지스터 / 메모리 / PC 갱신)**, **제어 신호**가 동일하고 funct3/funct7 에 따른 ALU 연산 종류나 메모리 접근 폭만 다르기 때문입니다. 이후 5단 파이프라인 CPU 를 설계할 때 디코더와 제어 신호를 이 분류대로 설계하면 됩니다.

### 4.3 Term 은 사용자 프로그램 실행 시간을 어떻게 측정하는가

기본 버전 kernel 은 타이머(CSR `mtime` 등)를 쓰지 않으므로 **시간 측정은 PC 쪽 term 이 하고, kernel 은 시작/종료 신호만 보냅니다.**

신호 정의 (`kernel/include/common.h:14~17`):

```c
#define SIG_TIMERSET    0x06   // ACK, 계시 시작
#define SIG_TIMETOKEN   0x07   // BEL, 계시 종료
#define SIG_FATAL       0x80   // 심각한 오류 (EN_INT)
#define SIG_TIMEOUT     0x81   // 시간 초과 (EN_INT)
```

**kernel 측** (`kern/shell.S`, `.OP_G`)
1. `shell.S:168` `jal READ_SERIAL_XLEN` 으로 사용자 프로그램 주소를 받아 `s10` 에 저장.
2. `shell.S:174~175` `li a0, SIG_TIMERSET; jal WRITE_SERIAL` — **0x06 을 보내 계시 시작을 알림**.
3. `uregs` 에서 사용자 레지스터를 복원하고 `la ra, .USERRET2; jr s10` 으로 사용자 코드 실행.
4. 사용자 프로그램이 `jr ra` 로 `.USERRET2`(`shell.S:297`)에 돌아오면 레지스터를 `uregs` 에 저장, 커널 스택 복원.
5. `shell.S:341~343` `li a0, SIG_TIMETOKEN; jal WRITE_SERIAL` — **0x07 을 보내 종료를 알림**.

**term 측** (`term/term.py:332~372`, `run_G`)
1. `'G'` + 주소(XLEN 바이트)를 전송.
2. 첫 바이트를 읽어 `0x06` 인지 확인 후 `time_start = timer()` (`timeit.default_timer`, 즉 `time.perf_counter`).
3. 루프에서 1바이트씩 읽음: `0x07` 이면 종료, `0x81` 이면 “killed timeout program.”, `0x80` 이면 trap 정보(mepc/mcause/mtval) 수신, 그 외의 바이트는 사용자 프로그램 출력으로 화면에 그대로 출력.
4. `elapse = timer() - time_start` 를 계산해 `elapsed time: %.3fs` 출력.

즉 측정값은 “0x06 을 받은 시점부터 0x07 을 받은 시점까지의 PC 시간”이며, 직렬 전송 지연, 사용자 프로그램이 출력한 문자의 전송 시간, 레지스터 복원/저장 시간이 포함되고 해상도는 ms 단위(출력 형식 기준)입니다. (EN_INT 버전은 추가로 `mtimecmp` 를 설정해 시간 초과 시 `SIG_TIMEOUT` 을 보냅니다, `shell.S:185~204, 264~269`.)

### 4.4 kernel 은 직렬 포트를 어떻게 사용하는가

1. **메모리 맵 I/O**: UART 는 16550 호환 장치로 `COM1 = 0x10000000` (`include/serial.h:5`)에 매핑되어 있고, 일반 `lb/sb` 로 레지스터에 접근합니다.
   - `+0` RBR/THR: 읽으면 수신 데이터, 쓰면 송신 데이터
   - `+5` LSR: bit5 `THRE`(0x20, 송신 가능), bit0 `DR`(0x01, 수신 데이터 있음) (`serial.h:31, 36`)
2. **초기화** (`kern/init.S:143~163`, `ENABLE_UART16550` 일 때): FCR 에 0x7 (FIFO 활성·초기화) → LCR.DLAB=1 → DLL/DLM 에 분주값(115200/9600) → LCR=8N1 (DLAB 해제) → MCR=0 → IER=RDI(수신 인터럽트 허용; 기본 버전에서는 CPU 인터럽트를 켜지 않으므로 실질적으로 폴링).
3. **폴링 방식 송수신** (`kern/utils.S`)
   - `WRITE_SERIAL` (`utils.S:14`): `lb t1, 5(t0)` 로 LSR 을 읽고 `andi 0x20` 이 0 이면 계속 대기(busy wait), 1 이 되면 `sb a0, 0(t0)` 로 a0 하위 바이트 송신.
   - `READ_SERIAL` (`utils.S:78`): LSR bit0(DR) 이 1 이 될 때까지 대기 후 `lb a0, 0(t0)` 로 한 바이트 수신.
4. **상위 함수**
   - `WRITE_SERIAL_WORD / WRITE_SERIAL_XLEN` (`utils.S:25, 54`): 32/XLEN 비트 값을 하위 바이트부터 (리틀 엔디언) 전송.
   - `READ_SERIAL_WORD / READ_SERIAL_XLEN` (`utils.S:89, 126`): 4/XLEN 바이트를 받아 `sll`/`or` 로 조립.
   - `WRITE_SERIAL_STRING` (`utils.S:68`): `\0` 까지 문자열 전송(환영 메시지).
5. **사용처**: SHELL 은 `READ_SERIAL` 로 명령 문자를, `READ_SERIAL_XLEN` 으로 주소/길이를, `READ_SERIAL_WORD` 로 A 명령의 기계어를 받고, `WRITE_SERIAL` 로 메모리/레지스터 바이트, XLEN, 계시 신호(0x06/0x07)를 보냅니다.
6. QEMU 에서는 `make sim` 의 `-serial tcp::6666,server` 옵션으로 가상 UART 가 TCP 소켓에 연결되고, term 의 `tcp_wrapper` 가 이를 직렬 포트처럼 사용합니다.

### 4.5 term 은 kernel 이 올바르게 연결되었는지 어떻게 확인하는가

두 단계로 확인합니다.

**① 환영 메시지 (부팅 확인)**
- kernel: `kern/init.S:90~91` 에 `monitor_version: .asciz "MONITOR for RISC-V - initialized."` (33자)를 정의하고, 초기화가 끝나면 `init.S:389~392` `WELCOME` 에서 `la a0, monitor_version; jal WRITE_SERIAL_STRING` 으로 출력.
- term: `term/term.py:438~440` `Main()` 에서 `output_binary(inp.read(33))` 로 정확히 33바이트를 받아 화면에 출력. (`-c/--continued` 옵션을 주면 이 단계를 건너뜀 — 이미 부팅된 kernel 에 다시 접속할 때 사용.)

**② XLEN 탐지 (명령 응답 확인)**
- term: `term/term.py:442~456` 에서 kernel 이 모르는 명령 `'W'` 를 보내고, 1바이트를 읽어
  - `4` → “running in 32bit, xlen = 4”, `arch='rv32'`
  - `8` → “running in 64bit, xlen = 8”, `arch='rv64'`
  - `< 20` 인 다른 값 → “Got unexpected XLEN” 후 종료
  - `≥ 20` (남아 있던 가시 문자 등) → 무시하고 다음 바이트를 계속 읽음
- kernel: `kern/shell.S:21~41` `SHELL` 에서 `READ_SERIAL` 로 읽은 문자가 R/D/A/G/T 어느 것과도 같지 않으면 `shell.S:37~41` 의

  ```asm
  // 错误的操作符，输出 XLEN，用于区分 RV32 和 RV64
  li a0, XLEN
  jal WRITE_SERIAL
  j .DONE
  ```

  으로 XLEN 한 바이트를 돌려줍니다.

이 응답이 4 또는 8 로 돌아오면 kernel 이 SHELL 루프에서 정상적으로 명령을 받고 응답할 수 있음이 확인되며, 동시에 이후 주소/길이 전송에 쓸 XLEN 과 어셈블러 아키텍처(`-march=rv32i/rv64i`)가 결정됩니다. 이 과정이 끝나야 `MainLoop()` 로 들어갑니다(`term.py:457`).
