# CBB_RAM_SP_UG

---

## 目录

- [目录](#目录)
- [1. 功能及应用场景](#1-功能及应用场景)
- [2. 规格](#2-规格)
- [3. 方案分析](#3-方案分析)
- [4. 配置参数](#4-配置参数)
- [5. 接口](#5-接口)
- [6. 时序图](#6-时序图)
- [7. PPA](#7-ppa)

---

## 1. 功能及应用场景

### 1.1 核心功能

CBB_RAM_SP（Single Port Synchronous RAM）是一款参数化的单端口同步 SRAM IP，支持外部初始化文件通过 `$readmemh` 加载。运行期间支持单端口读写互斥操作。

**顶层框图：**

```
       ┌──────────────────────┐
       │                      │
  ─────┤ mem_clk              │
       │                      │
  ─────┤ mem_cs               │
       │                      │
  ─────┤ mem_rwe              │
       │                      │
  ─────┤ mem_bwe              │
       │                      │
  ─────┤ mem_addr   mem_rdata ├─────
       │                      │
  ─────┤ mem_wdata            │
       │                      │
       └──────────────────────┘
```

**核心功能：**

| 功能 | 说明 |
|------|------|
| 初始化文件加载 | 通过 `$readmemh` 在仿真起始阶段填充存储阵列 |
| 同步写操作 | `mem_cs=1 && mem_rwe=1` 时在时钟上升沿将 `mem_wdata` 写入 `mem_addr` |
| 同步读操作 | 寄存器输出，1 拍延迟 |
| 字节/位写使能 | `mem_bwe` 高有效，逐位屏蔽写操作 |
| 片选控制 | `mem_cs` 高有效，`mem_cs=0` 时读写禁止、读输出保持前值 |
| 参数化位宽与深度 | `MEM_DATA_WIDTH` 与 `MEM_ADDR_WIDTH` 可独立配置，深度 = `2^MEM_ADDR_WIDTH` |
| 多工艺支持 | 通过宏定义支持 TSMC 12nm 硬宏、Xilinx FPGA、Altera FPGA 及纯行为级 |

**变体说明：**

| 变体 | 关键参数/宏 | 读模式 | 输出性质 | 适用场景 |
|------|------------|--------|----------|----------|
| 行为级 RTL | 默认 | 同步读 | 寄存器输出，1 拍延迟 | 通用场景，参数灵活配置 |
| TSMC_12 硬宏 | `+define+TSMC_12` | 纯同步 | 硬宏固定寄存器输出 | 16x8 固定配置，追求低功耗与已表征时序 |

### 1.2 适用场景

- 通用数据缓存、DMA 中间缓冲、算法临时变量存储
- 状态存储、微码存储、配置上下文保存
- 小型查找表（LUT）、三角函数表、CRC 余数表
- 单生产者/单消费者数据缓冲、FIFO 内部存储
- 深度较大时（>64）替代 DFF 阵列，显著降低面积

---

## 2. 规格

每条规格以 DS 点编号标识，命名规则为 `DS.[IP_NAME].[TYPE][SPEC_ID]`。TYPE 取值：`FUNC`（功能）、`PERF`（性能）、`INTF`（接口）、`CFG`（配置）。

### 规格汇总

| DS 编号 | 类型 | 规格概述 |
|---------|------|----------|
| DS.CBB_RAM_SP.FUNC.001 | FUNC | 单端口读写互斥：`mem_rwe` 控制访问方向，同一时钟周期内不允许读写冲突 |
| DS.CBB_RAM_SP.FUNC.002 | FUNC | 同步写操作：`mem_cs=1 && mem_rwe=1` 时 `mem_clk` 上升沿写入 |
| DS.CBB_RAM_SP.FUNC.003 | FUNC | 同步读操作：`mem_cs=1 && mem_rwe=0` 时 1 拍延迟寄存器输出 |
| DS.CBB_RAM_SP.FUNC.004 | FUNC | 片选控制：`mem_cs` 高有效，`mem_cs=0` 时读写禁止、读输出保持前值 |
| DS.CBB_RAM_SP.FUNC.005 | FUNC | 参数化初始化：通过 `$readmemh` 加载 `INIT_FILE` |
| DS.CBB_RAM_SP.FUNC.006 | FUNC | 字节/位写使能：`mem_bwe` 高有效，逐位屏蔽写操作 |
| DS.CBB_RAM_SP.CFG.001 | CFG | 数据位宽由 `MEM_DATA_WIDTH` 参数配置 |
| DS.CBB_RAM_SP.CFG.002 | CFG | 地址位宽由 `MEM_ADDR_WIDTH` 参数配置，深度 = `2^MEM_ADDR_WIDTH` |
| DS.CBB_RAM_SP.INTF.001 | INTF | 输出信号属性（同步寄存器输出，1 拍延迟） |
| DS.CBB_RAM_SP.PERF.001 | PERF | 读/写延迟固定 1 拍 |

### 2.1 单端口读写互斥 — DS.CBB_RAM_SP.FUNC.001

模块仅提供单一物理端口，由 `mem_rwe` 控制访问方向。`mem_rwe=1` 时写，`mem_rwe=0` 时读。同一时钟周期内不允许读写冲突（外部仲裁保证）。

| `mem_cs` | `mem_rwe` | 操作 | 说明 |
|:---:|:---:|:---|:---|
| 1 | 1 | 写 | 在时钟沿将 `mem_wdata` 写入 `mem_addr` 地址（受 `mem_bwe` 逐位门控） |
| 1 | 0 | 读 | 从 `mem_addr` 地址读出数据到 `mem_rdata`（1 拍延迟） |
| 0 | x | 禁用 | `mem_rdata` 保持前值，写操作被禁止 |

### 2.2 同步写操作 — DS.CBB_RAM_SP.FUNC.002

写操作在时钟上升沿触发，当 `mem_cs == 1'b1 && mem_rwe == 1'b1` 时，`mem_wdata` 在时钟沿被写入 `mem_addr` 指定的存储单元。写入仅影响 `mem_bwe==1'b1` 对应的数据位，其余位保持不变。

### 2.3 同步读操作 — DS.CBB_RAM_SP.FUNC.003

读操作采用固定同步寄存器输出。当 `mem_cs == 1'b1 && mem_rwe == 1'b0` 时，当前时钟上升沿采样 `mem_addr`，下一时钟周期 `mem_rdata` 输出有效数据。读延迟固定为 1 cycle。

### 2.4 片选控制 — DS.CBB_RAM_SP.FUNC.004

`mem_cs`（Chip Select，高有效）：片选信号。`mem_cs=1` 时 SRAM 被选中，允许读写；`mem_cs=0` 时读写被禁止，`mem_rdata` 保持上一拍有效值。

### 2.5 参数化初始化 — DS.CBB_RAM_SP.FUNC.005

支持通过 `INIT_FILE` 参数指定 `.hex` / `.mif` 文件路径，仿真阶段调用 `$readmemh` 加载初始值。空字符串表示不加载，存储阵列内容未定义（仿真期）。

**综合阶段**：Design Compiler 会忽略 `initial` 块中的 `$readmemh`。RAM 有写端口，DC 保留存储逻辑，面积真实，无需 dummy hex 注入。

### 2.6 字节/位写使能 — DS.CBB_RAM_SP.FUNC.006

`mem_bwe`（Byte/Bit Write Enable，高有效）：写使能掩码，位宽与 `MEM_DATA_WIDTH` 一致。写操作时仅 `mem_bwe[i]==1'b1` 对应的 `mem[i]` 位被更新，其余位保持原值，可灵活实现字节写或逐位屏蔽写。与 CM_RAM_SP 接口完全对齐（CM_RAM_SP 按照位粒度实现，CBB_RAM_SP 行为级采用逐位 `generate` 写门控，语义一致）。

### 2.7 数据位宽配置 — DS.CBB_RAM_SP.CFG.001

`MEM_DATA_WIDTH` 决定每个存储单元的位宽。默认值：8。

### 2.8 地址位宽配置 — DS.CBB_RAM_SP.CFG.002

`MEM_ADDR_WIDTH` 决定地址总线宽度，存储深度 = `2^MEM_ADDR_WIDTH`。默认：`MEM_ADDR_WIDTH=4`（深度 16）。

### 2.9 输出信号属性 — DS.CBB_RAM_SP.INTF.001

| 信号 | 输出类型 | 说明 |
|------|---------|------|
| `mem_rdata` | 寄存器输出 | `mem_cs=0` 时保持前值；同步读固定 1 拍延迟 |

### 2.10 性能规格 — DS.CBB_RAM_SP.PERF.001

- **读延迟**：固定 1 cycle（寄存器输出）
- **写延迟**：固定 1 cycle（时钟沿写入）

---

## 3. 方案分析

### 3.1 整体架构

CBB_RAM_SP 采用标准 Verilog 存储器模型，根据工艺宏定义在仿真/综合阶段自动选择最优实现方式。

```verilog
reg [MEM_DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

initial
begin : INIT_PROC
  if (INIT_FILE != "")
    $readmemh(INIT_FILE, mem);
end

// 根据工艺宏选择 TSMC_12 硬宏、FPGA BRAM 或行为级实现
// 写端口采用逐位 generate + mem_bwe 门控（与 CM_RAM_SP 一致）
```

### 3.2 存储阵列实现原理

综合工具将根据目标工艺、容量和宏定义自动选择最优实现方式：

| 容量 | 典型实现方式 | 说明 |
|------|-------------|------|
| 小深度（小于等于 64 字） | 触发器（DFF）阵列 | 综合工具自动推断为寄存器阵列 |
| 中深度（64 ~ 256 字） | 标准单元 MUX + DFF | 面积与性能的折中 |
| 大深度（大于 256 字） | SRAM 宏 | 需目标工艺库支持，综合工具自动推断 |

### 3.3 初始化机制

采用 `initial` 块调用 `$readmemh`：

```verilog
initial
begin : INIT_PROC
  if (INIT_FILE != "")
    $readmemh(INIT_FILE, mem);
end
```

- `$readmemh` 在仿真 0 时刻执行
- **综合工具忽略 `initial` 块**，但 RAM 有写端口，DC 保留存储逻辑

### 3.4 同步读写架构

```
           ┌─────────┐
mem_addr ─►│   寄存器 │──┐
           │  (采样)  │  │
           └─────────┘   ▼
                     ┌───────┐
                     │ mem[] │
                     │ 阵列  │
                     └───┬───┘
                         │
                   ┌─────▼─────┐
                   │ 输出寄存器 │──► mem_rdata
                   └───────────┘
```

- 地址在 always 块中直接采样
- 存储阵列输出经一级输出寄存器后送出
- 无复位端口，输出寄存器无上电复位

### 3.5 TSMC 12nm 硬宏架构

当定义 `TSMC_12` 宏且配置为 `MEM_ADDR_WIDTH=4, MEM_DATA_WIDTH=8` 时，模块例化一个 16x8 单口 SRAM 宏（本仓库以占位名 `CBB_SRAM_16X8_1P` 表示）：

- `mem_cs` 经反相后接宏的 `CEB`：`CEB = ~mem_cs`（宏低有效，接口高有效）
- `mem_rwe` 经反相后接宏的 `WEB`：`WEB = ~mem_rwe`（宏 `0`=写/`1`=读，接口 `1`=写/`0`=读）
- `mem_bwe` 经反相后接宏的 `BWEB`：`BWEB = ~mem_bwe`（宏低有效掩码，接口高有效逐位写使能）
- 测试引脚固定接法：`RTSEL=2'b01`、`WTSEL=2'b01`、`SLP=1'b0`、`DSLP=1'b0`、`SD=1'b0`
- BIST 禁用：`BIST=1'b0`、`CEBM=1'b1`、`WEBM=1'b1`
- 硬宏为纯同步输出

**硬宏端口映射**（详见 **表 5**）：

| CBB_RAM_SP 信号 | TSMC 宏端口 | 接法 |
|----------------|------------|------|
| `mem_clk` | `CLK` | 直连 |
| `mem_cs` | `CEB` | 反相：`CEB = ~mem_cs` |
| `mem_rwe` | `WEB` | 反相：`WEB = ~mem_rwe`（`1`=写→`WEB=0`，`0`=读→`WEB=1`） |
| `mem_bwe[7:0]` | `BWEB[7:0]` | 反相：`BWEB = ~mem_bwe`（逐位写掩码，高有效→低有效） |
| `mem_addr[3:0]` | `A[3:0]` | 直连 |
| `mem_wdata[7:0]` | `D[7:0]` | 直连 |
| `mem_rdata[7:0]` | `Q[7:0]` | 直连 |
| - | `BIST` | `1'b0`（禁用） |
| - | `CEBM` | `1'b1`（禁用 BIST） |
| - | `WEBM` | `1'b1`（禁用 BIST） |
| - | `AM[3:0]` | `4'b0` |
| - | `DM[7:0]` | `8'b0` |
| - | `BWEBM[7:0]` | `8'b0` |
| - | `RTSEL[1:0]` | `2'b01`（推荐默认值） |
| - | `WTSEL[1:0]` | `2'b01`（推荐默认值） |
| - | `SLP` | `1'b0`（禁用） |
| - | `DSLP` | `1'b0`（禁用） |
| - | `SD` | `1'b0`（禁用） |
| - | `PUDELAY` | 悬空 |

### 3.6 FPGA 实现架构

- **Xilinx FPGA**（`+define+FPGA_XILINX`）：`(* ram_style = "block" *)` 强制映射 BRAM
- **Intel/Altera FPGA**（`+define+FPGA_ALTERA`）：`(* ramstyle = "M20K" *)` 强制映射 M20K

### 3.7 工具链适配

- **SpyGlass 适配**：RTL 中 `initial` 块已用 `` `ifndef SPYGLASS `` 包裹；lint 流程设置 `set_option define SPYGLASS` 即可
- **VCS UTF-8 清洗**：编译前去除源码 BOM 和非 ASCII 字符
- **DC 语法兼容**：预处理阶段替换 `default_nettype` 和 `parameter string`
- **DC 参数化模块名**：综合 TCL 中使用 `get_designs ${TOP}_*` 匹配
- **产物目录收敛**：建议所有工具在统一输出目录下运行，避免中间文件散落 RTL 目录

---

## 4. 配置参数

| 参数 | 配置范围 | 默认值 | 描述 |
|------|----------|--------|------|
| `MEM_DATA_WIDTH` | 1 ~ 1024 | 8 | 数据位宽 |
| `MEM_ADDR_WIDTH` | 1 ~ 16 | 4 | 地址位宽，存储深度 = `2^MEM_ADDR_WIDTH` |
| `INIT_FILE` | 字符串 | `""` | 初始化文件路径，空字符串表示不加载 |

**配置约束关系：**

- `MEM_DATA_WIDTH` 与 `MEM_ADDR_WIDTH` 相互独立
- **TSMC_12 硬宏限制**：仅当 `MEM_ADDR_WIDTH=4 && MEM_DATA_WIDTH=8` 时生效，其余配置自动回退到行为级

---

## 5. 接口

> **特别说明**：
> - `mem_cs` 为高有效信号，正常工作时需驱动为 `1`。
> - 当 `mem_cs=0` 时，读写被禁止，`mem_rdata` 保持前值。

| 信号名 | 位宽 | I/O | 时钟域 | 描述 |
|--------|------|-----|--------|------|
| `mem_clk` | 1 | I | `clk` | 模块工作时钟，上升沿触发 |
| `mem_cs` | 1 | I | `clk` | **片选，高有效**。`1` 时选中 SRAM，`0` 时禁用 |
| `mem_rwe` | 1 | I | `clk` | **读写使能**。`1` = 写，`0` = 读 |
| `mem_bwe` | MEM_DATA_WIDTH | I | `clk` | **逐位写使能，高有效**。`mem_bwe[i]=1` 时写对应 bit，`0` 时保持原值 |
| `mem_addr` | MEM_ADDR_WIDTH | I | `clk` | 读写共用地址 |
| `mem_wdata` | MEM_DATA_WIDTH | I | `clk` | 写数据输入 |
| `mem_rdata` | MEM_DATA_WIDTH | O | `clk` | 读数据输出，同步寄存器输出，1 拍延迟 |

### 5.1 读写控制真值表

| `mem_cs` | `mem_rwe` | `mem_bwe` | `clk` 沿 | `mem_rdata` | 存储器状态 |
|:---:|:---:|:---:|:---|:---|:---|
| 1 | 1 | 非全 0 | 上升沿 | 保持前值 | `mem[mem_addr][i] <= mem_wdata[i]`（仅 `mem_bwe[i]=1` 的位写入） |
| 1 | 0 | x | 上升沿 | `mem[mem_addr]` 寄存输出（1拍延迟） | 读操作 |
| 0 | x | x | 上升沿 | 保持前值 | 禁用，无操作 |

---

## 6. 时序图

### 6.1 写操作时序

```
         T0      T1      T2      T3
           _       _       _       _
mem_clk  _| |_____| |_____| |_____| |_

                _____
mem_cs   ______/     \_________________

                _____
mem_rwe  ______/     \_________________

                _____
mem_bwe  ______/ 1s  \_________________
                  ↑       ↑
mem_addr  ────X  0x2  X───X  0x5  X────
mem_wdata ────X  0xA5 X───X  0x3C X────
                  ↑       ↑
mem[2]           0xA5
mem[5]                   0x3C
```

**说明**：`mem_cs=1` 且 `mem_rwe=1` 时，时钟上升沿写入；`mem_bwe` 为高有效逐位写掩码，全 1 表示整字写入。

### 6.2 同步读操作时序

```
         T0      T1      T2      T3
           _       _       _       _
mem_clk  _| |_____| |_____| |_____| |_

                ____________________
mem_cs   ______/                    \_

         ________                    _
mem_rwe          \__________________/
                  ↑       ↑       ↑
mem_addr  ────X  0x2  X───X  0x5  X──
                  │       │       │
mem_rdata ─────────X 0xA5 X───X 0x3C X
                          ↑       ↑
                       1拍延迟  1拍延迟
```

**说明**：`mem_cs=1` 且 `mem_rwe=0` 时执行读。T1 采样 `mem_addr=0x2`，T2 输出 `mem[0x2]`；T2 采样 `mem_addr=0x5`，T3 输出 `mem[0x5]`。

### 6.3 片选控制时序（mem_cs = 0 时禁用）

```
         T0      T1      T2      T3
           _       _       _       _
mem_clk  _| |_____| |_____| |_____| |_

                _____     _____
mem_cs   ______/     \___/     \______
                 ____________
mem_rwe  _______/            \________
                  ↑       ↑       ↑
mem_addr  ────X  0x2  X───────X  0x5  X──
                  │               │
mem_rdata ───X 0xA5 X───X 0xA5 X──X 0x3C X
                  ↑       ↑       ↑
               正常读   保持前值  恢复读
```

**说明**：`mem_cs=0` 时读写被禁止，`mem_rdata` 保持前值。

---

## 7. PPA

> **说明**：以下数据基于 TSMC 12nm 标准单元库和 Synopsys Design Compiler W-2024.09-SP3 综合获得。时钟周期约束为 2.0 ns（500 MHz），输入/输出延迟均为 0.6 ns。
>
> **重要提示**：以下配置均采用行为级 RTL 综合，DC 将其映射为寄存器阵列（DFF + MUX），未调用工艺库 SRAM 宏。大容量配置（Config D）面积与时序开销显著，建议在实际项目中评估 SRAM 宏替代方案。

**综合工具：** Synopsys Design Compiler W-2024.09-SP3  
**工艺库：** TSMC 12nm 标准单元库（具体库角落由后端提供）  
**综合策略：** 时钟周期约束 2.0 ns（500 MHz），输入/输出延迟 0.6 ns

### 7.1 配置 A：默认配置（MEM_DATA_WIDTH=8, MEM_ADDR_WIDTH=4）

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| MEM_DATA_WIDTH | 8 | 数据位宽 8 bit |
| MEM_ADDR_WIDTH | 4 | 存储深度 16 字 |
| INIT_FILE | "" | 空字符串，不加载 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 存储深度 | 16 字 |
| 总存储 bit | 128 bit |
| 读延迟 | 1 cycle（同步寄存器输出） |
| 写延迟 | 1 cycle |
| 面积 | 190.54 um2 |
| 时序裕量 | 1.10 ns（MET） |
| 动态功耗 | 204.43 uW |
| 泄漏功耗 | 1.044 uW |
| Leaf Cell | ~550 |
| Sequential Cell | ~136（128 bit 存储阵列 + 8 bit 输出寄存器） |
| Macro Count | 0（寄存器阵列实现） |

**综合特性**：默认配置与 16x8 单口 SRAM 宏规格一致，可作为硬宏替代参考。

---

### 7.2 配置 B：中容量（MEM_DATA_WIDTH=32, MEM_ADDR_WIDTH=8）

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| MEM_DATA_WIDTH | 32 | 数据位宽 32 bit |
| MEM_ADDR_WIDTH | 8 | 存储深度 256 字 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 存储深度 | 256 字 |
| 总存储 bit | 8,192 bit |
| 读延迟 | 1 cycle |
| 写延迟 | 1 cycle |
| 面积 | 11,212.42 um2 |
| 时序裕量 | 0.72 ns（MET） |
| 动态功耗 | 12.00 mW |
| 泄漏功耗 | 59.08 uW |
| Leaf Cell | ~30,715 |
| Sequential Cell | ~8,224 |

---

### 7.3 配置 C：非默认位宽（MEM_DATA_WIDTH=16, MEM_ADDR_WIDTH=8）

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 存储深度 | 256 字 |
| 总存储 bit | 4,096 bit |
| 面积 | 5,633.42 um2 |
| 时序裕量 | 0.86 ns（MET） |
| 动态功耗 | 6.01 mW |
| 泄漏功耗 | 29.65 uW |

---

### 7.4 配置 D：大容量行为级（MEM_DATA_WIDTH=64, MEM_ADDR_WIDTH=10）

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 存储深度 | 1024 字 |
| 总存储 bit | 65,536 bit |
| 面积 | 93,943.25 um2 |
| 时序裕量 | 0.54 ns（MET） |
| 动态功耗 | 95.65 mW |
| 泄漏功耗 | 485.29 uW |
| 高扇出警告 | `mem_clk` 负载 ~65,600；`mem_wdata` 每 bit 负载 1,024 |

**综合特性**：1024 字深度在标准单元库中面积过大，强烈建议启用 `TSMC_12` 硬宏或联系工艺厂定制 SRAM 宏。若必须使用行为级，建议拆分为多个 Bank。

---

### 7.5 配置 E：最小配置（MEM_DATA_WIDTH=1, MEM_ADDR_WIDTH=1）

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 存储深度 | 2 字 |
| 总存储 bit | 2 bit |
| 面积 | 4.61 um2 |
| 时序裕量 | 1.23 ns（MET） |
| 动态功耗 | 4.62 uW |
| 泄漏功耗 | 25.28 nW |

---

### 7.6 工艺宏对比（TSMC_12 模式）

当定义 `+define+TSMC_12` 且 `MEM_ADDR_WIDTH=4, MEM_DATA_WIDTH=8` 时，CBB_RAM_SP 自动例化 16x8 单口 SRAM 宏（占位名 `CBB_SRAM_16X8_1P`）：

| 指标 | 行为级（标准单元） | TSMC_12 硬宏 |
|------|-------------------|-------------|
| 面积 | 190.54 um2（16x8） | 待实测（含冗余列和 BIST 电路） |
| 访问延迟 | 1 cycle + MUX 逻辑延迟 | 1 cycle + 固定宏延迟 |
| 功耗 | 较高（DFF 阵列动态功耗大） | 较低（专用 SRAM 结构） |
| 时序稳定性 | 依赖综合策略 | 固定，已 Characterized |

**选型建议**：
- 小于等于 16 字：行为级或 TSMC_12 硬宏均可
- 大于 256 字：必须使用 TSMC_12 硬宏或 SRAM 宏，行为级面积不可接受

---

### 7.7 综合映射说明

| 深度范围 | 综合工具典型映射 | 说明 |
|----------|-----------------|------|
| 小于等于 64 字 | DFF 阵列 | 综合工具推断为寄存器阵列，面积随深度线性增长 |
| 64 ~ 256 字 | 分布式 RAM / LUT-RAM | 面积与性能的折中，适用于 FPGA |
| 大于 256 字 | SRAM 宏 | 需目标工艺库支持，面积最优 |

### 7.8 时序说明

- **同步读模式**：关键路径为 `mem_addr` 到输出寄存器建立时间，存储阵列访问在时钟周期内完成。输出端时序裕量显著。
- **片选路径**：`mem_cs=0` 时 `mem_rdata` 保持前值，`mem_cs` 需满足到 `mem_clk` 的建立时间要求。
- **写操作时序**：`mem_wdata` 与 `mem_addr` 需在时钟沿前满足建立时间要求。写入后数据在下一时钟沿方可稳定读出。
- **高扇出网络**：大容量配置（Config D）中 `mem_clk` 负载达 65,600，后端需做时钟树综合（CTS）和写数据网络缓冲，否则可能导致 hold 违例或时钟偏斜过大。

### 7.9 综合 Warning 说明

| Warning 编号 | 描述 | 影响 | 建议 |
|-------------|------|------|------|
| VER-281 | DC 忽略 RTL 内 `initial` 块 | 无功能影响 | 预期行为，无需处理 |
| PWR-536 / PWR-24 | tie cell 无内部功耗表征 | 功耗报告精度降低 | 使用完整 .lib 时自动消除 |
| OPT-1208 | 开启时序输出反相 | 形式验证需 SVF 文件 | 保留 `.svf` 文件用于 Formality |
| TIM-134 | 高扇出网络（mem_clk / mem_wdata） | 后端布线压力 | 大容量配置需评估 SRAM 宏替代 |

---

> **公开分发说明**：本文中的工艺宏型号、宏时序库名与工艺库角落名均以占位形式给出（`CBB_SRAM_*` / `CBB_ROM_*` / "TSMC 12nm 标准单元库"）。实际型号由后端 Memory Compiler 与所选工艺库决定；接入时请按宏 databook 复核固定接值（`RTSEL` / `WTSEL` / `PTSEL` / `BWEB*` 等）与端口极性，以及 `Port A/B` 的读写分工。
