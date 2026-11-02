# CBB_CNT_GRAY_UG

---

## 目录

- [1. 功能及应用场景](#1-功能及应用场景)
- [2. 规格](#2-规格)
- [3. 方案分析](#3-方案分析)
- [4. 配置参数](#4-配置参数)
- [5. 接口](#5-接口)
- [6. 时序图](#6-时序图)
- [7. PPA](#7-ppa)
- [8. 验证策略](#8-验证策略)

---

## 1. 功能及应用场景

### 1.1 核心功能 — DS.CBB_CNT_GRAY.FUNC.001
面向跨时钟域（CDC）场景的专用同步计数器。内部以二进制加法器为计数核心，并在输出级
寄存格雷码。核心特性：
- 二进制计数核心 `bin_cnt`（已寄存的加法器输出）
- 格雷码寄存输出 `q_gray`，转换输入为加法器输出 `next_val`（非 bin_cnt 寄存器）
- `bin_cnt` 与 `gray_reg` 在同一时钟沿寄存，**零周期偏差**（zero cycle skew）
- 相邻两个计数值的 `q_gray` 仅翻转 1 bit（Hamming distance = 1）
- 计数使能 `en`、加法回绕到 0

### 1.2 应用场景 — DS.CBB_CNT_GRAY.FUNC.002
| 场景 | 说明 |
|------|------|
| 异步 FIFO 读写指针 | 跨域同步前用格雷码消除多比特亚稳态 |
| CDC 跨域同步 | 二进制指针的格雷化后接 2 级 DFF 同步器 |
| 异步握手状态计数 | 跨域握手信号的事件计数 |
| 跨域事件计数器 | 跨时钟域统计脉冲数 |

### 1.3 为何使用格雷码 — DS.CBB_CNT_GRAY.FUNC.003
跨时钟域同步多比特二进制时，不同 bit 走不同布线延迟，采样瞬间可能捕获到
"中间态"（如 `011 → 100` 时可能采到 `000/111/001/...` ），引发亚稳态与
功能错误。格雷码相邻值仅 1 bit 翻转，同步器只需保证单比特稳定，从结构上
消除多比特同步风险。

---

## 2. 规格

### 2.1 计数方向 — DS.CBB_CNT_GRAY.FUNC.004
固定为加 1 计数（Up only）。无 dir 信号。

### 2.2 控制优先级 — DS.CBB_CNT_GRAY.FUNC.005
```
rst_n (最高) > en > hold
```

### 2.3 复位行为 — DS.CBB_CNT_GRAY.FUNC.006
异步低复位。复位后：
- `bin_cnt = 0`
- `q_bin  = 0`
- `q_gray = 0`

### 2.4 溢出行为 — DS.CBB_CNT_GRAY.FUNC.007
固定回绕模式。加到 `2^WIDTH - 1`（MAX）后再加自动回绕到 0。

### 2.5 格雷码转换 — DS.CBB_CNT_GRAY.FUNC.008
- 公式：`gray[i] = next_val[i] ^ next_val[i+1]`，`gray[MSB] = next_val[MSB]`
- 转换输入：加法器输出 `next_val`（= `bin_cnt + 1` 或回绕 0），非 bin_cnt 寄存器
- 实现：`gray_next = next_val ^ (next_val >> 1); always @(posedge clk) gray_reg <= gray_next;`
- `bin_cnt` 与 `gray_reg` 在同一时钟沿寄存，**零周期偏差**（zero cycle skew）
- `q_gray` 为寄存输出，与 `q_bin` 同拍更新

### 2.6 单比特翻转特性 — DS.CBB_CNT_GRAY.FUNC.009
对于任意 N，`gray(N)` 与 `gray(N+1)` 的 Hamming 距离恒为 1。本模块每拍
`q_gray` 与上一拍 `q_gray` 仅差 1 bit（前提：`en=1 && rst_n=1`）。
此性质是本模块作为 CDC 指针的根本依据，由 TB TC7 显式验证。

---

## 3. 方案分析

### 3.1 原理
格雷码计数器的标准实现 = 二进制计数核心 + 格雷码寄存器：

```
            ┌──────────────────┐
            │  next_val = +1   │──┬──▶ bin_cnt (reg) ──▶ q_bin
            │   or wrap to 0   │  │
            └──────────────────┘  │
                                  └─▶ XOR ──▶ gray_next ──▶ gray_reg ──▶ q_gray
                                  (next_val >> 1)              ↑
                                                        clk ↑ (同沿寄存)
```

### 3.2 关键设计点：转换逻辑输入选择 — DS.CBB_CNT_GRAY.PERF.001
两种可能实现：

| 方案 | 实现 | 延迟 | 评价 |
|------|------|------|------|
| **A（选定）** | `gray_next = next_val ^ (next_val >> 1); always @(posedge clk) gray_reg <= gray_next;` | 寄存输出，与 bin_cnt 零周期偏差 | 转换输入为加法器输出 next_val，bin_cnt 与 gray_reg 同沿寄存 |
| B（禁用） | `assign q_gray = bin_cnt ^ (bin_cnt >> 1);` | 组合输出 | 转换输入为 bin_cnt 寄存器，组合路径暴露给下游，不利于时序收敛 |

**方案 A 满足规格要求**："二进制加法器输出暂存为 bin_cnt，格雷码转换电路输入应为
加法器输出而非 bin_cnt 输出" —— 转换电路对加法器输出 `next_val` 做组合，结果与
`bin_cnt` 在同一时钟沿寄存，保证 `q_gray` 与 `q_bin` 零周期偏差。

### 3.3 加法器实现 — RCA
`bin_cnt + 1` 默认综合为 RCA（Ripple Carry Adder），进位链 LSB→MSB：

```
cin[0] ─▶ FA[0] ─▶ carry[0] ─▶ FA[1] ─▶ ... ─▶ FA[N-1]
```

### 3.4 多种实现方法对比
| 方案 | 关键路径 | 适合位宽 | 备注 |
|------|---------|---------|------|
| **RCA（默认）** | N 级 FA 串行 | ≤ 16 bit | 本模块选用 |
| CLA (Carry Lookahead) | log(N) 级 | 16~64 bit | 面积换速度 |
| Prefix Adder | log(N) 级 | ≥ 32 bit | 高性能场景 |
| LFSR + Gray 映射 | 1 级 | 任意 | 非顺序，不适合地址 |

### 3.5 选定方法
RCA + 寄存格雷转换。关键路径 = RCA 进位链 + XOR 链 + 1 DFF，频率随位宽提升下降。

### 3.6 详细设计
- 边界检测组合：`at_max = (bin_cnt == MAX)`
- next_val 组合：MAX 时回绕到 0，否则 `bin_cnt + 1`
- gray_next 组合：`next_val ^ (next_val >> 1)`
- 时序逻辑：`bin_cnt` 与 `gray_reg` 在同一 posedge 寄存，rst_n > en > hold
- `q_bin`/`q_gray` 均为寄存输出，零周期偏差

---

## 4. 配置参数

| 参数 | 配置范围 | 默认值 | 描述 |
|------|---------|--------|------|
| WIDTH | ≥ 2 | 8 | 计数器位宽 |

**默认赋值说明**：
- `WIDTH=8`：匹配异步 FIFO 常用地址位宽，CDC 场景通用配置

---

## 5. 接口

| 信号名 | 位宽 | I/O | 时钟域 | 类型 | 默认值/复位值 | 描述 |
|--------|------|-----|--------|------|--------------|------|
| clk      | 1 | I | clk  | - | - | 系统时钟 |
| rst_n    | 1 | I | -    | 异步 | - | 异步复位，低有效 |
| en       | 1 | I | clk  | - | - | 计数使能 |
| q_bin    | WIDTH | O | clk | **寄存输出** | **0** | 二进制计数值输出 |
| q_gray   | WIDTH | O | clk | **寄存输出** | **0** | 格雷码计数值输出（与 q_bin 零周期偏差） |

### 5.1 输出类型说明

- `q_bin` 为寄存输出：内部 `bin_cnt` 寄存器直接引出
- `q_gray` 为寄存输出：`gray_reg` 寄存器引出，转换输入为加法器输出 `next_val`，与 `q_bin` 同拍更新（零周期偏差）

### 5.2 输出默认值/复位值

| 状态 | q_bin | q_gray | 原因 |
|------|-------|--------|------|
| 复位期间（rst_n=0） | 0 | 0 | 异步复位 |
| 复位释放后 | 0 | 0 | 从 0 开始计数 |
| 计数中 | 0~MAX | gray(bin) | 正常计数 |
| 边界（bin=MAX, en=1） | MAX | gray(MAX) | 下一拍回绕 |
| 回绕后 | 0 | 0 | 下一拍 bin=0 |

### 5.3 接口时序约束

本模块为同步时序逻辑，所有寄存器在 `clk` 上升沿采样：

| 约束项 | 要求 | 说明 |
|--------|------|------|
| clk 周期 | 由 SDC `create_clock` 约束 | 典型 1 ns（1 GHz）@12nm, WIDTH=8 |
| setup | en 相对 clk 上升沿 ≥ Tsu | 典型 0.2 ns |
| hold | en 相对 clk 上升沿 ≥ Th | 典型 0.05 ns |
| Tco | `q_bin`/`q_gray` 寄存器输出 clk→Q 延迟 | 典型 0.2 ns，两者同拍更新 |
| rst_n 异步释放 | rst_n 释放需同步化 | 异步复位，同步释放（建议在 CRG 模块完成） |
| CDC 同步链 | `q_gray` 跨时钟域前需经 2~3 级 DFF 同步 | 单比特翻转特性保证同步安全 |
| gray→bin 转换 | 接收侧需 XOR 前缀和还原：`bin[i] = gray[i] ^ gray[i+1] ^ ... ^ gray[MSB]` | 组合转换，建议在同步器后完成 |

> **CDC 使用要点**：`q_gray` 相邻拍仅 1 bit 翻转，跨域同步器只需保证单比特稳定；
> 接收侧经 2~3 级同步后做 XOR 前缀和还原为二进制（`bin[MSB]=gray[MSB]; bin[i]=bin[i+1]^gray[i]`）。禁止直接跨域同步 `q_bin`。

---

## 6. 时序图

### 6.1 加法计数 + 回绕（WIDTH=8）— DS.CBB_CNT_GRAY.INTF.001
```
clk    __|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
en     ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
bin    00 01 02 03 ... FE FF 00 01 02 ...
gray   00 01 03 02 ... 81 80 00 01 03 ...
                              ▲
                              └── bin=FF 后下一拍回绕到 00
```

### 6.2 单比特翻转示意 — DS.CBB_CNT_GRAY.INTF.002
```
bin   : 000 → 001 → 010 → 011 → 100 → 101 → ...
gray  : 000 → 001 → 011 → 010 → 110 → 111 → ...
XOR   :   -    001    010    001    100    001   (Hamming = 1)
```
每对相邻 gray 仅 1 bit 翻转 → 适合 CDC 同步。

---

## 7. PPA

### 7.1 配置 A：WIDTH=8, 12nm — DS.CBB_CNT_GRAY.PERF.002
综合数据（DC W-2024.09-SP3, tcbn12ffcllbwp7d5t16p96cpdssgnp0p9v125c SS 0.9V/125°C, 1 ns 约束）：

| 项目 | 数值 |
|------|------|
| 频率 | 1 GHz 收敛（slack MET 0.41 ns，关键路径 = 8 级 RCA + 1 XOR + 1 DFF） |
| 面积 | 21.10 µm²（8 DFF × 2 + 8 FA + 8 XOR，52 cells） |
| 功耗 | 动态 49.6 µW @1 GHz vectorless；漏电 128.0 nW |
| 翻转特性 | 每拍平均翻转 ~1 bit（gray 输出，单比特翻转特性） |

### 7.2 配置 B：WIDTH=4, 12nm

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| WIDTH | 4 | 小位宽，高频场景 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 频率 | 1 GHz 收敛（slack MET 0.41 ns，关键路径 = 4 级 RCA + 1 XOR + 1 DFF） |
| 面积 | 10.09 µm²（4 DFF × 2 + 4 FA + 4 XOR） |
| 功耗 | 动态 36.3 µW @1 GHz vectorless；漏电 61.5 nW |
| 翻转特性 | 每拍平均翻转 ~1 bit（gray 单比特翻转特性） |

### 7.3 配置 C：WIDTH=16, 12nm

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| WIDTH | 16 | 中位宽，异步 FIFO 常用地址位宽 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 频率 | 1 GHz 收敛（slack MET 0.32 ns，关键路径 = 16 级 RCA + 1 XOR + 1 DFF） |
| 面积 | 42.85 µm²（16 DFF × 2 + 16 FA + 16 XOR） |
| 功耗 | 动态 76.1 µW @1 GHz vectorless；漏电 255.5 nW |
| 翻转特性 | 每拍平均翻转 ~1 bit（gray 单比特翻转特性） |

> WIDTH≥16 时 RCA 进位链成为瓶颈，建议改用预定标方案（参见 `cbb_cnt_fast`）。

### 7.4 时序说明

本模块为同步时序逻辑，关键路径 = RCA 进位链 + 格雷转换 XOR 链 + 1 DFF：

- **寄存器输出 Tco**：`q_bin`/`q_gray` 均为寄存器直接引出，Tco 典型 0.2 ns（@12nm）
- **关键路径**（clk→q_bin/q_gray）：
  - `clk ↑ → RCA 进位链（WIDTH 级 FA）→ next_val → XOR 链（1 级）→ gray_reg DFF → q_gray`
  - `clk ↑ → RCA 进位链 → next_val → bin_cnt DFF → q_bin`
  - 两条路径共享 RCA 进位链，gray_reg 多 1 级 XOR，但同拍稳定
  - RCA 进位链延迟 O(WIDTH)，是频率瓶颈
  - XOR 链为 1 级（`next_val ^ (next_val>>1)` 按位异或，不串行）
- **零周期偏差**：`bin_cnt` 与 `gray_reg` 在同一 posedge 寄存，`q_gray` 与 `q_bin` 同拍更新
- **位宽对频率影响**：WIDTH≤32 均可在 1 GHz 收敛（WIDTH=32 slack 仅 0.03 ns，WIDTH=64 临界收敛 0.00 ns），详见 §7.5
- **CDC 时序对齐**：`q_gray` 与 `q_bin` 同拍更新（寄存输出，零周期偏差），跨域同步器采样到的
  gray 值与对应 bin 严格对应
- **时序收敛建议**：WIDTH≥16 时 RCA 进位链过长，建议切预定标方案或插入流水

### 7.5 位宽对频率影响 — DS.CBB_CNT_GRAY.PERF.003
| WIDTH | 关键路径级数 | 1 ns 约束 slack（实测） |
|-------|------------|------------------------|
| 8  | 8 FA + 1 XOR  | MET 0.41 ns |
| 16 | 16 FA + 1 XOR | MET 0.32 ns |
| 32 | 32 FA + 1 XOR | MET 0.03 ns |
| 64 | 64 FA + 1 XOR | MET 0.00 ns（临界） |

> 实测条件：DC W-2024.09-SP3, tcbn12ffcllbwp7d5t16p96cpdssgnp0p9v125c SS 0.9V/125°C, ZeroWireload, 1 ns 约束。
> WIDTH=8 实测：面积 21.10 µm²，动态功耗 49.6 µW vectorless。
> WIDTH≥32 时 RCA 进位链余量趋紧，更宽位宽建议改用预定标方案（参见 cbb_cnt_fast）。

### 7.6 与二进制计数器对比 — DS.CBB_CNT_GRAY.PERF.004
| 项目 | cbb_cnt_bin | cbb_cnt_gray |
|------|-------------|--------------|
| 加减方向 | 双向 | 仅加 |
| 溢出模式 | wrap / sat | wrap only |
| 输出 | 二进制 | 二进制 + 格雷码 |
| XOR 链 | 无 | 有（gray 转换） |
| 单比特翻转 | 否 | 是（适合 CDC） |
| 关键路径 | RCA | RCA + XOR |
| CDC 适用性 | 否（需外接 gray 编码） | 是（直接对接同步器） |

### 7.7 例化示例

```verilog
CBB_CNT_GRAY
   #(
    .WIDTH                             (8                                           )
    )
    U_CBB_CNT_GRAY
    (
    .clk                               (clk                                         ),  // System clock
    .rst_n                             (rst_n                                       ),  // Async reset, low
    .en                                (cnt_en                                      ),  // Count enable
    .q_bin                             (bin_ptr                                     ),  // Binary output
    .q_gray                            (gray_ptr                                    )   // Gray output (for CDC)
    );
```

---

## 8. 验证策略

### 8.1 验证思路

采用 Reference Model + Scoreboard 自检架构：
- TB 内置参考模型（behavioral 二进制计数 + 行为级格雷转换，基于 next_val 寄存）
- 每拍对比 DUT 输出与期望值（`q_bin`/`q_gray`），mismatch 立即报错

### 8.2 关键测试点

| 测试点 | 描述 |
|--------|------|
| 复位行为 | rst_n=0 期间 q_bin/q_gray 全 0；释放后从 0 开始 |
| 加法计数 | en=1，顺序计数 0→1→...→MAX→0 |
| 计数保持 | en=0 时 q_bin 保持不变 |
| 回绕 | 加到 MAX 后下一拍回 0 |
| gray 单比特翻转 | 相邻拍 q_gray Hamming 距离恒为 1（TC7 专属验证） |
| gray 与 bin 对应 | q_gray == gray(q_bin) 每拍成立，零周期偏差 |
| 寄存输出对齐 | q_gray 与 q_bin 同拍更新（均为寄存输出） |
| 位宽遍历 | WIDTH=2/4/8/16 配置参数化 |

### 8.3 激励策略

- 定向用例：覆盖边界值（0、MAX、MAX-1、回绕点）
- 随机用例：1000+ 组随机 en 序列
- 覆盖点：状态翻转、相邻状态 q_gray 1-bit 翻转、q_bin/q_gray 同拍对齐

### 8.4 与 VR 衔接

详细 Feature/TC 规划、覆盖率结果见独立文档 `cbb_cnt_gray_vr.md`。本 UG §8 仅给出验证策略概要。
