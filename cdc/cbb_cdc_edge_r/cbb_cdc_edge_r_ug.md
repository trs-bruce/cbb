# CBB_CDC_EDGE_R_UG

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

`cbb_cdc_edge_r` 是一个**上升沿同步器（Rising-Edge Synchronizer）**，对应标准 CDC 电路15（电平同步器 + 上升沿检测）。将源时钟域的 `data_s` 电平信号同步到目标时钟域，并在目标时钟域检测其上升沿（0→1 跳变），输出 1 个 `clk_d` 时钟周期宽度的单周期脉冲 `event_d`。

**核心功能：**

- 采用两级（STAGES 级）目标域 DFF 对 `data_s` 进行电平同步，消除亚稳态
- 在目标域通过"当前同步值取反 & 上一拍同步值"的组合逻辑提取上升沿
- 输出 1 个 `clk_d` 周期宽度的单周期脉冲
- STAGES 参数化可配置，默认 2 级
- 支持多工艺平台：`TSMC_12` / `FPGA_XILINX` / `FPGA_ALTERA` / 默认 RTL

**适用场景：**

**信号类型：** 单 bit 电平信号（位宽固定为 1）。仅支持单 bit 信号跨时钟域同步，不适用于多 bit 数据总线场景。

**时钟域场景：**
- **慢时钟域 → 快时钟域（推荐）：** 目标时钟频率 ≥ 源时钟频率时，同步链可充分采样源信号，亚稳态概率最低。`data_s` 每产生一次 0→1 跳变，目标域在 STAGES+1 个 `clk_d` 周期后输出 1 个 `clk_d` 周期宽度的脉冲 `event_d`。
- **快时钟域 → 慢时钟域（受限）：** 需保证 `data_s` 高电平宽度 ≥ 1 个 `clk_d` 周期，否则目标域可能漏采跳变。当目标时钟频率远低于源时钟频率时，`data_s` 高电平保持时间须相应增大，建议频率比 f_src/f_dst ≤ 1/(2×STAGES) 以确保可靠检测。

**设计限制：** 输出 `event_d` 为单周期脉冲，宽度恒为 1 个 `clk_d` 周期，与源域 `data_s` 的脉冲宽度无关。两次 `data_s` 跳变的最小间隔须 ≥ (STAGES+1) 个 `clk_d` 周期，否则目标域输出脉冲可能重叠。

**典型应用：**
- 使能信号上升沿触发目标域动作
- 事件通知跨域（如中断请求、启动命令）
- 状态机跨域触发
- 源域电平跳变需在目标域产生脉冲响应的场景

---

## 2. 规格

**规格汇总：**

| 规格 ID | 类型 | 规格项 | 描述 |
|---------|------|--------|------|
| DS.CBB_CDC_EDGE_R.INTF.001 | INTF | 时钟域 | clk_d 目标域，data_s 来自源域 |
| DS.CBB_CDC_EDGE_R.CFG.001 | CFG | 同步级数 | STAGES ≥2，默认 2 |
| DS.CBB_CDC_EDGE_R.CFG.002 | CFG | 工艺选择 | TSMC_12/FPGA_XILINX/FPGA_ALTERA/RTL |
| DS.CBB_CDC_EDGE_R.FUNC.001 | FUNC | 上升沿检测 | 检测 data_s 0→1 跳变 |
| DS.CBB_CDC_EDGE_R.FUNC.002 | FUNC | 单周期脉冲 | 1 个 clk_d 周期脉冲 |
| DS.CBB_CDC_EDGE_R.PERF.001 | PERF | 同步延迟 | STAGES+1 个 clk_d 周期 |
| DS.CBB_CDC_EDGE_R.PERF.002 | PERF | MTBF | 2 级典型 >10^9 年 |

### 2.1 上升沿检测与脉冲输出 — DS.CBB_CDC_EDGE_R.FUNC.001

`data_s` 经两级目标域 DFF 电平同步得到 `sync_dst`，目标域再打一拍得到 `sync_dly`，通过 `event_d = sync_dst & ~sync_dly` 提取上升沿。`data_s` 每个 0→1 跳变在目标域产生 1 个 `clk_d` 周期宽度的脉冲。

### 2.2 单周期脉冲输出 — DS.CBB_CDC_EDGE_R.FUNC.002

`event_d` 为目标域单周期脉冲，宽度恒为 1 个 `clk_d` 周期，与源域 `data_s` 的脉冲宽度无关。

### 2.3 同步级数可配置 — DS.CBB_CDC_EDGE_R.CFG.001

同步寄存器链级数 STAGES 可参数化配置，范围为 >= 2，默认值 2。Elaboration 阶段自动校验，STAGES < 2 时报 `$error` 拦截。

### 2.4 工艺选择 — DS.CBB_CDC_EDGE_R.CFG.002

通过宏定义选择同步器工艺实现：`TSMC_12`（标准单元同步 DFF，SDFSYNCNQD）、`FPGA_XILINX`（FDCE）、`FPGA_ALTERA`（dffeas）、默认 RTL 行为级描述。`.v` 标准单元实现统一归一到 `TSMC_12`，不再使用 `USE_STDCELL`，以消除宏定义冗余。

### 2.5 时钟域 — DS.CBB_CDC_EDGE_R.INTF.001

仅包含目标域时钟 `clk_d`。`data_s` 为源域产生的电平信号，在目标域完成电平同步与边沿检测，无需源域时钟。

### 2.6 同步延迟 — DS.CBB_CDC_EDGE_R.PERF.001

同步延迟 = STAGES + 1 个 `clk_d` 周期（STAGES 级电平同步 + 1 级边沿检测打拍）。STAGES=2 时延迟为 3 个 `clk_d` 周期。

### 2.7 MTBF — DS.CBB_CDC_EDGE_R.PERF.002

MTBF 随 STAGES 指数级提升。2 级同步器在典型工艺条件下（100MHz 目标时钟）MTBF > 10^9 年。

---

## 3. 方案分析

### 3.1 电路结构

边沿同步器（电路15）的机制是：先用电平同步器（两级 DFF）将源信号同步到目标时钟域，再在目标时钟域进行上升沿检测。电平同步保证跨域采样的亚稳态被净化，边沿检测在目标域完成，避免在源域直接检测边沿时因时钟频率差异漏采。

**实现方法对比：**

| 方法 | 优点 | 缺点 | 选用 |
| ---- | ---- | ---- | ---- |
| 源域检测边沿 + 电平同步 | 逻辑简单 | 需源域时钟，窄脉冲可能漏采 | 否 |
| 电平同步 + 目标域边沿检测 | 结构规整，仅需目标域时钟 | 需保证源电平宽度足够 | **是** |

### 3.2 实现方案

**电路结构图：**

```
  data_s ──→ sync_reg[0] ──→ sync_reg[1] ──→ ... ──→ sync_dst
                 (clk_d)        (clk_d)                  │
                                                             ├──→ sync_dly (clk_d, 打一拍)
                                                             │
                       event_d = sync_dst & ~sync_dly
```

**工作原理：**

1. **电平同步**：`data_s` 进入目标时钟域，经 STAGES 级 DFF（`sync_reg`）逐级净化亚稳态，末级输出 `sync_dst`
2. **边沿检测**：`sync_dst` 再打一拍得到 `sync_dly`，`event_d = sync_dst & ~sync_dly` 检测 `sync_dst` 的 0→1 跳变
3. **脉冲输出**：`sync_dst` 上升沿当拍 `event_d` 为 1，下一拍 `sync_dly` 追上 `sync_dst` 后 `event_d` 回 0，形成 1 个 `clk_d` 周期宽度的脉冲

---

## 4. 配置参数

| 参数 | 配置范围 | 默认值 | 描述 |
| ---- | -------- | ------ | ---- |
| STAGES | >= 2 | 2 | 同步寄存器链级数。影响 MTBF 和同步延迟 |

---

## 5. 接口

| 信号名 | 位宽 | I/O | 时钟域 | 描述 |
| ------ | ---- | --- | ------ | ---- |
| clk_d    | 1 | I | dst | 目标域工作时钟，上升沿有效 |
| rst_d_n  | 1 | I | dst | 目标域异步复位，低有效 |
| init_d_n | 1 | I | dst | 目标域同步复位，低有效 |
| data_s   | 1 | I | src | 源域电平信号，上升沿触发目标域脉冲 |
| event_d  | 1 | O | dst | 目标域上升沿脉冲，高有效，1 个 clk_d 周期宽 |
| test     | 1 | I | -   | 测试模式使能 |

---

## 6. 时序图

### 6.1 典型时序

![timing](figures/cbb_cdc_edge_r_timing.svg)

- 源域 `data_s` 出现 0→1 跳变（异步于 `clk_d`）
- 经 STAGES 级电平同步后，`sync_dst` 稳定为 1
- `sync_dly` 为 `sync_dst` 延迟一拍
- `event_d = sync_dst & ~sync_dly` 在 `sync_dst` 上升沿产生单周期脉冲
- 下降沿期间 `sync_dst & ~sync_dly` 不检出，不产生脉冲

---

## 7. PPA

> **综合工具：** Synopsys DC Ultra W-2024.09-SP3
> **工艺库：** TSMC 12nm tcbn12ffcllbwp7d5t16p96cpd (ssgnp0p9v125c)
> **时钟约束：** 0.2ns (5.0GHz)

### 7.1 配置A：STAGES=2（默认）

**参数设置：**

| 参数 | 设置值 | 说明 |
| ---- | ------ | ---- |
| STAGES | 2 | 2 级同步寄存器链 |

**PPA 数据：**（DC 综合实测，TSMC_12 宏、SDFSYNCNQD 标准同步单元）

| 项目 | 数值 |
| ---- | ---- |
| 频率 | 5.0 GHz（周期 200ps） |
| 面积 | 5.760000 µm²（2 个 SDFSYNCNQD + 1 边沿检测 DFF + 逻辑） |
| 单元数 | 12 cells（3 时序 + 9 组合） |
| 功耗 | 49.0604 µW（动态）+ 31.7966 nW（漏电） |
| WNS | 0.08217 ns（建立时序收敛，裕量 41%） |
| 非违例路径 | 0 |

> **结论：** 上升沿同步器关键路径为同步触发器 CK→Q→D 两级链路，时序极端收敛。实测 200ps（5GHz）周期下建立时间无违例，且仍保留 41% 时序裕量；频率扫描（TSMC 12nm/SSPVT 0.9V/125℃）显示极限可达 8.33GHz，但为保证 MTBF 亚稳态恢复时间与工程裕量，**支持的最大工作频率按 5GHz 声明**，较上一版 500MHz 提升 10 倍。与 `cbb_cdc_edge_f` 电路结构对称。

---
