# CBB_CNT_CASCADE_UG

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

### 1.1 核心功能 — DS.CBB_CNT_CASCADE.FUNC.001
参数化级联计数器。由 `NUM_STAGES` 级 `STAGE_WIDTH` 位二进制上行计数器级联构成，
总位宽 = `STAGE_WIDTH × NUM_STAGES`。低位级溢出时通过进位链自动触发高位级递增，
实现超高位宽计数。集成：
- 计数使能 `en`（顶级）
- 每级进位脉冲 `cout_stage[i]`（内部）
- 复位后所有级 q=0
- 支持 `CASCADE_MODE` 参数切换同步/异步级联模式：
  - `CASCADE_MODE=0`（SYNC）：所有级共享同一 `clk`，进位通过组合逻辑链传递
  - `CASCADE_MODE=1`（ASYNC）：stage 0 由 `clk` 驱动，stage i（i>0）由
    `cout_stage[i-1]` 的下降沿驱动（纹波进位风格）

### 1.2 应用场景 — DS.CBB_CNT_CASCADE.FUNC.002
| 场景 | 说明 |
|------|------|
| 超长周期定时 | 64/128/256-bit 计数器，超长定时周期 |
| 大流量统计 | 网络包计数、总线事务计数 |
| 时间戳计数 | 高精度时间戳生成 |
| 超宽位宽计数 | 位宽扩展灵活，单级 8-bit 4 级 = 32-bit，8 级 = 64-bit |
| 频率分频 | 配合比较器实现超大分频比 |

---

## 2. 规格

### 2.1 级联结构 — DS.CBB_CNT_CASCADE.FUNC.003
- 每级为 `STAGE_WIDTH` 位二进制上行计数器，wrap-around 模式
- 第 0 级（LSB）使能：`en_stage[0] = en`
- 第 i 级使能（SYNC 模式）：`en_stage[i] = en && (&cout_stage[i-1:0])`——**全部低位级**的进位 AND 归约
- 第 i 级 cout：`cout_stage[i] = (q_stage[i] == STAGE_MAX)`（纯电平，不含 `en`）
- 同步级联：所有级共享同一 `clk`，进位通过组合逻辑链传递
- 异步级联：stage 0 由 `clk` 驱动，stage i（i>0）由 `cout_stage[i-1]` 下降沿驱动
- **SYNC 使能必须看全部低位级**：低位级在 MAX 上会持续 `2^STAGE_WIDTH` 个时钟的 cout 高电平（排空期，低一整圈），只看 `cout_stage[i-1]` 会在该窗口内让高位级连续误加，回绕周期缩短为 `2^(STAGE_WIDTH×(NUM_STAGES-1-i))`；AND 归约等价于二进制加法器进到第 `i×STAGE_WIDTH` 位的进位

### 2.2 控制优先级 — DS.CBB_CNT_CASCADE.FUNC.004
```
rst_n (最高) > en_stage[i] > hold
```

### 2.3 复位行为 — DS.CBB_CNT_CASCADE.FUNC.005
异步低复位。复位后所有级 `q_stage[i] = 0`，输出 `q = 0`。

### 2.4 级联模式选择 — DS.CBB_CNT_CASCADE.CFG.001
| CASCADE_MODE | 模式 | 进位方式 | 适用场景 |
|--------------|------|---------|---------|
| 0 (默认) | SYNC 同步 | 组合逻辑链，所有级同 `clk` | 级数 ≤ 4，fmax 要求中等 |
| 1 | ASYNC 异步 | 下降沿进位，stage i 由 `cout_stage[i-1]` 下降沿驱动 | 级数多、对单级 fmax 要求高 |

### 2.5 异步级联原理 — DS.CBB_CNT_CASCADE.FUNC.006
异步模式下采用下降沿进位（falling-edge carry）：
- stage 0 由 `posedge clk` 驱动，按 `en` 计数
- stage i（i>0）由 `negedge cout_stage[i-1]` 驱动
- 选择下降沿而非上升沿的原因：`cout_stage[i-1]` 在 stage i-1 到达 MAX 时拉高，
  回绕时拉低；下降沿对应"stage i-1 完成回绕"事件，时序语义清晰
- 该结构为纹波计数器（Ripple Counter）原理的扩展，每级进位独立时钟，无组合进位链

### 2.6 每级回绕 — DS.CBB_CNT_CASCADE.FUNC.007
每级在 `en_stage[i]=1` 且 `q_stage[i]==STAGE_MAX` 时回绕到 0，并向上一级产生 cout 脉冲。

---

## 3. 方案分析

### 3.1 原理
级联计数器本质是多个低位宽计数器通过进位链组合：

```
        ┌──────────┐    ┌──────────┐         ┌──────────┐
en ─────▶│ Stage 0  │─c0─▶│ Stage 1  │─c1─ ... ─▶│ Stage N-1│
        │ SW bits  │    │ SW bits  │         │ SW bits  │
        └──────────┘    └──────────┘         └──────────┘
```

每级结构：
```
                ┌──────────┐
en_stage[i] ───▶│  q_stage │──▶ q[i*SW +: SW]
                │  register│
                │  +1 /wrap│
   (q==MAX) ──▶│          │──▶ cout_stage[i]
                └──────────┘
```

### 3.2 进位链实现

#### 3.2.1 同步级联（CASCADE_MODE=0，AND-Reduction Carry）
- `cout_stage[i]` 由 `q_stage[i]` 组合比较产生（纯电平，不含 `en`）
- `en_stage[i+1]` 由 `en && (&cout_stage[i:0])` 组合产生——本级只在**全部低位级**都处于 MAX 时加一
- 所有级的 `q_stage` 在同一 posedge 同步更新

关键路径：`q_stage[0..N-1] → cmp → AND 归约树 → en_stage[i] → q_stage[i]`，归约树深度为 `log2(NUM_STAGES)`，而非逐级串行；扇入随级数增长。

为什么不能只看紧邻一级：低位级到达 MAX 后，其 cout 会保持高电平 `2^STAGE_WIDTH` 个时钟（要等更低位走完整整一圈，本级才回落），在这段窗口内上位级若只看 `cout_stage[i-1]`，就会**每个时钟都加一**——高位级在这一个窗口里连加 `2^STAGE_WIDTH` 次，整体回绕周期被截短。AND 归约把"所有低位都满"作为一个整体条件，正是二进制加法器进位到第 `i×STAGE_WIDTH` 位的充要条件。

> 实测（SW=4/NS=3，SYNC）：只看紧邻一级时回绕周期 256（理想 4096），改为 AND 归约后回绕周期精确 4096，66 000 拍逐位比对 0 失配；SW=4/NS=2 两种写法行为完全相同（本级只有一级低位，归约退化为单级）。

#### 3.2.2 异步级联（CASCADE_MODE=1，Falling-edge Carry）
- stage 0 由 `posedge clk` 驱动
- stage i（i>0）由 `negedge cout_stage[i-1]` 驱动
- 无组合进位链，每级独立时钟域（衍生自前级 cout 下降沿）
- 关键路径仅为单级 `cmp + 1 DFF`，fmax 与单级计数器相当

### 3.3 多种实现方法对比
| 方案 | 关键路径 | 适合级数 | 备注 |
|------|---------|---------|------|
| **SYNC AND-Reduction（CASCADE_MODE=0）** | 单级 cmp + log2(N) 级 AND 归约 + 1 DFF | ≤ 8 级 | 默认，结构简单、面积接近 |
| **ASYNC Falling-edge（CASCADE_MODE=1）** | 单级 cmp + 1 DFF | 任意级数 | 纹波进位，fmax 高 |
| Carry Lookahead | log(N) 级 | 8~32 级 | 面积换速度 |
| Prefix Tree | log(N) 级 | ≥ 16 级 | 高性能场景 |

### 3.4 选定方法
提供 SYNC/ASYNC 双模式参数化选择：
- 默认 SYNC（CASCADE_MODE=0）：结构简单，综合友好，无跨时钟域问题
- ASYNC（CASCADE_MODE=1）：级数多时 fmax 优势明显，每级独立时钟避免组合进位链瓶颈

### 3.5 详细设计
- `q_stage[0:NUM_STAGES-1]` 为每级寄存器（unpacked array）
- `en_stage[0:NUM_STAGES-1]` 为每级使能（packed wire vector）
- `cout_stage[0:NUM_STAGES-1]` 为每级 cout（packed wire vector）
- generate for 中每个 stage 包含：`assign en_stage`、`assign cout_stage`、`always STAGE_SEQ_PROC`
- SYNC 模式：所有级 `always @(posedge clk or negedge rst_n)`
- ASYNC 模式：stage 0 `always @(posedge clk or negedge rst_n)`，stage i `always @(negedge cout_stage[i-1] or negedge rst_n)`
- 输出 `q` 通过 `+:` 切片拼接聚集

---

## 4. 配置参数

| 参数 | 配置范围 | 默认值 | 描述 |
|------|---------|--------|------|
| STAGE_WIDTH | ≥ 2 | 8 | 每级位宽 |
| NUM_STAGES | ≥ 1 | 4 | 级联级数（总位宽 = STAGE_WIDTH × NUM_STAGES） |
| CASCADE_MODE | 0 / 1 | 0 | 级联模式：0=同步，1=异步 |

**默认赋值说明**：
- `STAGE_WIDTH=8`：每级用 8 位 RCA，关键路径短
- `NUM_STAGES=4`：4 级级联得 32 位总位宽，覆盖 4.3G 周期，通用定时器场景
- `CASCADE_MODE=0`：默认同步级联，结构简单，综合友好

> **参数组合示例**
> | STAGE_WIDTH | NUM_STAGES | CASCADE_MODE | 总位宽 | 最大计数周期 |
> |-------------|-----------|--------------|--------|-------------|
> | 8 | 4 | 0 | 32 | 2^32 ≈ 4.3 G |
> | 8 | 8 | 1 | 64 | 2^64 ≈ 1.8 E |
> | 4 | 2 | 0 | 8 | 2^8 = 256 |
> | 16 | 4 | 0 | 64 | 2^64 ≈ 1.8 E |

---

## 5. 接口

| 信号名 | 位宽 | I/O | 时钟域 | 类型 | 默认值/复位值 | 描述 |
|--------|------|-----|--------|------|--------------|------|
| clk      | 1 | I | clk  | - | - | 系统时钟 |
| rst_n    | 1 | I | -    | 异步 | - | 异步复位，低有效 |
| en       | 1 | I | clk  | - | - | 顶级计数使能 |
| q        | STAGE_WIDTH×NUM_STAGES | O | clk | **寄存输出** | **0** | 计数值输出 |

### 5.1 输出类型说明

- `q` 为寄存输出：各级 stage_reg 拼接输出

### 5.2 输出默认值/复位值

| 状态 | q | 原因 |
|------|---|------|
| 复位期间（rst_n=0） | 0 | 异步复位 |
| 复位释放后 | 0 | 从 0 开始计数 |
| 计数中 | 0~MAX | 正常计数 |
| 回绕后 | 0 | 所有级达 MAX 后下一拍整体回绕到 0 |

### 5.3 接口时序约束 — DS.CBB_CNT_CASCADE.INTF.001

本模块为同步时序逻辑（CASCADE_MODE=0）或异步级联时序逻辑（CASCADE_MODE=1）：

| 约束项 | 要求 | 说明 |
|--------|------|------|
| clk 周期 | 由 SDC `create_clock` 约束 | 典型 1 ns（1 GHz）@TSMC 12nm，SYNC 模式受级联深度限制 |
| setup | en 相对 clk 上升沿 ≥ Tsu | 典型 0.2 ns |
| hold | en 相对 clk 上升沿 ≥ Th | 典型 0.05 ns |
| Tco | q 寄存输出 clk→Q 延迟 | 典型 0.2 ns |
| rst_n 异步释放 | rst_n 释放需同步化 | 异步复位，同步释放（建议在 CRG 模块完成） |
| SYNC 级联进位链 | `cout_stage[i:0]` → AND 归约 → `en_stage[i+1]` 同拍组合传递 | CASCADE_MODE=0 关键路径，归约深度 log2(NUM_STAGES)，扇入随级数增长 |
| ASYNC 级联进位 | cout_stage[i-1] 下降沿 → stage i 时钟 | CASCADE_MODE=1，每级独立时钟域，无组合进位链 |

> **级间延迟说明**：
> - SYNC 模式（CASCADE_MODE=0）：`en_stage[i]` 由 `en && (&cout_stage[i-1:0])` 组合产生，
>   关键路径为 `q_stage[*] → cmp → AND 归约树 → en_stage[i] → q_stage[i]`，
>   长度 ≈ `cmp + log2(N)` 级。实测 SW=8：NS=2/4/8 关键路径 0.13 / 0.19 / 0.37 ns（含 0.1 ns input delay），
>   1 ns 约束下 slack 分别为 0.75 / 0.69 / 0.52 ns。NUM_STAGES ≥ 16 时建议改用 ASYNC 模式。
> - ASYNC 模式（CASCADE_MODE=1）：无组合进位链，每级独立时钟，fmax 接近单级计数器；
>   但整体回绕延迟 = N 拍（每级进位延迟 1 个 cout 周期），适合对单级 fmax 要求高、
>   对整体回绕延迟不敏感的场景。

---

## 6. 时序图

### 6.1 同步级联计数与进位（CASCADE_MODE=0, STAGE_WIDTH=8, NUM_STAGES=2, 总 16-bit）
```
clk   __|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
en    ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
q[7:0] 00 01 02 ... FE FF 00 01 02 ...   ← stage 0 回绕
q[15:8]00 00 00 ... 00 00 01 01 01 ...   ← stage 1 在 stage 0 回绕后 +1（同拍）
```

### 6.2 异步级联计数与进位（CASCADE_MODE=1, STAGE_WIDTH=8, NUM_STAGES=2, 总 16-bit）
```
clk     __|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
en      ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
q[7:0]  00 01 02 ... FE FF 00 01 02 ...    ← stage 0 由 posedge clk 驱动
cout0   0  0  0  ... 0  1  0  0  0  ...    ← stage 0 达 MAX 时 cout0=1
                                     ↘ 下降沿触发 stage 1
q[15:8] 00 00 00 ... 00 00 01 01 01 ...    ← stage 1 在 cout0 下降沿后 +1
```

### 6.3 整体回绕
```
q_stage[0]   ... FE FF FF FF FF ...      ← stage 0 在 MAX 后回绕
q_stage[1]   ... FE FF FF FF FF ...      ← stage 1 在 stage 0 回绕后进位
                                     ▲
                                     └── 所有级达 MAX 后逐级回绕到 0
```

### 6.4 运行中复位
```
clk   __|‾|_|‾|_|‾|_|‾|_|‾|_
rst_n ‾‾‾‾‾‾‾‾‾‾‾0‾‾‾‾‾‾‾‾‾   ← rst_n 拉低
q     1234 1234 0000 0000   ← 异步立即清零
```

---

## 7. PPA

### 7.1 配置 A：STAGE_WIDTH=8, NUM_STAGES=4, CASCADE_MODE=0 (32-bit), TSMC 12nm
综合数据（DC W-2024.09-SP3, tcbn12ffcllbwp7d5t16p96cpdssgnp0p9v125c SS 0.9V/125°C, 1 ns 约束）：

| 项目 | 数值 |
|------|------|
| 频率 | 1 GHz 收敛（关键路径 = 单级 cmp + 3 级 AND 归约 + 1 DFF，0.19 ns @1 ns 约束） |
| 面积 | 48.15 µm²（116 cells） |
| 功耗 | 动态 39.1 µW @1 GHz vectorless；漏电 312.0 nW |
| 翻转特性 | 每拍平均翻转 ~4 bit（典型计数模式，低 8 位高频翻转） |

### 7.2 配置 B：STAGE_WIDTH=8, NUM_STAGES=8, CASCADE_MODE=1 (64-bit), TSMC 12nm
综合数据（同上条件, 1 ns 约束）：

| 项目 | 数值 |
|------|------|
| 频率 | 1 GHz 收敛（slack MET 0.41 ns，关键路径 = 单级 cmp + 1 DFF，无组合进位链） |
| 面积 | 87.60 µm² |
| 功耗 | 仅低 8 位高频翻转，高位极少翻转，平均功耗低 |

### 7.3 配置 C：STAGE_WIDTH=8, NUM_STAGES=2, CASCADE_MODE=0 (16-bit), TSMC 12nm

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| STAGE_WIDTH | 8 | 每级 8 位 |
| NUM_STAGES | 2 | 2 级级联，总 16 位 |
| CASCADE_MODE | 0 | 同步级联 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 频率 | 1 GHz 收敛（关键路径 = 单级 cmp + 1 级 AND + 1 DFF，0.13 ns @1 ns 约束） |
| 面积 | 23.96 µm² |
| 功耗 | 每拍平均翻转 ~1 bit（低 8 位高频翻转，高位极少） |

> 用于高频小位宽场景（如分频比 ≤ 65536 的快速定时器、短计数窗口统计）。NUM_STAGES=2 时关键路径最短，fmax 接近单级计数器上限。

### 7.4 时序说明

本模块关键路径随 CASCADE_MODE 不同而不同：

- **寄存器输出 Tco**：`q` 为寄存输出，clk→Q 延迟典型 0.2 ns（@TSMC 12nm）
- **SYNC 模式级联进位链传播**：`en_stage[i] = en && (&cout_stage[i-1:0])`，
  关键路径 `q_stage[*] → cmp → AND 归约树 → en_stage[i] → q_stage[i]`，
  深度 ≈ `cmp + log2(NUM_STAGES)`，扇入随级数增长（32-bit/8 级实测 0.37 ns，见 §7.5）
- **ASYNC 模式进位**：无组合进位链，每级独立时钟域，关键路径仅为单级 `cmp + 1 DFF`；
  但整体回绕延迟 = N 拍（每级进位延迟 1 个 cout 周期）
- **setup/hold**：en 相对 clk 上升沿需满足 Tsu/Th（典型 0.2 ns / 0.05 ns）
- **rst_n 异步释放**：异步复位，同步释放需在 CRG 模块完成，避免复位释放沿引发 metastable
- **时序收敛建议**：
  - SYNC 模式实测 1 ns 约束下 NS=2/4/8 均收敛（slack MET 0.41 ns），300+ MHz 轻松满足
  - SYNC 模式更深级联或更低约束时：建议切到 ASYNC 模式或 Carry Lookahead 进位结构
  - ASYNC 模式：任意级数均可保持高 fmax，但需注意整体回绕延迟

### 7.5 级数/模式对频率影响（AND 归约修复前后对比）

**同环境实测**（DC W-2024.09-SP3, tcbn12ffcllbwp7d5t16p96cpdssgnp0p9v125c SS 0.9V/125°C,
1 ns 约束、input/output delay 0.1 ns、`compile -map_effort medium`）：

| NUM_STAGES | STAGE_WIDTH | 面积（修复前 → 后） | 关键路径（前 → 后） | slack（前 → 后） |
|:---:|:---:|:---:|:---:|:---:|
| 2 | 8 | 32.30 → 32.30 µm² | 0.13 → 0.13 ns | 0.75 → 0.75 |
| 4 | 8 | 64.83 → 64.88 µm² | 0.14 → 0.19 ns | 0.75 → 0.69 |
| 8 | 8 | 129.90 → 129.95 µm² | 0.14 → 0.37 ns | 0.74 → 0.52 |

> 关键路径 = data arrival − 0.1 ns（input delay）；修复前指 `en_stage[i] = en && cout_stage[i-1]`。
> 结论：面积代价 < 0.1%（AND 树与原单级 AND 门数相当）；时序代价随级数增长（归约扇入），
> NS=2 完全不变（归约退化为单级，行为等价）；1 ns 约束下 NS ≤ 8 全部收敛。
> ASYNC 模式（CASCADE_MODE=1）不受本次改动影响，关键路径恒为单级 `cmp + 1 DFF`。

### 7.6 关键路径优化建议
1. **SYNC → ASYNC 切换**：级数多时改用 CASCADE_MODE=1，消除组合进位链瓶颈
2. **流水线化进位链**：SYNC 模式下在进位链中插入寄存器，每级延迟 1 拍但频率翻倍
3. **并行预计算（已内置）**：`&cout_stage[i-1:0]` 即 AND 归约，已替代逐级串行链；更深的级数可改平衡 AND 树或进位预计算
4. **预定标（Prescaler）**：低级用高速小计数器，高级用低速大计数器，详见 cbb_cnt_fast

---

## 8. 验证策略

### 8.1 验证思路

采用 **Reference Model + Scoreboard 自检**架构：

- TB 内置参考模型（behavioral 计算期望 `q_ref`，按 NUM_STAGES×STAGE_WIDTH 拼接）
- 每拍对比 DUT 输出与期望值，mismatch 立即报错并打印上下文 5 拍波形
- 参数化测试框架：单 TB 覆盖 STAGE_WIDTH∈{4,8}、NUM_STAGES∈{2,4}、CASCADE_MODE∈{0,1} 配置矩阵

### 8.2 关键测试点

| 测试点 | 描述 |
|--------|------|
| 单级基础计数 | NUM_STAGES=1，验证单 stage wrap-around |
| 多级级联进位（SYNC） | CASCADE_MODE=0，NUM_STAGES=2/4，验证 cout_stage[i] → en_stage[i+1] 传递链 |
| 多级级联进位（ASYNC） | CASCADE_MODE=1，验证下降沿进位正确性 |
| 各级独立回绕 | 验证某级从 MAX 回绕 + 向上级进位 |
| 整体回绕 | 所有级达 MAX，验证下拍 q=0 |
| en 使能控制 | en=0 hold，en=1 计数，验证 hold 期间 q 不变 |
| 复位恢复 | 运行中拉 rst_n，验证异步立即清零 + 释放后从 0 重计 |
| 边界值 | 计数到 MAX、0、MAX-1 边界 |
| 位宽遍历 | STAGE_WIDTH=4/8，NUM_STAGES=2/4 配置参数化 |
| 模式遍历 | CASCADE_MODE=0/1 配置参数化 |

### 8.3 激励策略

- 定向用例：覆盖所有边界组合（MAX、0、回绕点）
- 随机用例：1000+ 组随机 en 序列，每序列 1000+ 拍
- 自检：TB 内置 Reference Model + Scoreboard 自动对比 `q`
- 覆盖点：
  - 状态翻转（每级 q_stage[i] 翻转覆盖）
  - 进位传递（每对相邻 stage 的 cout→cin 链覆盖）
  - 回绕边界（每级 0↔MAX 跳变）
  - 模式覆盖（SYNC / ASYNC 各自完整回绕）

### 8.4 与 VR 衔接

详细 Feature/TC 规划、覆盖率结果见独立文档 `cbb_cnt_cascade_vr.md`。本 UG §8 仅给出验证策略概要。
