# CBB_ARB_FCFS_UG

---

## 目录

- [1. 功能及应用场景](#1-功能及应用场景)
- [2. 规格](#2-规格)
- [3. 方案分析](#3-方案分析)
- [4. 配置参数](#4-配置参数)
- [5. 接口](#5-接口)
- [6. 时序图](#6-时序图)
- [7. PPA](#7-ppa)

---

## 1. 功能及应用场景

`CBB_ARB_FCFS` 是一个参数化同步仲裁器，采用**先来先服务（First-Come-First-Served, FCFS）**优先级调度策略。在每个时钟周期内，等待时间最长的客户端获得最高优先级，刚获得授权的客户端优先级降至最低。

**核心功能：**

- 参数化客户端数量，支持 2~32 个请求源
- FCFS 调度：等待时间越长优先级越高
- 平局仲裁：同优先级时以客户端索引打破平局（索引越小优先级越高）
- Lock 锁定：已授权客户端可锁定仲裁器独占资源
- Mask 屏蔽：可屏蔽指定客户端使其不参与仲裁
- Park 停靠：无请求时授权自动停靠到指定客户端
- 输出模式可选：寄存器输出或组合逻辑输出

**适用场景：**

- 多主设备共享总线仲裁（如 AHB/APB 总线仲裁器）
- DMA 通道请求调度
- 内存控制器请求排队
- 多核共享资源访问调度（Cache、SRAM 等）
- 网络包调度器

---

## 2. 规格

| 规格编号 | 类型 | 规格项 |
|----------|------|--------|
| DS.ARB_FCFS.FUNC.001 | FUNC | FCFS 优先级调度 |
| DS.ARB_FCFS.FUNC.002 | FUNC | 平局仲裁机制 |
| DS.ARB_FCFS.FUNC.003 | FUNC | Lock 锁定机制 |
| DS.ARB_FCFS.FUNC.004 | FUNC | Mask 屏蔽机制 |
| DS.ARB_FCFS.FUNC.005 | FUNC | Park 停靠机制 |
| DS.ARB_FCFS.FUNC.006 | FUNC | 优先级顺序：Lock > Mask > 正常仲裁 > Park |
| DS.ARB_FCFS.INTF.001 | INTF | 时钟与复位 |
| DS.ARB_FCFS.INTF.002 | INTF | 请求输入接口 |
| DS.ARB_FCFS.INTF.003 | INTF | 授权输出接口 |
| DS.ARB_FCFS.INTF.004 | INTF | Lock 输入接口 |
| DS.ARB_FCFS.INTF.005 | INTF | Mask 输入接口 |
| DS.ARB_FCFS.INTF.006 | INTF | 状态标志输出 |
| DS.ARB_FCFS.CFG.001 | CFG | NUM_MASTERS：客户端数量，范围 2~32 |
| DS.ARB_FCFS.CFG.002 | CFG | PARK_MODE：停靠模式使能 |
| DS.ARB_FCFS.CFG.003 | CFG | PARK_INDEX：停靠客户端索引 |
| DS.ARB_FCFS.CFG.004 | CFG | OUTPUT_MODE：输出模式选择 |

### 2.1 FCFS 优先级调度 — DS.ARB_FCFS.FUNC.001

仲裁器内部为每个客户端维护一个**优先级计数器** `priority[i]`，数值越小表示等待时间越长、优先级越高。`MAX_PRIORITY = NUM_MASTERS - 1` 为最低优先级（最大数值）。

**每个时钟周期的优先级更新规则：**

| 客户端状态 | priority[i] 更新行为 | 说明 |
|-----------|---------------------|------|
| 有有效请求且获得授权 | **置为 MAX_PRIORITY** | 已被服务，优先级降至最低 |
| 有有效请求但未获授权 | **减 1**（`priority[i] = priority[i] - 1`） | 继续等待，数值变小，优先级逐步升高 |
| 无有效请求（含被 mask） | **置为 MAX_PRIORITY** | 不参与竞争，保持最低优先级 |

**每个时钟周期的授权决策规则：** 在所有有效请求客户端中，`priority` 值最小者获得授权。当多个客户端 `priority` 值相同时，由低索引到高索引的遍历顺序天然保证索引小者获胜，无需额外判断。

**复位后初始状态：** 所有 `priority[i] = MAX_PRIORITY`，此时若多个客户端同时发起请求，`req[0]` 最先获得授权。

### 2.2 平局仲裁机制 — DS.ARB_FCFS.FUNC.002

当两个及以上客户端 `priority` 值相同时（含复位后初始状态），由低索引到高索引的遍历顺序天然保证索引小者获胜，无需额外的平局判断逻辑。

### 2.3 Lock 锁定机制 — DS.ARB_FCFS.FUNC.003

已获授权的客户端可通过 `lock[i]` 独占资源：
- `lock[i] = 1` 且客户端 i 已获授权时，仲裁器进入锁定状态
- 锁定期间 `update_priorities = 0`，所有客户端优先级数值冻结，其他客户端请求无法获得授权
- 锁定期间即使被锁定客户端撤销请求，授权仍维持
- `locked` 输出标志指示当前处于锁定状态
- 撤销 lock 后，仲裁器恢复正常 FCFS 调度

### 2.4 Mask 屏蔽机制 — DS.ARB_FCFS.FUNC.004

通过 `mask` 输入将特定客户端从仲裁中排除：
- `mask[i] = 1`：客户端 i 不参与仲裁
- 非锁定状态下，若屏蔽当前已授权客户端，下一周期授权撤销并重新仲裁
- 锁定状态下，mask 对当前授权无影响（锁定优先级最高）

### 2.5 Park 停靠机制 — DS.ARB_FCFS.FUNC.005

- `PARK_MODE = 1` 时使能停靠逻辑
- 当所有客户端均无活跃请求时，`gnt` 自动停靠到 `PARK_INDEX` 指定的客户端
- `parked` 输出标志指示当前处于停靠状态
- 停靠的客户端可直接通过 lock 锁定授权，无需先发出请求
- `PARK_MODE = 0` 时无停靠逻辑，`parked` 信号固定为 0

### 2.6 优先级顺序 — DS.ARB_FCFS.FUNC.006

仲裁器内部各机制的优先级从高到低为：**Lock > Mask > 正常仲裁 > Park**。

- **Lock 优先级最高**：锁定状态下覆盖所有其他逻辑，Mask 和请求变化均不影响当前授权
- **Mask 次之**：非锁定状态下，被屏蔽的客户端不参与仲裁，若当前授权客户端被屏蔽则下一周期重新仲裁
- **正常仲裁**：无 Lock 且无 Mask 影响时，按 FCFS 规则选出授权客户端
- **Park 优先级最低**：仅当无任何有效请求时才进入停靠状态

### 2.7 时钟与复位 — DS.ARB_FCFS.INTF.001

- 单时钟域设计，所有输入信号需与 `clk` 同步
- `rst_n` 为异步低有效复位，复位后所有内部状态清零（priority 复位为 MAX_PRIORITY）
- 异步请求需先经过外部同步器处理后再接入本模块

### 2.8 请求输入接口 — DS.ARB_FCFS.INTF.002

- `req[NUM_MASTERS-1:0]`：客户端请求输入，每位对应一个客户端
- `req[i] = 1` 表示客户端 i 请求授权
- 所有 req 信号需与 clk 同步

### 2.9 授权输出接口 — DS.ARB_FCFS.INTF.003

- `gnt[NUM_MASTERS-1:0]`：独热码授权输出
- `gnt[i] = 1` 表示客户端 i 获得授权
- 每个周期最多只有一个位为高
- `OUTPUT_MODE = 1` 时 `gnt` 为寄存器输出

### 2.10 Lock 输入接口 — DS.ARB_FCFS.INTF.004

- `lock[NUM_MASTERS-1:0]`：锁定输入（高有效）
- `lock[i] = 1` 且客户端 i 已获授权时锁定仲裁器

### 2.11 Mask 输入接口 — DS.ARB_FCFS.INTF.005

- `mask[NUM_MASTERS-1:0]`：屏蔽输入（高有效）
- `mask[i] = 1` 屏蔽客户端 i 的请求

### 2.12 状态标志输出 — DS.ARB_FCFS.INTF.006

| 标志 | 激活条件 | 说明 |
|------|----------|------|
| `granted` | 存在至少一个活跃请求 | 授权已发给某个活跃请求的客户端 |
| `locked` | 当前授权且对应 lock 有效 | 当前授权客户端已锁定 |
| `parked` | 无活跃请求输入 | 授权停靠在 PARK_INDEX 客户端；PARK_MODE=0 时固定为 0 |

### 2.13 可配置参数 — DS.ARB_FCFS.CFG.001~004

| 规格编号 | 参数 | 说明 |
|----------|------|------|
| DS.ARB_FCFS.CFG.001 | NUM_MASTERS | 客户端数量，范围 2~32 |
| DS.ARB_FCFS.CFG.002 | PARK_MODE | 停靠模式使能：0=禁用，1=使能 |
| DS.ARB_FCFS.CFG.003 | PARK_INDEX | 停靠客户端索引，范围 0~NUM_MASTERS-1 |
| DS.ARB_FCFS.CFG.004 | OUTPUT_MODE | 输出模式：0=组合逻辑输出，1=寄存器输出 |

---

## 3. 方案分析

### 3.1 核心原理

FCFS 仲裁器的核心思想是：**等待时间越长的请求，获得服务的优先级越高**。通过为每个客户端维护一个内部优先级计数器 `priority[i]`，将"等待时长"量化为可比较的数值。

**优先级计数器的本质：** `priority[i]` 从 `MAX_PRIORITY`（最低优先级）开始，每等待一个时钟周期数值减 1——数值越小表示等待越久、优先级越高。获得授权或无请求时，立即复位为 `MAX_PRIORITY`。

- `MAX_PRIORITY = NUM_MASTERS - 1`：最低优先级（初始值 / 复位值）
- `priority[i] = 0`：理论最高优先级（等待了 NUM_MASTERS-1 个周期）



### 3.2 仲裁选择逻辑

遍历所有客户端（`i` 从 0 到 NUM_MASTERS-1），选出 `priority` 值最小的有效请求客户端作为授权对象：

```verilog
gnt_idx_v = -1;   // 初始无选中客户端
for (i = 0; i < NUM_MASTERS; i = i + 1) begin
    if (req_masked[i] == 1'b1) begin
        // 核心比较规则：priority 数值更小的获胜（更小 = 等待更久 = 优先级更高）
        if ((gnt_idx_v < 0) || (priority[i] < priority[gnt_idx_v])) begin
            gnt_idx_v = i;
        end
    end
end
```

**比较规则拆解：**

| 条件 | 含义 |
|------|------|
| `gnt_idx_v < 0` | 尚未选中任何客户端，当前 `i` 直接当选 |
| `priority[i] < priority[gnt_idx_v]` | 当前客户端优先级值更小 → 等待更久 → 替换 winner |

**平局处理：** 若两个客户端 `priority` 值相等，先遍历到的（更小索引 `i`）会被保留为 winner，后遍历到的大索引因 `priority[i] < priority[winner]` 不成立，不会覆盖结果。这天然实现了 `req[0] > req[1] > ... > req[NUM_MASTERS-1]` 的平局规则，**无需额外的索引比较逻辑**。

### 3.3 优先级更新规则

遍历所有客户端，根据本轮仲裁结果更新 `priority[i]`（下一周期生效）：

```verilog
for (i = 0; i < NUM_MASTERS; i = i + 1) begin
    if (i == gnt_idx_v) begin
        // 本轮被授权客户端：下一周期置最低优先级
        priority_next[i] = MAX_PRIORITY;
    end
    else if (req_masked[i] == 1'b1) begin
        // 持续等待、未被授权客户端：优先级数值 -1（数值变小，优先级升高）
        if (update_priorities == 1'b1)
            priority_next[i] = priority[i] - 1;
    end
    else begin
        // 无请求客户端：直接置最低优先级
        priority_next[i] = MAX_PRIORITY;
    end
end
```

**优先级更新逻辑对应 FCFS 机制：**

| 客户端状态 | 更新行为 | FCFS 语义 |
|-----------|---------|-----------|
| 本轮获授权 | `priority = MAX_PRIORITY` | 刚被服务，优先级降至最低，排到队尾 |
| 等待未授权 | `priority = priority - 1` | 每周期数值减 1，持续变小，优先级持续升高 |
| 无请求 / 被屏蔽 | `priority = MAX_PRIORITY` | 未参与竞争，等待记录清零 |

**Lock 锁定状态：** `update_priorities = 0`，所有等待客户端的优先级数值冻结不变，实现独占总线。

### 3.4 结构框图

```
                           +-------------------------+
      rst_n -------------> |                         |
      req[n-1:0] --------> |   +---------------+    |
      mask[n-1:0] -------> |   |  Mask Gate     |    |
      lock[n-1:0] -------> |   +-------+-------+    |
                           |           |              |
                           |   +-------v-------+    |
                           |   | Priority Calc  |    |
                           |   | (FCFS Engine)  |    |
                           |   +-------+-------+    |
                           |           |              |
                           |   +-------v-------+    |
      clk ---------------> |   |  Lock Check    |    |
                           |   +-------+-------+    |
                           |           |              |
                           |   +-------v-------+    |
                           |   |  Park Check    |    |
                           |   +-------+-------+    |
                           |           |              |
                           |   +-------v-------+    |
                           |   |  Grant Decision|    |
                           |   +-------+-------+    |
                           |           |              |
      OUTPUT_MODE=1 -----> |   +-------v-------+    |
      clk ---------------> |   | Output Register|----> gnt[n-1:0]
                           |   +---------------+----> granted
                           |                        |---> locked
                           |   CBB_ARB_FCFS         |---> parked
                           +-------------------------+
```

---

## 4. 配置参数

| 参数 | 配置范围 | 默认值 | 描述 |
|------|----------|--------|------|
| NUM_MASTERS | 2 ~ 32 | 4 | 仲裁器客户端数量，决定 req/lock/mask/gnt 位宽 |
| PARK_MODE | 0 / 1 | 1 | 停靠模式使能：0=禁用停靠逻辑，1=使能停靠 |
| PARK_INDEX | 0 ~ NUM_MASTERS-1 | 0 | 停靠客户端索引，仅在 PARK_MODE=1 时有效 |
| OUTPUT_MODE | 0 / 1 | 1 | 输出模式：0=组合逻辑输出，1=寄存器输出 |

**派生参数：**

| 参数 | 计算公式 | 说明 |
|------|----------|------|
| PRIORITY_WIDTH | `$clog2(NUM_MASTERS)` | 优先级计数器位宽 |
| MAX_PRIORITY | `NUM_MASTERS - 1` | 最低优先级数值（最大值） |

---

## 5. 接口

| 信号名 | 位宽 | I/O | 时钟域 | 描述 |
|--------|------|-----|--------|------|
| clk | 1 | I | clk | 模块工作时钟 |
| rst_n | 1 | I | - | 异步复位，低有效 |
| req | NUM_MASTERS | I | clk | 客户端请求输入，req[i]=1 表示客户端 i 请求授权 |
| lock | NUM_MASTERS | I | clk | 锁定输入（高有效），lock[i]=1 锁定当前授权给客户端 i 。不使用时接 `{NUM_MASTERS{1'b0}}`（全 0）|
| mask | NUM_MASTERS | I | clk | 屏蔽输入（高有效），mask[i]=1 屏蔽客户端 i 。不使用时接 `{NUM_MASTERS{1'b0}}`（全 0）|
| gnt | NUM_MASTERS | O | clk | 独热码授权输出，寄存器输出（OUTPUT_MODE=1）/ 组合输出（OUTPUT_MODE=0） |
| granted | 1 | O | clk | 授权标志（高有效），表示已向某一活跃请求客户端发出授权。寄存器输出（OUTPUT_MODE=1）/ 组合输出（OUTPUT_MODE=0） |
| locked | 1 | O | clk | 锁定标志（高有效），表示当前授权被某一客户端锁定 。寄存器输出（OUTPUT_MODE=1）/ 组合输出（OUTPUT_MODE=0）|
| parked | 1 | O | clk | 停靠标志（高有效），表示无活跃请求且授权停靠在 PARK_INDEX。寄存器输出（OUTPUT_MODE=1）/ 组合输出（OUTPUT_MODE=0） |

**接口说明：**

- 所有输入信号（req / lock / mask）需与 `clk` 同步
- `gnt` 为独热码格式，每个周期最多只有一个位为高
- `OUTPUT_MODE = 1` 时，所有输出信号为寄存器输出（经过一级 flip-flop）
- `OUTPUT_MODE = 0` 时，所有输出信号为组合逻辑输出

---

## 6. 时序图

### 6.1 基本 FCFS 仲裁时序（OUTPUT_MODE = 1, NUM_MASTERS=4）

```
        T0      T1      T2      T3      T4      T5      T6
        |       |       |       |       |       |       |
clk   __/‾‾\____/‾‾\____/‾‾\____/‾‾\____/‾‾\____/‾‾\____/‾‾\__
      |       |       |       |       |       |       |
rst_n ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
      |       |       |       |       |       |       |
req_0 ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
req_1 ____________________________________‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
req_2 ____________________‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
      |       |       |       |       |       |       |
pri_0  3       3       3       2       3       2       1
pri_1  3       3       3       3       2       3       2
pri_2  3       3       2       3       2       1       3
      |       |       |       |       |       |       |
gnt   _[0]____[0]____[2]____[0]____[1]____[2]____[0]____
      |       |       |       |       |       |       |
```

图中 priority 为周期初值（MAX_PRIORITY=3）：T0~T1 初始均为 3，索引小者先获授权；T1 `req[2]` 未获授权后 `pri[2]` 降为 2，T2 时 `pri[2]=2 < pri[0]=3` 获得授权；T3 `pri[0]=2` 最小胜出；T4 `pri[1]=pri[2]=2` 平局时索引小者 `req[1]` 胜；T5 `pri[2]=1` 最小胜出——完整体现了"数值越小=等待越久=优先级越高"的递减式 FCFS 机制。

### 6.2 Lock 锁定时序

```
         T0    T1    T2    T3    T4    T5
         |     |     |     |     |     |
clk    __/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__/
       |     |     |     |     |     |
req[0] ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
       |     |     |     |     |     |
req[1] ____‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
       |     |     |     |     |     |
lock[0]____________‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
       |     |     |     |     |     |
locked ___________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
       |     |     |     |     |     |
gnt    ____‾‾\_____‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
       [0]   [1]   [0]   [0]   [0]
```

T0~T1 正常仲裁；T2 lock[0] 置位后 update_priorities=0，授权锁定在客户端 0，优先级冻结；T3 锁定期间即使 req[0] 撤销授权仍维持；T4 lock[0] 撤销后恢复正常仲裁。

### 6.3 Mask 屏蔽时序

```
         T0    T1    T2    T3    T4
         |     |     |     |     |
clk    __/‾‾\__/‾‾\__/‾‾\__/‾‾\__/
       |     |     |     |     |
req[0] ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
       |     |     |     |     |
req[1] ____‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾
       |     |     |     |     |
mask[0]____________‾‾‾‾‾‾‾‾‾‾‾‾‾‾
       |     |     |     |     |
gnt    ____‾‾\__‾‾\__‾‾\__‾‾\____
       [0]   [0]   [1]   [1]   [0]
```

T0~T1 正常仲裁 gnt=0；T2 mask[0]=1 屏蔽客户端 0，仲裁器重新选择 gnt=1；T3 mask[0] 保持，gnt=1 维持；T4 mask[0]=0 恢复正常仲裁。

### 6.4 Park 停靠时序

```
         T0    T1    T2    T3    T4
         |     |     |     |     |
clk    __/‾‾\__/‾‾\__/‾‾\__/‾‾\__/
       |     |     |     |     |
req[0] ‾‾‾‾‾\___________‾‾‾‾‾‾‾‾‾
       |     |     |     |     |
parked ________/‾‾‾‾‾‾‾‾‾\__________
       |     |     |     |     |
gnt    ____‾‾\__‾‾‾‾‾‾‾‾\__‾‾\____
       [0]  [0]  [PARK]  [0]  [0]
```

T1 req[0] 撤销后无活跃请求，gnt 停靠到 PARK_INDEX，parked 拉高；T3 req[0] 重新发起后退出停靠，恢复正常仲裁。

---

## 7. PPA


### 7.1 配置A：基础模式 — OUTPUT_MODE=1, PARK_MODE=1, NUM_MASTERS=4

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| NUM_MASTERS | 4 | 4个客户端 |
| PARK_MODE | 1 | 使能停靠 |
| PARK_INDEX | 0 | 停靠到客户端0 |
| OUTPUT_MODE | 1 | 寄存器输出 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 工艺 | TSMC 12nm (tcbn12ffcllbwp7d5t16p96cpd) |
| Corner | SS, 0.9V, 125°C |
| 频率 | 1.43 GHz（周期 0.7ns） |
| 面积 | 31.058 µm²（~225 gates） |
| 动态功耗 | 74.71 µW |
| 泄漏功耗 | 162.78 nW |

### 7.2 配置B：大规格模式 — OUTPUT_MODE=1, PARK_MODE=1, NUM_MASTERS=32

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| NUM_MASTERS | 32 | 32个客户端 |
| PARK_MODE | 1 | 使能停靠 |
| PARK_INDEX | 0 | 停靠到客户端0 |
| OUTPUT_MODE | 1 | 寄存器输出 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 工艺 | TSMC 12nm (tcbn12ffcllbwp7d5t16p96cpd) |
| Corner | SS, 0.9V, 125°C |
| 频率 | 238 MHz（周期 4.2ns，时序约束 CLK0_PERIOD=6.0/INPUT_DELAY=0.1） |
| 面积 | 1562.665 µm²（~11,307 gates） |
| 动态功耗 | 307.67 µW |
| 泄漏功耗 | 11.56 µW |

### 7.3 配置C：组合输出模式 — OUTPUT_MODE=0, PARK_MODE=1, NUM_MASTERS=4

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| NUM_MASTERS | 4 | 4个客户端 |
| PARK_MODE | 1 | 使能停靠 |
| PARK_INDEX | 0 | 停靠到客户端0 |
| OUTPUT_MODE | 0 | 组合逻辑输出 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 工艺 | TSMC 12nm (tcbn12ffcllbwp7d5t16p96cpd) |
| Corner | SS, 0.9V, 125°C |
| 频率 | 1.43 GHz（周期 0.7ns） |
| 面积 | 30.228 µm²（~219 gates） |
| 动态功耗 | 60.78 µW |
| 泄漏功耗 | 173.04 nW |

### 7.4 时序说明

| 配置 | 约束周期 | 瓶颈路径 | 逻辑级数 | 关键路径 | Slack | 极限频率 | 限制因素 |
|------|:---:|------|:---:|------|------|:---:|------|
| A | 0.7ns | REGIN | 19 | 0.31ns | 0.13ns | **2.26 GHz** | 输入→寄存器路径 |
| B | 4.2ns | REGIN | 245 | 3.15ns | 0.0002ns | **254 MHz** | 输入→寄存器路径（32 客户端） |
| C | 0.7ns | FEEDTHROUGH | 15 | 0.25ns | 0.0014ns | **2.01 GHz** | 输入→输出组合路径（OUTPUT_MODE=0） |

> 极限频率按各路径组最小允许周期估算：CLK0 路径 `T ≥ path / (1 - uncertainty_ratio)`，REGIN 路径 `T ≥ path / (1 - input_ratio - uncertainty_ratio)`，FEEDTHROUGH 路径 `T ≥ path / (1 - input_ratio - output_ratio)`。

- **配置 A**：REGIN（输入→首级寄存器）为瓶颈，输入延迟 + 时钟不确定性吃掉 30% 周期裕量。CLK0 内部寄存器间路径 slack 充裕（0.20ns），可进一步提频但受限于输入约束。
- **配置 B**：32 客户端优先级比较链产生 ~250 级逻辑深度，原始 0.7ns 远无法收敛。将约束放宽至 4.2ns、输入延迟比例降至 0.1 后，REGIN 路径 slack 仅 0.0002ns（已达物理极限）。如需更高频率，需流水线化优先级比较逻辑。
- **配置 C**：OUTPUT_MODE=0 下 gnt/granted/locked/parked 为纯组合输出，新增 FEEDTHROUGH 路径（req→gnt 全组合），输入+输出延迟共吃掉 50% 周期裕量，slack 仅 0.0014ns。该模式下极限频率受限于输入→输出组合路径。

---
