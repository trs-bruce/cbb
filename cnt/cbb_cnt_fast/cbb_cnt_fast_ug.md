# CBB_CNT_FAST_UG

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

### 1.1 核心功能 — DS.CBB_CNT_FAST.FUNC.001
基于预定标（Prescaler）架构的参数化高速二进制计数器。将 N 位计数器拆分为：
- 低 `PRE_WIDTH` 位预定标计数器（每周期计数，关键路径短）
- 高 `WIDTH-PRE_WIDTH` 位高位计数器（每 `2^PRE_WIDTH` 拍计数一次，时序松弛）

集成功能：
- 计数使能 `en`
- 整体回绕（wrap）到 0
- 进位脉冲输出 `cout`（每 `2^WIDTH` 拍一次）

### 1.2 应用场景 — DS.CBB_CNT_FAST.PERF.001
| 场景 | 说明 |
|------|------|
| 高速分频 | 低位预定标承担高频翻转，适合 500MHz+ 时钟域 |
| 高频时序生成 | CPU/DSP/NPU 内部分频比、节拍生成 |
| 性能关键路径计数 | 大位宽（16~32）计数器在单时钟域跑高频 |
| 长事件计数 | 高位稀疏更新，整体功耗低 |
| 高速定时器 | SoC 内高性能定时器/看门狗 |

> **与 cbb_cnt_bin 的差异**：`cbb_cnt_bin` 关键路径 = N 级 RCA，位宽↑则频率↓；`cbb_cnt_fast` 关键路径固定为 `PRE_WIDTH` 级 RCA，与 `WIDTH` 解耦，适合大位宽高频场景。

---

## 2. 规格

### 2.1 控制优先级 — DS.CBB_CNT_FAST.FUNC.002
```
rst_n (最高) > en > hold
```

### 2.2 复位行为 — DS.CBB_CNT_FAST.FUNC.003
异步低复位。复位后 `q = 0`，`cout = 0`。

### 2.3 计数行为 — DS.CBB_CNT_FAST.FUNC.004
| en | 行为 |
|----|------|
| 0  | 保持当前 q |
| 1  | 低位每拍 +1；高位在低位回绕时 +1 |

回绕规则：
- 低位 `pre_cnt` 从 `PRE_MAX` 加 1 → 回到 0（每 `2^PRE_WIDTH` 拍一次）
- 高位 `high_cnt` 从 `HIGH_MAX` 加 1 → 回到 0（每 `2^WIDTH` 拍一次）
- 整体 q 从 `CNT_MAX` 加 1 → 回到 0（每 `2^WIDTH` 拍一次）

### 2.4 进位输出 — DS.CBB_CNT_FAST.FUNC.005
`cout` 在 `q == 全 1` 且 `en == 1` 时拉高 1 拍（即"将要整体回绕"的那拍）。`en=0` 时即使 `q==全 1` 也不拉高（无 wrap 动作）。

### 2.5 参数约束 — DS.CBB_CNT_FAST.CFG.001
- `WIDTH >= 2`
- `1 <= PRE_WIDTH < WIDTH`
- 默认 `WIDTH=16, PRE_WIDTH=4`：低位 4 位 RCA，高位 12 位（每 16 拍更新一次）

---

## 3. 方案分析

### 3.1 原理
预定标核心思想：**让快的部分（低位）频繁翻转，让慢的部分（高位）少翻转**。
- 低位关键路径短（如 4 位 RCA），可以跑很高频率。
- 高位虽然位宽大但每 `2^PRE_WIDTH` 拍才更新一次，时序松弛。

```
                 ┌─────────────────────┐
                 │   q[WIDTH-1:0]      │
                 │   = {high,pre}      │
                 │                     │
                 │  │     │            │
                 │  ▼     ▼            │
                 │ pre_cnt  high_cnt   │
                 │ (PRE_W)  (HIGH_W)   │
                 │  │ ▲     │  ▲       │
                 │  │ │     │  │       │
                 │  │ └─────┘  │       │
                 │  │ pre_wrap │       │
                 │  │ (en&max) │       │
                 │  ▼          ▼       │
                 │  +1    +1 (gated)   │
                 └─────────────────────┘
                       │
                       ▼
                      cout (q==全1 && en)
```

### 3.2 关键路径分析 — DS.CBB_CNT_FAST.PERF.002
| 路径 | 级数 | 频率影响 |
|------|------|----------|
| 低位 `pre_cnt` +1 | `PRE_WIDTH` 级 FA + 1 MUX + 1 DFF | **决定 fmax**（短） |
| 高位 `high_cnt` +1 | `HIGH_WIDTH` 级 FA + 1 MUX + 1 DFF | 每 `2^PRE_WIDTH` 拍才需满足，时序裕量大 |
| `cout` 组合 | 1 比较 + 1 与门 | 寄存器前短路径 |

对比 N 位纯 RCA（`cbb_cnt_bin`）：关键路径 = N 级 FA。本模块关键路径 = `PRE_WIDTH` 级 FA，**与 WIDTH 解耦**。

### 3.3 多种实现方法对比
| 方案 | 关键路径 | 适合位宽 | 备注 |
|------|---------|---------|------|
| 纯 RCA（`cbb_cnt_bin`） | N 级 FA | ≤ 16 bit | 简单，频率随位宽下降 |
| CLA (Carry Lookahead) | log(N) 级 | 16~64 bit | 面积换速度 |
| Prefix Adder (Kogge-Stone) | log(N) 级 | ≥ 32 bit | 高性能，面积大 |
| **预定标 Prescaler（本模块）** | 固定 `PRE_WIDTH` 级 | **任意** | 频率与 WIDTH 解耦 |
| 纹波计数器 (Ripple) | 1 级 FA（串行） | 任意 | 速度最快但延迟累积 |

### 3.4 选定方法
**预定标（Prescaler）双计数器级联**：
- 低位 `pre_cnt`：`PRE_WIDTH` 位 RCA，每拍 +1，关键路径 = `PRE_WIDTH` 级 FA
- 高位 `high_cnt`：`HIGH_WIDTH` 位 RCA，由 `pre_wrap` 使能，每 `2^PRE_WIDTH` 拍 +1

### 3.5 详细设计
- 低位 `pre_at_max` 比较器组合输出，`pre_wrap = en && pre_at_max` 作为高位使能
- 高位 `high_at_max` 比较器组合输出
- `q_at_max = pre_at_max && high_at_max`，用于 cout 生成
- `cout = en && q_at_max`（组合输出，无寄存器延迟）
- `q = {high_cnt, pre_cnt}` 直接拼接

---

## 4. 配置参数

| 参数 | 配置范围 | 默认值 | 描述 |
|------|---------|--------|------|
| WIDTH    | ≥ 2          | 16 | 计数器总位宽 |
| PRE_WIDTH | 1 ~ WIDTH-1 | 4  | 预定标低位宽（决定关键路径长度） |

**默认赋值说明**：
- `WIDTH=16`：常见定时器位宽，覆盖 65536 周期范围
- `PRE_WIDTH=4`：低位 4 位 RCA 关键路径短，1 ns 约束收敛；高位 12 位每 16 拍更新一次，时序裕量充足

典型配置：
| 配置 | WIDTH | PRE_WIDTH | 高位宽 | 低位回绕周期 | 适用场景 |
|------|-------|-----------|--------|------------|---------|
| A    | 16    | 4         | 12     | 16 拍      | 通用高速 |
| B    | 16    | 8         | 8      | 256 拍     | 低位更慢、高位更宽 |
| C    | 32    | 4         | 28     | 16 拍      | 大位宽高频 |
| D    | 32    | 8         | 24     | 256 拍     | 大位宽中速 |

---

## 5. 接口

| 信号名 | 位宽 | I/O | 时钟域 | 类型 | 默认值/复位值 | 描述 |
|--------|------|-----|--------|------|--------------|------|
| clk      | 1     | I | clk  | - | - | 系统时钟 |
| rst_n    | 1     | I | -    | 异步 | - | 异步复位，低有效 |
| en       | 1     | I | clk  | - | - | 计数使能 |
| q        | WIDTH | O | clk  | **寄存输出** | **0** | 计数值输出 |
| cout     | 1     | O | clk  | **组合输出** | **0** | 进位脉冲（q==全1 && en） |

### 5.1 输出类型说明

- `q` 为寄存输出：`{high_cnt, pre_cnt}` 拼接寄存器直接输出
- `cout` 为组合输出：`en & q_at_max`，脉宽 1 拍

### 5.2 输出默认值/复位值

| 状态 | q | cout | 原因 |
|------|---|------|------|
| 复位期间（rst_n=0） | 0 | 0 | 异步复位 |
| 复位释放后 | 0 | 0 | 从 0 开始计数 |
| 计数中 | 0~CNT_MAX | 0 | 正常计数 |
| 边界（q=全1, en=1） | 全1 | 1 | 进位脉冲 |
| 回绕后 | 0 | 0 | 下一拍 q=0 |

### 5.3 接口时序约束

本模块为同步时序逻辑，所有寄存器在 `clk` 上升沿采样：

| 约束项 | 要求 | 说明 |
|--------|------|------|
| clk 周期 | 由 SDC `create_clock` 约束 | 典型 1 ns（1 GHz）@TSMC 12nm, PRE_WIDTH=4 |
| setup | en 相对 clk 上升沿 ≥ Tsu | 典型 0.2 ns |
| hold | en 相对 clk 上升沿 ≥ Th | 典型 0.05 ns |
| Tco | `q` 寄存器输出 clk→Q 延迟 | 典型 0.2 ns |
| Tpd (组合) | `cout` 组合输出延迟 | Tco + 1 级比较 + 1 级与门 |
| rst_n 异步释放 | rst_n 释放需同步化 | 异步复位，同步释放（建议在 CRG 模块完成） |
| 预定标级时序 | 低位 `pre_cnt` 每拍 +1，关键路径 = PRE_WIDTH 级 FA | 决定 fmax，与 WIDTH 解耦 |
| 高位级时序 | 高位 `high_cnt` 每 2^PRE_WIDTH 拍 +1 | 时序裕量充足，不受 fmax 约束 |

> **两级时序特性**：低位预定标级（`pre_cnt`）为关键路径，决定 fmax；高位级（`high_cnt`）
> 由 `pre_wrap` 使能，每 `2^PRE_WIDTH` 拍才需满足时序，裕量大。fmax 仅依赖 PRE_WIDTH，与 WIDTH 解耦。

---

## 6. 时序图

### 6.1 加法计数 + 低位回绕（WIDTH=16, PRE_WIDTH=4）
```
clk   __|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
en    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
q(low)  0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F  0  1  2  3 ...
q(high) 0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  1  1  1  1 ...
                                   ↑ pre_wrap     ↑ pre_wrap
q      0000 0001 ... 000E 000F 0010 0011 ...
cout   0    0    ... 0     0     0     0    ...     ← 仅在 q=FFFF 才拉高
```

### 6.2 整体回绕（从 0xFFF0 计数 16 拍到 0xFFFF，再 1 拍回绕）
```
q      FFF0 FFF1 ... FFFF 0000 0001 ...
cout   0    0    ... 1    0    0         ← 仅在 q=FFFF 那拍拉高
```

---

## 7. PPA

### 7.1 配置 A：WIDTH=16, PRE_WIDTH=4, TSMC 12nm — DS.CBB_CNT_FAST.PERF.003
综合数据（DC W-2024.09-SP3, tcbn12ffcllbwp7d5t16p96cpdssgnp0p9v125c SS 0.9V/125°C, 1 ns 约束）：

| 项目 | 数值 |
|------|------|
| 关键路径 | 4 级 FA + 1 MUX + 1 DFF（低位预定标），与 WIDTH 解耦 |
| 频率 | 1 GHz 收敛（slack MET 0.07 ns，瓶颈为 en→cout 输入输出组合路径） |
| 面积 | 24.33 µm² |
| 功耗 | 动态 26.6 µW @1 GHz vectorless；高位每 16 拍翻转一次，平均翻转 ~5 bit/拍 |

### 7.2 配置 B：WIDTH=16, PRE_WIDTH=8
综合数据（同上条件, 1 ns 约束）：

| 项目 | 数值 |
|------|------|
| 关键路径 | 8 级 FA + 1 MUX + 1 DFF（低位预定标） |
| 频率 | 1 GHz 收敛（slack MET 0.10 ns） |
| 面积 | 24.42 µm² |
| 功耗 | 动态 32.9 µW @1 GHz vectorless；高位每 256 拍翻转一次，平均翻转 ~9 bit/拍 |

### 7.3 配置 C：WIDTH=32, PRE_WIDTH=4, TSMC 12nm

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| WIDTH | 32 | 大位宽，长计数范围 |
| PRE_WIDTH | 4 | 低位 4 位 RCA，关键路径与配置 A 相同 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 关键路径 | 4 级 FA + 1 MUX + 1 DFF（低位预定标） |
| 频率 | 1 GHz 收敛（slack MET 0.00 ns 临界，与配置 A 相同，与 WIDTH 解耦） |
| 面积 | 49.81 µm² |
| 功耗 | 动态 27.4 µW @1 GHz vectorless；高位每 16 拍翻转一次，平均翻转 ~5 bit/拍 |

> **核心优势**：WIDTH=32 仍可 1 GHz 收敛，fmax 仅由 PRE_WIDTH 决定。

### 7.4 时序说明

本模块为同步时序逻辑，关键路径 = 预定标级（低位 `pre_cnt`）的 RCA 进位链：

- **寄存器输出 Tco**：`q = {high_cnt, pre_cnt}` 拼接寄存器直接输出，Tco 典型 0.2 ns（@TSMC 12nm）
- **组合输出 Tpd**：`cout = en & q_at_max`：Tco + 1 级比较 + 1 级与门
- **关键路径**（clk→q 低位）：
  - `clk ↑ → pre_cnt 寄存器 → PRE_WIDTH 级 RCA 进位链 → 1 MUX → pre_cnt`（自循环 +1）
  - 关键路径级数 = PRE_WIDTH 级 FA + 1 MUX + 1 DFF，**与 WIDTH 解耦**
- **进位跳过特性**：
  - 低位 `pre_wrap = en & pre_at_max` 作为高位使能，每 `2^PRE_WIDTH` 拍触发一次
  - 高位 `high_cnt` 的 RCA 进位链（HIGH_WIDTH 级）有 `2^PRE_WIDTH` 拍时序裕量，不构成关键路径
  - 这就是"预定标"的本质：用低位承担高频翻转，高位稀疏更新
- **fmax 与位宽关系**：WIDTH=8/16/32/64 在 PRE_WIDTH=4 时 1 ns 约束均收敛（详见 §7.6）
- **时序收敛建议**：PRE_WIDTH 选 4 或 8（1 ns 约束下实测 slack 分别 0.07/0.10 ns）即可覆盖大多数场景；
  WIDTH 增大不影响 fmax，仅增大面积

### 7.5 PRE_WIDTH 对 fmax 影响（WIDTH=16）
| PRE_WIDTH | 关键路径级数 | 1 ns 约束 slack（实测） | 高位更新周期 |
|-----------|------------|------------------------|-------------|
| 2 | 2 FA  | MET 0.04 ns | 4 拍 |
| 4 | 4 FA  | MET 0.07 ns | 16 拍 |
| 8 | 8 FA  | MET 0.10 ns | 256 拍 |
| 12 | 12 FA | MET 0.03 ns | 4096 拍 |

### 7.6 位宽对 fmax 影响（PRE_WIDTH=4 固定）
| WIDTH | 关键路径级数 | 1 ns 约束 slack（实测，PRE_WIDTH=4） |
|-------|------------|--------------------------------------|
| 8  | 4 FA | MET 0.09 ns |
| 16 | 4 FA | MET 0.07 ns |
| 32 | 4 FA | MET 0.00 ns（临界） |
| 64 | 4 FA | MET 0.00 ns（临界） |

> **核心优势**：fmax 仅由 PRE_WIDTH 决定，与 WIDTH 解耦。WIDTH=64 仍可 1 ns 收敛（PRE_WIDTH=4）。
> 实测条件：DC W-2024.09-SP3, tcbn12ffcllbwp7d5t16p96cpdssgnp0p9v125c SS 0.9V/125°C, ZeroWireload, 1 ns 约束。
> WIDTH=8/PW=4 实测：面积 13.36 µm²，动态功耗 26.5 µW vectorless；关键路径为 en→cout 输入输出组合路径。

---

## 8. 验证策略

### 8.1 验证思路

采用 Reference Model + Scoreboard 自检架构：
- TB 内置参考模型（behavioral 双计数器级联：pre_cnt + high_cnt）
- 每拍对比 DUT 输出与期望值（`q`/`cout`），mismatch 立即报错

### 8.2 关键测试点

| 测试点 | 描述 |
|--------|------|
| 复位行为 | rst_n=0 期间 q/cout 全 0；释放后从 0 开始 |
| 加法计数 | en=1，低位每拍 +1 |
| 计数保持 | en=0 时 q 保持不变 |
| 低位回绕 | pre_cnt 从 PRE_MAX 加 1 → 回 0，触发 pre_wrap |
| 高位进位 | pre_wrap 触发 high_cnt +1，每 2^PRE_WIDTH 拍一次 |
| 整体回绕 | q 从 CNT_MAX 加 1 → 回 0，cout 在全 1 拍拉高 |
| cout 脉冲 | 仅在 q==全1 && en=1 时拉高，en=0 不拉高 |
| 预定标切换 | 不同 PRE_WIDTH 配置下验证进位周期 |
| 位宽遍历 | WIDTH=8/16/32, PRE_WIDTH=2/4/8 配置参数化 |

### 8.3 激励策略

- 定向用例：覆盖边界值（0、全 1、低位 MAX、高位 MAX、回绕点）
- 随机用例：1000+ 组随机 en 序列
- 覆盖点：pre_cnt 回绕、high_cnt 进位、cout 触发、pre_wrap 与 en 时序

### 8.4 与 VR 衔接

详细 Feature/TC 规划、覆盖率结果见独立文档 `cbb_cnt_fast_vr.md`。本 UG §8 仅给出验证策略概要。
