# CBB_ROM_UG

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

CBB_ROM（Configurable Read-Only Memory）是一款参数化的只读存储器 IP，内容通过外部初始化文件在仿真阶段载入。运行期间仅支持读操作，不支持在线写入。

**顶层框图：**

```
           ┌───────────────────────────────┐
           │                               │
mem_addr ─►│ 存储阵列 (mem[])     mem_rdata ├───►
           │                               │
       ────┤ mem_clk                       │
       ────┤ mem_cs                        │
           └───────────────────────────────┘
```

**核心功能：**

| 功能 | 说明 |
|------|------|
| 初始化文件加载 | 通过 `$readmemh` 在仿真起始阶段填充存储阵列 |
| 同步读模式 | 读地址在 `mem_clk` 上升沿采样，1 拍延迟寄存器输出 |
| 片选控制 | `mem_cs` 高有效，低电平时输出保持前值 |
| 参数化位宽与深度 | 地址位宽与数据位宽可独立配置 |
| 多工艺支持 | 通过宏定义支持 TSMC 12nm 硬宏、Xilinx FPGA、Altera FPGA 及纯行为级 |

**变体说明：**

| 变体 | 关键参数/宏 | 读模式 | 输出性质 | 适用场景 |
|------|------------|--------|----------|----------|
| 行为级同步读 | 默认 | 同步读 | 寄存器输出，1 拍延迟 | 驱动下游时序逻辑，时序可控 |
| TSMC_12 硬宏 | `+define+TSMC_12` | 纯同步 | 硬宏固定寄存器输出 | 256×32 固定配置，追求低功耗与已表征时序 |

### 1.2 适用场景

- 微码存储、查找表（LUT）、三角函数 / 对数查表
- 启动代码（Boot ROM）、常量表、字符点阵存储
- 状态机跳转表、译码表、CRC 余数表等只读数据结构
- 需要上电即确定内容且运行期不被修改的片上固件

---

## 2. 规格

每条规格以 DS 点编号标识，命名规则为 `DS.[IP_NAME].[TYPE][SPEC_ID]`。TYPE 取值：`FUNC`（功能）、`PERF`（性能）、`INTF`（接口）、`CFG`（配置）。

### 规格汇总

| DS 编号 | 类型 | 规格概述 |
|---------|------|----------|
| DS.CBB_ROM.FUNC.001 | FUNC | 初始化文件加载：通过 `$readmemh(INIT_FILE, mem)` 填充存储阵列 |
| DS.CBB_ROM.FUNC.002 | FUNC | 同步读模式：`mem_addr` 在 `mem_clk` 上升沿采样，1 拍延迟寄存器输出 |
| DS.CBB_ROM.FUNC.003 | FUNC | 只读属性：无写端口，运行期间物理只读 |
| DS.CBB_ROM.FUNC.004 | FUNC | 片选控制：`mem_cs` 高有效，`mem_cs=0` 时读输出保持前值 |
| DS.CBB_ROM.CFG.001 | CFG | 地址/数据位宽配置：深度 = `2^MEM_ADDR_WIDTH`，位宽 = `MEM_DATA_WIDTH` |
| DS.CBB_ROM.CFG.004 | CFG | 多工艺支持：TSMC_12 / FPGA_XILINX / FPGA_ALTERA / 行为级 |
| DS.CBB_ROM.INTF.001 | INTF | 标准读接口（无 rst_n） |
| DS.CBB_ROM.INTF.002 | INTF | 输出信号属性（同步寄存器输出） |
| DS.CBB_ROM.PERF.001 | PERF | 读延迟固定 1 拍 |

### 2.1 初始化文件加载 — DS.CBB_ROM.FUNC.001

ROM 内容通过标准 Verilog 系统任务 `$readmemh(INIT_FILE, mem)` 在 `initial` 过程中加载。初始化文件为纯文本十六进制格式，每行对应一个地址的数据，从地址 0 开始顺序填充。

- 文件行数超过存储深度时，超出部分被忽略
- 文件行数不足存储深度时，未填充地址保持为 X（仿真期）
- 若 `INIT_FILE` 为空字符串 `""`，则跳过初始化，存储阵列内容未定义
- **综合阶段限制**：Design Compiler 等工具会忽略 `initial` 块中的 `$readmemh`。若需获得真实面积与功耗数据，综合时必须提供非空 `INIT_FILE`（综合前需提供非空 INIT_FILE），或改用 `TSMC_12` 硬宏模式

### 2.2 同步读模式 — DS.CBB_ROM.FUNC.002

CBB_ROM 采用固定同步读架构。`mem_addr` 在 `mem_clk` 上升沿被采样，下一拍 `mem_rdata` 更新为对应存储单元内容。输出经寄存器打拍，无毛刺，适合驱动下游时序逻辑。

- **读延迟**：固定 1 个时钟周期
- **输出特性**：寄存器输出，时序路径干净，外部可直接连接时序逻辑而无需担心毛刺

### 2.3 只读属性 — DS.CBB_ROM.FUNC.003

CBB_ROM 在硬件接口与内部实现上均不暴露写端口。存储内容仅在初始化阶段由文件载入，运行期间为物理只读。若需运行期可写的存储器，应选用 `CBB_RAM_SP` / `CBB_RAM_DP` / `CBB_RAM_TP`。

### 2.4 片选控制 — DS.CBB_ROM.FUNC.004

- `mem_cs`（Chip Select / Read Enable，高有效）：片选兼读使能信号。
  - `mem_cs=1` 时 ROM 被选中，允许输出有效数据
  - `mem_cs=0` 时：`mem_rdata` 保持上一拍的有效值（寄存器不更新）
- 本模块不实现三态输出（高阻 `Z`），输出始终为确定电平，便于数字后端处理

### 2.5 地址与数据位宽配置 — DS.CBB_ROM.CFG.001

- 存储深度 = `2^MEM_ADDR_WIDTH`，地址合法范围为 `0` 至 `(2^MEM_ADDR_WIDTH - 1)`
- 数据位宽 = `MEM_DATA_WIDTH`，每个地址存储 `MEM_DATA_WIDTH` 位数据

### 2.6 标准读接口 — DS.CBB_ROM.INTF.001

| 信号 | 位宽 | I/O | 描述 |
|------|------|-----|------|
| `mem_clk` | 1 | I | 工作时钟，用于采样地址和驱动输出寄存器 |
| `mem_cs` | 1 | I | 片选/读使能，高有效。`1` 时选中 ROM 并输出有效数据；`0` 时 `mem_rdata` 保持前值 |
| `mem_addr` | MEM_ADDR_WIDTH | I | 读地址，在 `mem_clk` 上升沿采样 |
| `mem_rdata` | MEM_DATA_WIDTH | O | 读数据输出，固定延迟 1 拍。`mem_cs=0` 时保持前值 |

### 2.7 输出信号属性 — DS.CBB_ROM.INTF.002

| 信号 | 输出类型 | 说明 |
|------|---------|------|
| `mem_rdata` | 寄存器输出 | `mem_cs=1` 时，下一拍更新为 `mem[mem_addr]`；`mem_cs=0` 时保持前值 |

**上电初值说明：**

仿真阶段通过 `$readmemh` 在 0 时刻加载 INIT_FILE，上电后存储阵列已有确定值。综合阶段若 `INIT_FILE` 为空，Design Compiler 会将未初始化的存储阵列优化为常量逻辑，导致面积严重失真（详见 3.8 节）。

### 2.8 读延迟性能 — DS.CBB_ROM.PERF.001

CBB_ROM 固定采用同步读模式：

- `mem_rdata` 为寄存器输出，固定 1 拍时钟延迟
- 输出路径延迟仅为 CK→Q，存储阵列寻址路径被包在模块内部
- 外部时序约束仅需考虑 `mem_addr` 到 `mem_clk` 的建立/保持时间

深度较大时（> 256），建议采用 `TSMC_12` 硬宏或上层 Banking 策略，利用硬宏的已表征时序改善裕量。

### 2.9 多工艺支持 — DS.CBB_ROM.CFG.004

本模块通过宏定义支持四种物理实现方式，综合工具将根据目标工艺、容量和宏定义自动选择最优映射策略：

| 工艺宏 | 容量 | 典型实现方式 | 说明 |
|--------|------|-------------|------|
| 无（默认） | 小深度（≤ 64 字） | 触发器（DFF）阵列 | 综合工具自动推断为寄存器阵列，访问速度快 |
| 无（默认） | 中深度（64 ~ 256 字） | 标准单元 MUX + DFF | 面积与性能的折中，适用于 ASIC 小容量场景 |
| `TSMC_12` | 256×32（固定） | Memory Compiler 硬宏（占位名 `CBB_ROM_256X32`） | 仅当 `MEM_ADDR_WIDTH=8 && MEM_DATA_WIDTH=32` 时例化硬宏；其余配置自动回退到行为级 |
| `FPGA_XILINX` | 任意 | Block ROM（BRAM） | `(* rom_style = "block" *)` 强制映射；Vivado 自动映射为 BRAM 或 UltraRAM |
| `FPGA_ALTERA` | 任意 | M20K ROM | `(* ramstyle = "M20K" *)` 强制映射；Quartus 自动映射为 M20K 块存储器 |

由于为只读，综合工具可自动优化掉写电路，面积优于同等容量的 RAM。

---

## 3. 方案分析

### 3.1 整体架构

CBB_ROM 采用标准 Verilog 存储器模型，根据工艺宏定义，在仿真/综合阶段自动选择最优实现方式。本模块为只读存储器，数据路径为同步寄存器输出。

代码结构如下：

```verilog
reg [MEM_DATA_WIDTH-1:0] mem [0:((1 << MEM_ADDR_WIDTH)-1)];

initial
begin : INIT_PROC
  if (INIT_FILE != "")
    $readmemh(INIT_FILE, mem);
end

// 同步读 always 块
always @(posedge mem_clk)
begin : MEM_READ_PROC
  if (mem_cs == 1'b1)
  begin
    mem_rdata <= mem[mem_addr];
  end
end
```

### 3.2 存储阵列实现原理

综合工具将根据目标工艺、容量和宏定义自动选择最优实现方式，详见 **表 2**。

### 3.3 初始化机制

采用 `initial` 块调用 `$readmemh`：

```verilog
initial
begin : INIT_PROC
  if (INIT_FILE != "")
    $readmemh(INIT_FILE, mem);
end
```

- `$readmemh` 在仿真 0 时刻执行，确保上电后存储阵列已有确定值
- **综合工具（Design Compiler）不支持 `initial` 块综合**，因此综合阶段 `mem` 数组被视为未初始化。综合时需显式提供非空 dummy hex 路径解决此问题（详见 2.11）
- 若 `INIT_FILE` 为空，综合后面积接近 0（约 0.18 μm²），`report_timing` 显示 `No paths`，原因及解决方案见 2.11

### 3.4 同步读架构

```
           ┌─────────────┐
           │   mem[]     │
mem_addr ─►│   阵列      │
           └──────┬──────┘
                       │
                       ▼
              ┌─────────────────┐
              │  输出寄存器      │──► mem_rdata
              │ (mem_clk 上升沿) │
              └─────────────────┘
```

- `mem_addr` 在 `mem_clk` 上升沿直接采样，存储阵列输出经一级输出寄存器后送出
- 无时钟门控或地址寄存器，结构简洁，与 TSMC 硬宏行为一致
- 输出寄存器消除存储阵列读路径的毛刺

### 3.5 同步读适用场景

| 场景 | 说明 |
|------|------|
| 驱动下游时序逻辑（如 CPU 取指） | 输出干净，时序可控，避免组合路径过长 |
| 大深度、高频、时序紧张 | 输出寄存器切断关键路径，改善时序裕量 |
| 小深度、低频、控制查表 | 结构简单，综合工具可优化为 LUT 逻辑 |

### 3.6 TSMC 12nm 硬宏架构

当定义 `TSMC_12` 宏且配置为 `MEM_ADDR_WIDTH=8, MEM_DATA_WIDTH=32` 时，模块例化一个 256x32 ROM 宏（本仓库以占位名 `CBB_ROM_256X32` 表示）：

- `mem_cs` 经反相器接入宏的 `CEB`（低有效），接口端口高有效、宏内部低有效，极性正确
- 测试引脚固定接法：`RTSEL=2'b01`、`PTSEL=2'b01`、`TRB=2'b01`、`TM=1'b0`、`SD=1'b0`、`BIST=1'b0`、`CEBM=1'b1`
- 硬宏为纯同步输出
- ROM 内容在 Memory Compiler 生成时固化，RTL 中的 `INIT_FILE` 被忽略

**硬宏端口映射**（详见 **表 6**）：

| CBB_ROM 信号 | TSMC 宏端口 | 接法 |
|-------------|------------|------|
| `mem_clk` | `CLK` | 直连 |
| `mem_cs` | `CEB` | 反相（接口高有效 → 宏低有效） |
| `mem_addr[7:0]` | `A[7:0]` | 直连 |
| `mem_rdata[31:0]` | `Q[31:0]` | 直连 |
| - | `AM[7:0]` | `8'b0` |
| - | `CEBM` | `1'b1`（禁用 BIST） |
| - | `BIST` | `1'b0`（禁用 BIST） |
| - | `SD` | `1'b0`（禁用 ShutDown） |
| - | `RTSEL[1:0]` | `2'b01`（推荐默认值） |
| - | `PTSEL[1:0]` | `2'b01`（推荐默认值） |
| - | `TRB[1:0]` | `2'b01`（推荐默认值） |
| - | `TM` | `1'b0`（禁用测试模式） |
| - | `PUDELAY` | 悬空 |

**使用方法示例：**

```bash
# 仿真：把后端提供的 ROM 宏模型加入编译列表（宏模型不随本仓库提供）
vcs -sverilog +define+TSMC_12 +incdir+. cbb_rom.v <rom_macro_model>.v <your_tb>.v

# 综合：TSMC_12 模式下 ROM 内容由宏固化，INIT_FILE 不参与
dc_shell -f <your_synth_script>.tcl
```

### 3.7 FPGA 实现架构

- **Xilinx FPGA**（`+define+FPGA_XILINX`）：行为级数组附加 `(* rom_style = "block" *)` 属性，Vivado 自动映射为 Block RAM（BRAM）或 UltraRAM，支持任意 `MEM_ADDR_WIDTH` 和 `MEM_DATA_WIDTH`
- **Intel/Altera FPGA**（`+define+FPGA_ALTERA`）：行为级数组附加 `(* ramstyle = "M20K" *)` 属性，Quartus 自动映射为 M20K 块存储器，支持任意 `MEM_ADDR_WIDTH` 和 `MEM_DATA_WIDTH`

### 3.8 工具链适配

为便于嵌入各类 EDA 流程，RTL 与工具链已做以下适配：

- **Dummy INIT_FILE 注入**：综合前须保证 `INIT_FILE` 指向非全零的 dummy hex，避免 DC 将 ROM 优化为常量逻辑
- **SpyGlass 适配**：RTL 中 `initial` 块已用 `` `ifndef SPYGLASS `` / `` `endif `` 包裹；TCL 中 `set_option define SPYGLASS` 启用宏；lint 报告 `moresimple.rpt` 中的已知假错误需在流程中人工排除
- **VCS UTF-8 清洗**：编译前去除源码 BOM 和非 ASCII 字符
- **DC 语法兼容**：预处理阶段将 `` `default_nettype none `` 替换为 `` `default_nettype wire ``
- **DC 参数化模块名匹配**：综合脚本用 `get_designs ${TOP}_*` 匹配参数化展开后的模块名，再 `current_design $elaborated_design`
- **产物目录收敛**：建议所有工具在统一输出目录下运行，避免中间文件散落 RTL 目录

---

## 4. 配置参数

| 参数 | 配置范围 | 默认值 | 描述 |
|------|----------|--------|------|
| `MEM_ADDR_WIDTH` | 1 ~ 32 | 8 | 地址位宽，决定存储深度为 `2^MEM_ADDR_WIDTH` |
| `MEM_DATA_WIDTH` | 1 ~ 1024 | 32 | 数据位宽，每个地址存储的数据位数 |
| `INIT_FILE` | 字符串 | `""`（空字符串） | 初始化文件路径。空字符串表示不加载；非空时调用 `$readmemh` 加载 |

**配置约束关系：**

- `MEM_ADDR_WIDTH` 与 `MEM_DATA_WIDTH` 相互独立，无耦合约束
- `INIT_FILE` 的行数不应超过 `2^MEM_ADDR_WIDTH`，否则超出部分被忽略
- **TSMC_12 硬宏限制**：仅当 `MEM_ADDR_WIDTH=8 && MEM_DATA_WIDTH=32` 时生效，其余配置自动回退到行为级

---

## 5. 接口

### 5.1 同步读模式接口

| 信号名 | 位宽 | I/O | 时钟域 | 输出类型 | 描述 |
|--------|------|-----|--------|----------|------|
| `mem_clk` | 1 | I | - | - | 工作时钟，用于采样地址和驱动输出寄存器 |
| `mem_cs` | 1 | I | - | - | 片选/读使能，高有效。`1` 时选中 ROM 并输出有效数据；`0` 时 `mem_rdata` 保持前值 |
| `mem_addr` | MEM_ADDR_WIDTH | I | mem_clk | - | 读地址，在 `mem_clk` 上升沿采样 |
| `mem_rdata` | MEM_DATA_WIDTH | O | mem_clk | 寄存器输出 | 读数据输出，延迟 1 拍。`mem_cs=0` 时保持前值 |

### 5.2 输出信号属性

| 信号 | 输出类型 | 说明 |
|------|---------|------|
| `mem_rdata` | 寄存器输出 | `mem_cs=1` 时下一拍更新为 `mem[mem_addr]`；`mem_cs=0` 时保持前值 |

### 5.3 TSMC_12 硬宏接口映射

当定义 `+define+TSMC_12` 且 `MEM_ADDR_WIDTH=8, MEM_DATA_WIDTH=32` 时，CBB_ROM 信号与 TSMC 硬宏端口映射如下：

| CBB_ROM 信号 | TSMC 宏端口 | 接法 |
|-------------|------------|------|
| `mem_clk` | `CLK` | 直连 |
| `mem_cs` | `CEB` | 反相（接口高有效 → 宏低有效） |
| `mem_addr[7:0]` | `A[7:0]` | 直连 |
| `mem_rdata[31:0]` | `Q[31:0]` | 直连 |
| - | `AM[7:0]` | `8'b0` |
| - | `CEBM` | `1'b1`（禁用 BIST） |
| - | `BIST` | `1'b0`（禁用 BIST） |
| - | `SD` | `1'b0`（禁用 ShutDown） |
| - | `RTSEL[1:0]` | `2'b01`（推荐默认值） |
| - | `PTSEL[1:0]` | `2'b01`（推荐默认值） |
| - | `TRB[1:0]` | `2'b01`（推荐默认值） |
| - | `TM` | `1'b0`（禁用测试模式） |
| - | `PUDELAY` | 悬空 |

**片选控制真值表：**

| `mem_cs` | `mem_rdata` |
|:---:|:---|
| 1 | 下一拍更新为 `mem[mem_addr]` |
| 0 | 保持上一拍有效值 |

---

## 6. 时序图

### 6.1 同步读模式

```
         T0      T1      T2      T3      T4      T5
             _       _       _       _       _       _
mem_clk    _| |_____| |_____| |_____| |_____| |_____| |_
                          _______________
mem_addr   XXXXXXXXXXXXXX_0x05___________0x0A___________
                          _______________ _____________
mem_rdata XXXXXXXXXXXXX< 0 >__________< mem[0x05] >__< mem[0x0A] >
```

**说明：**
- T0~T1：上电初始，`mem_rdata` 为 X（未初始化）或 `mem[0]`（若 INIT_FILE 已加载）
- T2：`mem_addr=0x05` 在 T1~T2 上升沿被采样，T2 后 `mem_rdata` 更新为 `mem[0x05]`
- T4：`mem_addr` 变为 `0x0A`，T4~T5 上升沿采样，T5 后 `mem_rdata` 更新为 `mem[0x0A]`
- `mem_cs` 在整个过程中保持高电平（有效）

### 6.2 同步读模式下 mem_cs 控制

```
         T0      T1      T2      T3      T4
             _       _       _       _       _
mem_clk    _| |_____| |_____| |_____| |_____| |_
                          _______     _______
mem_addr   XXXXXXXXXXXXXX_0x05_______0x0A______
           _______     ___________     _________
mem_cs            |___|           |___|
                          _______     _______
mem_rdata XXXXXXXXXXXXX<mem[0x05]><mem[0x05]><mem[0x0A]>
```

**说明：**
- T0~T1：`mem_cs=1`，正常读 `mem[0x05]`
- T1~T2：`mem_cs=0`，`mem_rdata` **保持前值** `mem[0x05]`（寄存器不更新）
- T2~T3：`mem_cs=1`，`mem_addr` 已变为 `0x0A`，T2~T3 上升沿采样，T3 后更新为 `mem[0x0A]`
- 同步模式下 `mem_cs=0` 不会导致输出变为高阻，而是保持上一拍数据

---

## 7. PPA

> **说明**：以下数据基于 TSMC 12nm 标准单元库和 Synopsys Design Compiler W-2024.09-SP3 综合获得。时钟周期约束为 2.0 ns（500 MHz）。综合时通过非全零 dummy hex + case 函数变换阻止 DC 常量传播，以下 PPA 为真实标准单元实现数据。

**综合工具：** Synopsys Design Compiler W-2024.09-SP3  
**工艺库：** TSMC 12nm 标准单元库（具体库角落由后端提供）  
**综合策略：** 时钟周期约束 2.0 ns（500 MHz）

### 7.1 配置 A：默认同步读（MEM_ADDR_WIDTH=8, MEM_DATA_WIDTH=32）

| 项目 | 数值 |
|------|------|
| 读延迟 | 1 cycle |
| 面积 | 104.79 μm²（491 cells, 24 寄存器） |
| 时序裕量 | 0.96 ns（MET） |
| 动态功耗 | 54.05 μW |
| 泄漏功耗 | 634.68 nW |

### 7.2 配置 B：非默认数据位宽（MEM_ADDR_WIDTH=8, MEM_DATA_WIDTH=16）

| 项目 | 数值 |
|------|------|
| 读延迟 | 1 cycle |
| 面积 | 76.40 μm²（352 cells, 16 寄存器） |
| 时序裕量 | 1.02 ns（MET） |
| 动态功耗 | 43.39 μW |
| 泄漏功耗 | 400.35 nW |

### 7.3 配置 C：非默认地址位宽（MEM_ADDR_WIDTH=10, MEM_DATA_WIDTH=32）

| 项目 | 数值 |
|------|------|
| 读延迟 | 1 cycle |
| 面积 | 161.83 μm²（808 cells, 26 寄存器） |
| 时序裕量 | 0.87 ns（MET） |
| 动态功耗 | 77.06 μW |
| 泄漏功耗 | 911.94 nW |

### 7.4 配置 D：大容量行为级（MEM_ADDR_WIDTH=12, MEM_DATA_WIDTH=64）

| 项目 | 数值 |
|------|------|
| 读延迟 | 1 cycle |
| 面积 | 269.66 μm²（1349 cells, 27 寄存器） |
| 时序裕量 | 0.78 ns（MET） |
| 动态功耗 | 114.77 μW |
| 泄漏功耗 | 1.40 μW |

> **警告**：4096 字深度在标准单元库中面积过大。**强烈建议启用 `TSMC_12` 宏例化 Memory Compiler 硬宏**（或联系工艺厂定制 4096×64 ROM 宏）。若必须使用行为级，建议拆分为多个 Bank 或采用 SRAM 宏替代。

### 7.5 配置 E：最小配置（MEM_ADDR_WIDTH=1, MEM_DATA_WIDTH=1）

| 项目 | 数值 |
|------|------|
| 读延迟 | 1 cycle |
| 面积 | 1.15 μm²（2 cells, 1 寄存器） |
| 时序裕量 | 1.25 ns（MET） |
| 动态功耗 | 1.55 μW |
| 泄漏功耗 | 6.80 nW |

### 7.6 工艺宏对比（TSMC_12 模式）

当定义 `+define+TSMC_12` 且 `MEM_ADDR_WIDTH=8, MEM_DATA_WIDTH=32` 时，CBB_ROM 自动例化 256x32 ROM 宏（占位名 `CBB_ROM_256X32`）：

| 指标 | 行为级（标准单元，非零 INIT_FILE） | TSMC_12 硬宏 |
|------|-----------------------------------|-------------|
| 面积 | 104.79 μm²（491 cells） | ~50-80 μm²（含冗余列和 BIST 电路） |
| 访问延迟 | 1 cycle + MUX 逻辑延迟 | 1 cycle + 固定宏延迟 |
| 功耗 | 54.05 μW（标准单元） | 较低（专用 ROM 结构） |
| 时序稳定性 | 依赖综合策略 | 固定，已 Characterized |

**选型建议**：
- ≤ 256 字、性能要求极高：行为级或 TSMC_12 硬宏均可
- \> 256 字：必须使用 TSMC_12 硬宏或 SRAM 宏，行为级面积不可接受

### 7.7 时序说明

- **同步读模式**：`mem_rdata` 为寄存器输出，输出路径延迟仅为 CK→Q。存储阵列寻址路径被包在模块内部，外部时序约束仅需考虑 `mem_addr` 到 `mem_clk` 的建立/保持时间。
- **片选路径**：`mem_cs` 到 `mem_rdata` 需满足到 `mem_clk` 的建立时间要求。
- 深度较大时（\> 256），建议采用 `TSMC_12` 硬宏，利用已表征时序。

---

> **公开分发说明**：本文中的工艺宏型号、宏时序库名与工艺库角落名均以占位形式给出（`CBB_SRAM_*` / `CBB_ROM_*` / "TSMC 12nm 标准单元库"）。实际型号由后端 Memory Compiler 与所选工艺库决定；接入时请按宏 databook 复核固定接值（`RTSEL` / `WTSEL` / `PTSEL` / `BWEB*` 等）与端口极性，以及 `Port A/B` 的读写分工。
