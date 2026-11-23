# CBB_RAM_DP_UG

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

CBB_RAM_DP（True Dual Port Synchronous RAM）是一款参数化的**真双口同步 SRAM IP**，支持外部初始化文件通过 `$readmemh` 加载。模块提供完全独立的 Port A 与 Port B，两端口各有一组完整的读写信号（地址、写数据、读数据、片选、读写使能），并支持**独立时钟**（`mem_a_clk` / `mem_b_clk`）。两端口共享同一存储阵列，可在同一时刻（各自时钟沿）分别执行读或写操作，实现无阻塞的双向数据流。

**顶层框图：**

```
     ┌─────────────────────────────┐
     │                             │
   ──┤ mem_a_clk                   │
     │                             │
   ──┤ mem_a_cs                    │
     │                             │
   ──┤ mem_a_rwe                   │
     │                             │
   ──┤ mem_a_bwe                   │
     │                             │
   ──┤ mem_a_addr                  │
     │                             │
   ──┤ mem_a_wdata     mem_a_rdata ├───
     │                             │
   ──┤ mem_b_clk                   │
     │                             │
   ──┤ mem_b_cs                    │
     │                             │
   ──┤ mem_b_rwe                   │
     │                             │
   ──┤ mem_b_bwe                   │
     │                             │
   ──┤ mem_b_addr                  │
     │                             │
   ──┤ mem_b_wdata     mem_b_rdata ├───
     │                             │
     └─────────────────────────────┘
```

**核心功能特性：**

| 功能 | 说明 |
|------|------|
| **真双口架构** | Port A 与 Port B 完全对称，均可独立发起读或写 |
| **独立时钟域** | `mem_a_clk` 与 `mem_b_clk` 物理分离，支持同步或异步时钟操作 |
| **同步读写** | 写操作与读操作均在各自时钟上升沿触发，读输出固定 1 拍延迟 |
| **共享存储阵列** | A 口写入的数据 B 口立即可见（下一时钟沿），反之亦然 |
| **并发访问** | 两端口可同时读写**不同地址**，互不阻塞；同一地址并发写由硬件仲裁（行为级为后写优先，TSMC 宏由 Memory Compiler 定义） |
| **片选控制** | `cs` 高有效，`cs=0` 时对应端口所有操作被禁止，读输出保持前值 |
| **逐位写使能** | 每端口各有 `bwe[MEM_DATA_WIDTH-1:0]`，高有效，`bwe[i]=1` 的位才被写入，其余位保持原值 |
| **参数化位宽与深度** | `MEM_DATA_WIDTH` 与 `MEM_ADDR_WIDTH` 可独立配置，深度 = `2^MEM_ADDR_WIDTH` |
| **多工艺支持** | 通过宏定义支持 TSMC 12nm 硬宏、Xilinx FPGA、Altera FPGA 及纯行为级四种实现方式 |
| **初始化文件加载** | 支持 `$readmemh` 加载初始化数据 |

**变体说明：**

| 变体 | 关键参数/宏 | 读延迟 | 输出性质 | 适用场景 |
|------|------------|--------|----------|----------|
| 行为级（默认） | 无 | 1 cycle | 寄存器输出 | 仿真、FPGA 原型、非标准容量 |
| TSMC_12 硬宏 | `+define+TSMC_12` | 1 cycle | 硬宏固定寄存器输出 | 256×32 固定配置，追求低功耗与已表征时序 |

### 1.2 适用场景

| 场景 | 说明 |
|------|------|
| **FIFO 内部存储** | 作为异步 FIFO 的存储介质，写端口接写入侧，读端口接读出侧，天然支持一写一读并发 |
| **乒乓缓冲** | A 口写当前帧，B 口读上一帧，双缓冲零拷贝 |
| **跨时钟域数据缓冲** | `mem_a_clk` ≠ `mem_b_clk` 时，作为异步双口缓冲，无需额外 CDC 逻辑 |
| **查表与更新并发** | A 口持续查表的同时，B 口后台更新表项，无停顿 |
| **寄存器堆替代** | 深度较大时（>64）替代 DFF 阵列，真双口访问降低面积与功耗 |
| **总线交换矩阵** | 两个独立主设备通过 A/B 口同时访问存储空间 |

---

## 2. 规格

每条规格以 DS 点编号标识，命名规则为 `DS.[IP_NAME].[TYPE][SPEC_ID]`。TYPE 取值：`FUNC`（功能）、`PERF`（性能）、`INTF`（接口）、`CFG`（配置）。

### 规格汇总

| DS 编号 | 类型 | 规格概述 |
|---------|------|----------|
| DS.CBB_RAM_DP.FUNC.001 | FUNC | 提供真双口架构：Port A 与 Port B 完全独立，各含完整读写接口 |
| DS.CBB_RAM_DP.FUNC.002 | FUNC | Port A 写操作在 `mem_a_clk` 上升沿触发，`mem_a_rwe=1` 时写入 |
| DS.CBB_RAM_DP.FUNC.003 | FUNC | Port A 读操作在 `mem_a_clk` 上升沿触发，`mem_a_rwe=0` 时读取，1 拍延迟输出 |
| DS.CBB_RAM_DP.FUNC.004 | FUNC | Port B 写操作在 `mem_b_clk` 上升沿触发，`mem_b_rwe=1` 时写入 |
| DS.CBB_RAM_DP.FUNC.005 | FUNC | Port B 读操作在 `mem_b_clk` 上升沿触发，`mem_b_rwe=0` 时读取，1 拍延迟输出 |
| DS.CBB_RAM_DP.FUNC.006 | FUNC | 通过 `cs`（片选，高有效）控制对应端口访问；`cs=0` 时读写被禁止，读输出保持前值 |
| DS.CBB_RAM_DP.FUNC.007 | FUNC | 两端口共享单一存储阵列，A 写 B 读 / B 写 A 读数据互通 |
| DS.CBB_RAM_DP.FUNC.008 | FUNC | 支持通过 `$readmemh` 加载初始化文件 |
| DS.CBB_RAM_DP.FUNC.009 | FUNC | 两端口可在同一时刻（各自时钟沿）并发读写不同地址，互不阻塞 |
| DS.CBB_RAM_DP.FUNC.010 | FUNC | 每端口各有 `mem_x_bwe[MEM_DATA_WIDTH-1:0]` 逐位写使能（高有效），仅 `bwe[i]=1` 的位被写入 |
| DS.CBB_RAM_DP.CFG.001 | CFG | 数据位宽由 `MEM_DATA_WIDTH` 参数配置 |
| DS.CBB_RAM_DP.CFG.002 | CFG | 地址位宽由 `MEM_ADDR_WIDTH` 参数配置，存储深度 = `2^MEM_ADDR_WIDTH` |
| DS.CBB_RAM_DP.INTF.001 | INTF | 当 `cs=0` 时，对应端口写操作被禁止；读输出保持前值 |
| DS.CBB_RAM_DP.PERF.001 | PERF | 同步读模式固定 1 拍延迟；并发读写吞吐率：每周期可同时完成 1 次写和 1 次读（不同地址） |

### 2.1 真双口架构 — DS.CBB_RAM_DP.FUNC.001

模块提供完全对称的 Port A 与 Port B，两端口各有一组独立的读写控制信号，共享同一时钟域或独立时钟域。每个端口既可作为写端口，也可作为读端口，由 `rwe` 信号动态选择（`rwe=1` 写，`rwe=0` 读）；写操作由 `bwe` 逐位掩码。

| 端口 | 信号 | 方向 | 说明 |
|------|------|------|------|
| Port A | `mem_a_cs` | I | 片选，高有效（`1`=选中，`0`=禁用） |
| Port A | `mem_a_rwe` | I | 读写使能（`1`=写，`0`=读） |
| Port A | `mem_a_bwe` | I | 逐位写使能，高有效（`bwe[i]=1` 写入 bit i） |
| Port A | `mem_a_addr` | I | 地址 |
| Port A | `mem_a_wdata` | I | 写数据 |
| Port A | `mem_a_rdata` | O | 读数据（同步寄存器输出，1 拍延迟） |
| Port B | `mem_b_cs` | I | 片选，高有效 |
| Port B | `mem_b_rwe` | I | 读写使能（`1`=写，`0`=读） |
| Port B | `mem_b_bwe` | I | 逐位写使能，高有效 |
| Port B | `mem_b_addr` | I | 地址 |
| Port B | `mem_b_wdata` | I | 写数据 |
| Port B | `mem_b_rdata` | O | 读数据（同步寄存器输出，1 拍延迟） |

**读写控制逻辑**：
- 当 `cs=1 && rwe=1` 时，时钟上升沿将 `wdata` 按 `bwe` 掩码逐位写入 `addr` 指定的存储单元（仅 `bwe[i]=1` 的位被更新）；
- 当 `cs=1 && rwe=0` 时，时钟上升沿采样 `addr`，下一周期 `rdata` 输出对应存储单元数据；
- 当 `cs=0` 时，写操作被禁止，读输出保持前值（不更新）。

### 2.2 同步写操作 — DS.CBB_RAM_DP.FUNC.002 / FUNC.004

写操作在对应端口时钟上升沿触发。以 Port A 为例，当 `mem_a_cs == 1'b1 && mem_a_rwe == 1'b1` 时，`mem_a_wdata` 在 `mem_a_clk` 上升沿被写入 `mem_a_addr` 指定的存储单元，仅 `mem_a_bwe[i]==1` 的位被更新，其余位保持原值。`cs=0` 或 `rwe=0` 时，存储器内容保持不变。Port B 写操作同理，由 `mem_b_clk` 触发。

### 2.3 同步读操作 — DS.CBB_RAM_DP.FUNC.003 / FUNC.005

读操作固定为**同步寄存器输出**，1 拍延迟。以 Port A 为例，当 `mem_a_cs == 1'b1 && mem_a_rwe == 1'b0` 时，`mem_a_addr` 在 `mem_a_clk` 上升沿被采样，下一周期 `mem_a_rdata` 输出有效数据。Port B 读操作同理，由 `mem_b_clk` 触发。

### 2.4 片选控制 — DS.CBB_RAM_DP.FUNC.006

`cs`（Chip Select，高有效）：片选信号。当 `cs=1` 时对应端口被选中，允许读写操作；`cs=0` 时该端口所有读写被禁止，读输出 `rdata` 保持上一拍有效值。

### 2.4a 逐位写使能 — DS.CBB_RAM_DP.FUNC.010

`bwe`（Bit Write Enable，高有效）：逐位写掩码。写操作（`cs=1 && rwe=1`）时，仅 `bwe[i]==1` 的位被 `wdata[i]` 更新，`bwe[i]==0` 的位保持原值。全 `1` 等效于整字写；全 `0` 等效于本次写无操作。TSMC_12 硬宏下 `bwe` 经反相后接宏的 `BWEBx` 引脚（低有效）。

### 2.5 共享存储阵列 — DS.CBB_RAM_DP.FUNC.007

Port A 与 Port B 通过单一 `reg [MEM_DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1]` 共享数据：
- A 口写入的数据，B 口可在下一 `mem_b_clk` 上升沿读出；
- B 口写入的数据，A 口可在下一 `mem_a_clk` 上升沿读出。

### 2.6 并发读写支持 — DS.CBB_RAM_DP.FUNC.009

两端口可在各自时钟沿并发操作，无需互斥：
- **访问不同地址**：写操作与读操作完全独立，互不影响；
- **访问相同地址**：若两端口同时写同一地址，行为级模型为**后写优先**（非阻塞赋值，时钟沿后到者生效）；TSMC DP SRAM 宏的仲裁行为请参照 Memory Compiler databook。

### 2.7 参数化初始化 — DS.CBB_RAM_DP.FUNC.008

支持通过 `INIT_FILE` 参数指定 `.hex` 文件路径，仿真阶段调用 `$readmemh` 加载初始值。空字符串表示不加载，存储阵列内容未定义（仿真期）。

**综合阶段说明**：Design Compiler 会忽略 `initial` 块中的 `$readmemh`。RAM 有写端口，DC 保留存储逻辑，面积真实，无需 dummy hex。

### 2.8 数据位宽配置 — DS.CBB_RAM_DP.CFG.001

`MEM_DATA_WIDTH` 决定每个存储单元的位宽，可配置为 **≥ 1 的任意正整数**。默认值：32。

### 2.9 地址位宽配置 — DS.CBB_RAM_DP.CFG.002

`MEM_ADDR_WIDTH` 决定地址总线宽度，存储深度 = `2^MEM_ADDR_WIDTH`。默认值：8（深度 256）。

> **注意**：`MEM_DEPTH` 为 RTL 内部 `localparam`（= `2^MEM_ADDR_WIDTH`），不可在外部覆盖。

### 2.10 输出信号属性 — DS.CBB_RAM_DP.INTF.001

| 信号 | 输出类型 | 复位值 | 说明 |
|------|---------|--------|------|
| `mem_a_rdata` | 寄存器输出 | 无（上电未定义） | `mem_a_cs=0` 时保持前值 |
| `mem_b_rdata` | 寄存器输出 | 无（上电未定义） | `mem_b_cs=0` 时保持前值 |

> **注意**：真实 SRAM 硬宏无 RST 引脚，行为级模型不施加复位。上电后读输出为未定义值（X），需通过写操作或初始化文件确定有效数据。

### 2.11 性能规格 — DS.CBB_RAM_DP.PERF.001

- **时钟频率**：受限于写建立保持时间或读地址解码到输出寄存器的组合逻辑延迟
- **读延迟**：固定 1 cycle（同步寄存器输出）
- **写延迟**：固定 1 cycle（时钟沿写入）
- **并发吞吐**：每对时钟周期可同时完成 1 次写和 1 次读（不同地址）
- **面积**：小深度（≤64）时 DFF 实现面积最优；大深度（>256）时建议综合工具映射为 SRAM 宏或启用 TSMC_12 硬宏

---

## 3. 方案分析

### 3.1 整体架构

CBB_RAM_DP 采用标准 Verilog 存储器模型，根据工艺宏定义，在仿真/综合阶段自动选择最优实现方式。

```verilog
reg [MEM_DATA_WIDTH-1:0] mem [0:((1 << MEM_ADDR_WIDTH)-1)];

initial
begin : INIT_PROC
  if (INIT_FILE != "")
    $readmemh(INIT_FILE, mem);
end

// Port A: masked Write or Read
always @(posedge mem_a_clk)
  if (mem_a_cs == 1'b1 && mem_a_rwe == 1'b1)
    for (i = 0; i < MEM_DATA_WIDTH; i = i + 1)
      if (mem_a_bwe[i] == 1'b1)
        mem[mem_a_addr][i] <= mem_a_wdata[i];

always @(posedge mem_a_clk)
  if (mem_a_cs == 1'b1 && mem_a_rwe == 1'b0)
    mem_a_rdata <= mem[mem_a_addr];

// Port B: masked Write or Read
always @(posedge mem_b_clk)
  if (mem_b_cs == 1'b1 && mem_b_rwe == 1'b1)
    for (j = 0; j < MEM_DATA_WIDTH; j = j + 1)
      if (mem_b_bwe[j] == 1'b1)
        mem[mem_b_addr][j] <= mem_b_wdata[j];

always @(posedge mem_b_clk)
  if (mem_b_cs == 1'b1 && mem_b_rwe == 1'b0)
    mem_b_rdata <= mem[mem_b_addr];
```

### 3.2 存储阵列实现原理

综合工具将根据目标工艺、容量和宏定义自动选择最优实现方式：

| 容量 | 典型实现方式 | 说明 |
|------|-------------|------|
| 小深度（≤ 64 字） | 触发器（DFF）阵列 | 综合工具自动推断为寄存器阵列 |
| 中深度（64 ~ 256 字） | 标准单元 MUX + DFF | 面积与性能的折中 |
| 大深度（> 256 字） | SRAM 宏 | 需目标工艺库支持，综合工具自动推断 |

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
            ┌───────────┐
mem_a_addr ─┤   写地址   │
            │   寄存器   │──────────┐
            └───────────┘           │
                                    ▼
            ┌───────────┐      ┌────────┐
mem_b_addr ─┤   读地址   │      │ mem[]  │
            │   寄存器   │──────┤ 阵列   │
            └───────────┘      └────┬───┘
                                    │
                             ┌──────▼──────┐
                             │ 输出寄存器   │────► mem_a_rdata
                             └─────────────┘
```

- 地址在 always 块中直接采样
- 存储阵列输出经一级输出寄存器后送出
- **无复位端口**，输出寄存器无上电清零

### 3.5 TSMC 12nm 硬宏架构

当定义 `TSMC_12` 宏且配置为 `MEM_ADDR_WIDTH=8, MEM_DATA_WIDTH=32` 时，模块例化一个 256x32 真双口 SRAM 宏（本仓库以占位名 `CBB_SRAM_256X32_DP` 表示）：

- `mem_a_clk` / `mem_b_clk` 分别直连宏的 `CLKA` / `CLKB`（独立时钟）
- `CEBA = ~mem_a_cs`、`CEBB = ~mem_b_cs`（宏 CEB 低有效，接口 `cs` 高有效，全线反相）
- `WEBA = ~mem_a_rwe`、`WEBB = ~mem_b_rwe`（宏 WEB 低有效，`0`=写；接口 `rwe` 高有效写，`1`=写）
- `BWEBA = ~mem_a_bwe`、`BWEBB = ~mem_b_bwe`（宏 BWEB 低有效，逐位写使能真正生效）
- 测试引脚固定接法：`RTSEL=2'b01`、`WTSEL=2'b01`、`SLP=1'b0`、`DSLP=1'b0`、`SD=1'b0`
- BIST 禁用：`BIST=1'b0`，所有 `*M` 端口按 BIST 禁用接法
- 硬宏为纯同步输出，不支持异步读模式

**硬宏端口映射**（详见 **表 6**）：

| CBB_RAM_DP 信号 | TSMC 宏端口 | 接法 |
|----------------|------------|------|
| `mem_a_clk` | `CLKA` | 直连 |
| `mem_b_clk` | `CLKB` | 直连 |
| `mem_a_cs` | `CEBA` | 反相（`CEBA = ~mem_a_cs`，宏低有效） |
| `mem_b_cs` | `CEBB` | 反相（`CEBB = ~mem_b_cs`，宏低有效） |
| `mem_a_rwe` | `WEBA` | 反相（`WEBA = ~mem_a_rwe`，宏低有效，`0`=写） |
| `mem_b_rwe` | `WEBB` | 反相（`WEBB = ~mem_b_rwe`，宏低有效，`0`=写） |
| `mem_a_bwe[31:0]` | `BWEBA[31:0]` | 反相（`BWEBA = ~mem_a_bwe`，宏低有效，`0`=写该位） |
| `mem_b_bwe[31:0]` | `BWEBB[31:0]` | 反相（`BWEBB = ~mem_b_bwe`，宏低有效） |
| `mem_a_addr[7:0]` | `AA[7:0]` | 直连 |
| `mem_b_addr[7:0]` | `AB[7:0]` | 直连 |
| `mem_a_wdata[31:0]` | `DA[31:0]` | 直连 |
| `mem_b_wdata[31:0]` | `DB[31:0]` | 直连 |
| `mem_a_rdata[31:0]` | `QA[31:0]` | 直连 |
| `mem_b_rdata[31:0]` | `QB[31:0]` | 直连 |
| - | `BIST` | `1'b0`（禁用） |
| - | `RTSEL[1:0]` | `2'b01`（推荐默认值） |
| - | `WTSEL[1:0]` | `2'b01`（推荐默认值） |
| - | `SLP` | `1'b0`（禁用） |
| - | `DSLP` | `1'b0`（禁用） |
| - | `SD` | `1'b0`（禁用） |

### 3.6 FPGA 实现架构

- **Xilinx FPGA**（`+define+FPGA_XILINX`）：`(* ram_style = "block" *)` 强制映射 BRAM
- **Intel/Altera FPGA**（`+define+FPGA_ALTERA`）：`(* ramstyle = "M20K" *)` 强制映射 M20K

### 3.7 工具链适配

- **SpyGlass 适配**：RTL 中 `initial` 块已用 `` `ifndef SPYGLASS `` 包裹；TCL 中 `set_option define SPYGLASS`；lint 报告 `moresimple.rpt` 中的已知假错误需在流程中人工排除
- **VCS UTF-8 清洗**：编译前去除源码 BOM 和非 ASCII 字符
- **DC 语法兼容**：预处理阶段替换 `default_nettype` 和 `parameter string`
- **DC 真双口综合限制**：行为级 RTL 使用两个独立时钟过程驱动同一 `mem` 数组，DC Presto 编译器报多驱动错误（`ELAB-366`）。解决方案：RTL 中通过 `` `ifndef SYNTHESIS `` / `` `else `` 条件编译，在综合时回退为单时钟（`mem_a_clk`）合并写模型；TCL 中 `analyze` 增加 `-define SYNTHESIS`。综合面积为**参考值**，真实双口实现必须使用 TSMC_12 硬宏。
- **DC 参数化模块名**：综合 TCL 中使用 `get_designs ${TOP}_*` 匹配
- **产物目录收敛**：建议所有工具在统一输出目录下运行，避免中间文件散落 RTL 目录
- **TSMC_12 仿真**：`TSMC_MEM_V` 环境变量自动触发 `+define+TSMC_12` 和 `+notimingchecks`

---

## 4. 配置参数

| 参数 | 配置范围 | 默认值 | 描述 |
|------|----------|--------|------|
| `MEM_DATA_WIDTH` | 1 ~ 1024 | 32 | 数据位宽，每个地址存储的数据位数 |
| `MEM_ADDR_WIDTH` | 1 ~ 16 | 8 | 地址位宽，存储深度 = `2^MEM_ADDR_WIDTH` |
| `INIT_FILE` | 字符串 | `""` | 初始化文件路径。空字符串表示不加载 |

**配置约束关系：**

- `MEM_DATA_WIDTH` 与 `MEM_ADDR_WIDTH` 相互独立
- `MEM_DEPTH` 为 RTL 内部 `localparam`（= `2^MEM_ADDR_WIDTH`），不可在外部覆盖；综合/仿真脚本中仅为日志命名导出
- **TSMC_12 硬宏限制**：仅当 `MEM_ADDR_WIDTH=8 && MEM_DATA_WIDTH=32` 时生效，其余配置自动回退到行为级

---

## 5. 接口

> **特别说明**：
> - 模块**无 `rst_n` 端口**。真实 SRAM 硬宏无 RST 引脚，行为级模型不施加复位。
> - `cs` 为高有效信号，正常工作时需驱动为 `1`。
> - 当 `cs=0` 时，对应端口写操作被禁止，读输出保持前值。
> - 写操作受 `bwe` 逐位掩码，仅 `bwe[i]=1` 的位被写入。

| 信号名 | 位宽 | I/O | 时钟域 | 描述 |
|--------|------|-----|--------|------|
| `mem_a_clk` | 1 | I | `mem_a_clk` | Port A 工作时钟，上升沿触发 |
| `mem_a_cs` | 1 | I | `mem_a_clk` | **片选，高有效**。`1` 时选中 Port A，`0` 时禁用 |
| `mem_a_rwe` | 1 | I | `mem_a_clk` | **读写使能**。`1` = 写，`0` = 读 |
| `mem_a_bwe` | MEM_DATA_WIDTH | I | `mem_a_clk` | **逐位写使能，高有效**。`bwe[i]=1` 写入 bit i，`0` 保持原值 |
| `mem_a_addr` | MEM_ADDR_WIDTH | I | `mem_a_clk` | Port A 地址 |
| `mem_a_wdata` | MEM_DATA_WIDTH | I | `mem_a_clk` | Port A 写数据输入 |
| `mem_a_rdata` | MEM_DATA_WIDTH | O | `mem_a_clk` | Port A 读数据输出，1 拍延迟 |
| `mem_b_clk` | 1 | I | `mem_b_clk` | Port B 工作时钟，上升沿触发 |
| `mem_b_cs` | 1 | I | `mem_b_clk` | **片选，高有效**。`1` 时选中 Port B，`0` 时禁用 |
| `mem_b_rwe` | 1 | I | `mem_b_clk` | **读写使能**。`1` = 写，`0` = 读 |
| `mem_b_bwe` | MEM_DATA_WIDTH | I | `mem_b_clk` | **逐位写使能，高有效**。`bwe[i]=1` 写入 bit i，`0` 保持原值 |
| `mem_b_addr` | MEM_ADDR_WIDTH | I | `mem_b_clk` | Port B 地址 |
| `mem_b_wdata` | MEM_DATA_WIDTH | I | `mem_b_clk` | Port B 写数据输入 |
| `mem_b_rdata` | MEM_DATA_WIDTH | O | `mem_b_clk` | Port B 读数据输出，1 拍延迟 |

### 5.1 Port A 读写控制真值表

| `mem_a_cs` | `mem_a_rwe` | `mem_a_clk` 沿 | `mem_a_rdata` | 存储器状态 |
|:---:|:---:|:---|:---|:---|
| 1 | 1 | ↑ | 保持前值 | `mem_a_bwe[i]=1` 的位：`mem[mem_a_addr][i] <= mem_a_wdata[i]`（掩码写） |
| 1 | 0 | ↑ | `mem[mem_a_addr]` 寄存输出（1拍延迟） | 读操作 |
| 0 | x | ↑ | 保持前值 | 禁用，无操作 |

### 5.2 Port B 读写控制真值表

| `mem_b_cs` | `mem_b_rwe` | `mem_b_clk` 沿 | `mem_b_rdata` | 存储器状态 |
|:---:|:---:|:---|:---|:---|
| 1 | 1 | ↑ | 保持前值 | `mem_b_bwe[i]=1` 的位：`mem[mem_b_addr][i] <= mem_b_wdata[i]`（掩码写） |
| 1 | 0 | ↑ | `mem[mem_b_addr]` 寄存输出（1拍延迟） | 读操作 |
| 0 | x | ↑ | 保持前值 | 禁用，无操作 |

---

## 6. 时序图

### 6.1 写操作时序（Port A）

```
            T0      T1      T2      T3
            _       _       _       _
mem_a_clk _| |_____| |_____| |_____| |_

                 _____
mem_a_cs  ______/     \_________________

                 _____
mem_a_rwe ______/     \_________________

                 _____
mem_a_bwe ______/ 1s  \_________________
                    ↑       ↑
mem_a_addr    ──X  0x2  X───X  0x5  X────
mem_a_wdata   ──X  0xA5 X───X  0x3C X────
                    ↑       ↑
mem[2]             0xA5
mem[5]                     0x3C
```

**说明**：`mem_a_cs=1` 且 `mem_a_rwe=1` 时，时钟上升沿写入；`mem_a_bwe` 为高有效逐位写掩码，全 1 表示整字写入，仅 `mem_a_bwe[i]=1` 的位被更新。

### 6.2 同步读操作时序（Port B）

```
            T0      T1      T2      T3
            _       _       _       _
mem_b_clk _| |_____| |_____| |_____| |_

                 ____________________
mem_b_cs  ______/                    \_

         ________                    _
mem_b_rwe        \__________________/
                  ↑       ↑       ↑
mem_b_addr  ──X  0x2  X───X  0x5  X──
                  │       │       │
mem_b_rdata ────────X 0xA5 X───X 0x3C X
                         ↑       ↑
                      1拍延迟  1拍延迟
```

**说明**：`mem_b_cs=1` 且 `mem_b_rwe=0` 时执行读。T1 采样 `mem_b_addr=0x2`，T2 输出 `mem[0x2]`；T2 采样 `mem_b_addr=0x5`，T3 输出 `mem[0x5]`。

### 6.3 A 写 B 读跨时钟时序

```
            T0      T1      T2      T3      T4
            _       _       _       _       _
mem_a_clk _| |_____| |_____| |_____| |_____| |_

                 _____
mem_a_cs  ______/     \_______________________
                 _____
mem_a_rwe ______/     \_______________________
                 _____
mem_a_bwe ______/ 1s  \_______________________
                 ↑
mem_a_addr ──X  0x2  X───────────────────────
mem_a_wdata ──X  0xA5 X───────────────────────
                 ↑
mem[2]          0xA5

mem_b_clk  _____________________| |_____| |_____| |_____
                               ↑       ↑
mem_b_cs   ______________________/─────────────

mem_b_rwe ──────────────────────\______________
                                       ↑
mem_b_addr ──────────────────────X  0x2  X────
                                       │
mem_b_rdata ───────────────────────────X 0xA5 X
                                       ↑
                                    1拍延迟
```

**说明**：T1（`mem_a_clk`）写入 mem[2]=0xA5（`mem_a_cs=1`、`mem_a_rwe=1`、`mem_a_bwe=全1`）；T3（`mem_b_clk`）采样地址 0x2（`mem_b_cs=1`、`mem_b_rwe=0`），T4 输出 0xA5。两端口时钟独立，数据在各自时钟域传播。

### 6.4 并发读写时序（A 写 addr2，B 读 addr5）

```
         T0      T1      T2      T3
            _       _       _       _
mem_a_clk _| |_____| |_____| |_____| |_

                 _____
mem_a_cs  ______/     \________________
                 _____
mem_a_rwe ______/     \________________
                 _____
mem_a_bwe ______/ 1s  \________________
                 ↑
mem_a_addr ──X  0x2  X────────────────
mem_a_wdata ──X  0xA5 X────────────────
                 ↑
mem[2]          0xA5

mem_b_clk _| |_____| |_____| |_____| |_
                 ____________________
mem_b_cs  ______/                    \__
         ________                    _
mem_b_rwe        \__________________/
                 ↑       ↑
mem_b_addr ──X  0x5  X────────────────
                         │
mem_b_rdata ─────────────X 0x3C X────
                         ↑
                      B 口独立输出
```

**说明**：T1 `mem_a_clk` 沿写入 mem[2]=0xA5（`mem_a_cs=1`、`mem_a_rwe=1`）；同时 T1 `mem_b_clk` 沿采样 addr5（`mem_b_cs=1`、`mem_b_rwe=0`），T2 输出 mem[5]=0x3C。两端口完全独立，互不阻塞。

### 6.5 片选控制时序（Port A）

```
         T0      T1      T2      T3
            _       _       _       _
mem_a_clk _| |_____| |_____| |_____| |_

                 _____     _____
mem_a_cs  ______/     \___/     \______
               ____________
mem_a_rwe ____/            \__________
                    ↑       ↑       ↑
mem_a_addr    ──X  0x2  X───────X  0x5  X──
                    │               │
mem_a_rdata ───X 0xA5 X───X 0xA5 X──X 0x3C X
                    ↑       ↑       ↑
                 正常读   保持前值  恢复读
```

**说明**：同步模式下 `mem_a_cs=0` 时读操作被禁止，`mem_a_rdata` 保持前值（T2 保持 0xA5）。

### 6.6 逐位写掩码时序（Port A）

```
         T0      T1      T2      T3
            _       _       _       _
mem_a_clk _| |_____| |_____| |_____| |_

                 ____________
mem_a_cs  ______/            \__________

                 ____________
mem_a_rwe ______/            \__________

                 _____ _____
mem_a_bwe ______/ 1s  \_0xF0_\__________
                    ↑       ↑
mem_a_addr    ──X  0x2  X───X  0x2  X────
mem_a_wdata   ──X  0xFF X───X  0xAB X────
                    ↑       ↑
mem[2]             0xFF     0xAF（仅高 4 位更新）
```

**说明**：T1 整字写入 mem[2]=0xFF（`mem_a_bwe=全1`）；T2 掩码写（`mem_a_bwe=0xF0`），仅高 4 位更新为 0xA，低 4 位保持 0xF，mem[2] 变为 0xAF。

---

## 7. PPA

> **说明**：以下数据基于 TSMC 12nm 标准单元库和 Synopsys Design Compiler W-2024.09-SP3 综合获得。时钟周期约束为 2.0 ns（500 MHz），输入/输出延迟均为 0.6 ns（周期的 30%）。
>
> **综合模型说明**：行为级 RTL 在 `SYNTHESIS` 宏下回退为单时钟写模型（B 口写同步到 `mem_a_clk`），以避免 DC 对多驱动 reg 数组报错。以下面积为**参考值**，用于评估行为级实现规模；真实双口实现需使用 TSMC_12 硬宏。

**综合工具：** Synopsys Design Compiler W-2024.09-SP3  
**工艺库：** TSMC 12nm 标准单元库（具体库角落由后端提供）  
**综合策略：** 时钟周期约束 2.0 ns（500 MHz），输入/输出延迟 0.6 ns（周期的 30%）

### 7.1 配置 A：默认配置（MEM_DATA_WIDTH=32, MEM_ADDR_WIDTH=8）

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| MEM_DATA_WIDTH | 32 | 数据位宽 32 bit |
| MEM_ADDR_WIDTH | 8 | 存储深度 256 字 |
| 总容量 | 8,192 bit | 与 TSMC 硬宏 256×32 对齐 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 存储深度 | 256 字 |
| 总存储 bit | 8,192 bit |
| 读延迟 | 1 cycle |
| 写延迟 | 1 cycle |
| **面积** | **16,817.82 μm²** |
| 时序裕量 | **0.74 ns**（无 setup 违例） |
| 动态功耗 | 12.34 mW |
| 漏电功耗 | 87.69 μW |
| Sequential Cell | 8,256（8,192 bit 寄存器阵列 + 32 bit A 输出寄存器 + 32 bit B 输出寄存器） |
| 高扇出警告 | 1 个高扇出网络（`mem_a_clk`: 8,224 loads） |
| Macro Count | 0（寄存器阵列实现） |

---

### 7.2 配置 B：非默认数据位宽（MEM_DATA_WIDTH=16, MEM_ADDR_WIDTH=8）

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| MEM_DATA_WIDTH | 16 | 数据位宽 16 bit |
| MEM_ADDR_WIDTH | 8 | 存储深度 256 字 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 存储深度 | 256 字 |
| 总存储 bit | 4,096 bit |
| 读延迟 | 1 cycle |
| 写延迟 | 1 cycle |
| **面积** | **8,454.34 μm²** |
| 时序裕量 | **0.79 ns**（无 setup 违例） |
| 动态功耗 | 6.18 mW |
| 漏电功耗 | 43.97 μW |
| Sequential Cell | 4,128（4,096 bit 寄存器阵列 + 16 bit A 输出寄存器 + 16 bit B 输出寄存器） |
| 高扇出警告 | 1 个高扇出网络（`mem_a_clk`: 4,112 loads） |
| Macro Count | 0 |

---

### 7.3 配置 C：小容量行为级（MEM_DATA_WIDTH=8, MEM_ADDR_WIDTH=4）

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| MEM_DATA_WIDTH | 8 | 数据位宽 8 bit |
| MEM_ADDR_WIDTH | 4 | 存储深度 16 字 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 存储深度 | 16 字 |
| 总存储 bit | 128 bit |
| 读延迟 | 1 cycle |
| 写延迟 | 1 cycle |
| **面积** | **294.96 μm²** |
| 时序裕量 | **1.05 ns**（无 setup 违例） |
| 动态功耗 | 228.00 μW |
| 漏电功耗 | 1.60 μW |
| Sequential Cell | 144（128 bit 寄存器阵列 + 8 bit A 输出寄存器 + 8 bit B 输出寄存器） |
| Macro Count | 0 |

---

### 7.4 配置 D：大容量行为级（MEM_DATA_WIDTH=64, MEM_ADDR_WIDTH=10）

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| MEM_DATA_WIDTH | 64 | 数据位宽 64 bit |
| MEM_ADDR_WIDTH | 10 | 存储深度 1024 字 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 存储深度 | 1024 字 |
| 总存储 bit | 65,536 bit |
| 读延迟 | 1 cycle |
| 写延迟 | 1 cycle |
| **面积** | **136,948.93 μm²** |
| 时序裕量 | **0.46 ns**（无 setup 违例） |
| 动态功耗 | 98.07 mW |
| 漏电功耗 | 720.12 μW |
| Sequential Cell | 65,664（65,536 bit 寄存器阵列 + 64 bit A 输出寄存器 + 64 bit B 输出寄存器） |
| 高扇出警告 | 65 个高扇出网络（`mem_a_clk`: 65,600 loads, `mem_a_wdata`/`mem_b_wdata` 每 bit: 1,024 loads） |
| Macro Count | 0（寄存器阵列实现） |

**建议**：1024 字深度行为级面积过大，**强烈建议启用 TSMC 硬宏或拆分为多个 Bank**。

---

### 7.5 配置 E：极端最小配置（MEM_DATA_WIDTH=1, MEM_ADDR_WIDTH=1）

**参数设置：**

| 参数 | 设置值 | 说明 |
|------|--------|------|
| MEM_DATA_WIDTH | 1 | 数据位宽 1 bit |
| MEM_ADDR_WIDTH | 1 | 存储深度 2 字 |

**PPA 数据：**

| 项目 | 数值 |
|------|------|
| 存储深度 | 2 字 |
| 总存储 bit | 2 bit |
| 读延迟 | 1 cycle |
| 写延迟 | 1 cycle |
| **面积** | **7.19 μm²** |
| 时序裕量 | **1.21 ns**（无 setup 违例） |
| 动态功耗 | 6.36 μW |
| 漏电功耗 | 39.10 nW |
| Sequential Cell | 4（2 bit 寄存器阵列 + 1 bit A 输出寄存器 + 1 bit B 输出寄存器） |
| Macro Count | 0 |

---

### 7.6 TSMC_12 硬宏对比（256×32 真双口宏）

| 指标 | 行为级（标准单元，参考值） | TSMC_12 硬宏 |
|------|---------------------------|-------------|
| 面积 | ~16,818 μm² | 待实测（需 LEF/Lib 数据） |
| 访问延迟 | 1 cycle + MUX 逻辑 | 1 cycle + 固定宏延迟 |
| 功耗 | 较高（DFF 阵列动态功耗大） | 较低（专用 SRAM 结构） |
| 时序稳定性 | 依赖综合策略 | 固定，已 Characterized |
| 真双口并发 | 行为级支持（参考模型） | 硬件原生支持（独立 CLKA/CLKB） |

> **注意**：DC 综合时 `TSMC_12` 宏未启用（仿真宏），上述行为级面积为单时钟参考模型。若需硬宏面积，需在 DC 中读入 `.v` 模型并 `set_dont_touch`，或从后端 LEF 获取。

---

### 7.7 综合映射说明

| 深度范围 | 综合工具典型映射 | 说明 |
|----------|-----------------|------|
| ≤ 64 字 | DFF 阵列 | 综合工具推断为寄存器阵列，面积随深度线性增长 |
| 64 ~ 256 字 | 分布式 RAM / LUT-RAM | 面积与性能的折中，适用于 FPGA |
| > 256 字 | SRAM 宏 | 需目标工艺库支持，面积最优，访问速度略慢 |

### 7.8 时序说明

- **同步读模式**：关键路径为 `addr` → 地址译码 → 存储阵列 MUX → 输出寄存器建立时间。输出端时序裕量随容量增加而减小（32×8 为 0.74 ns，64×10 为 0.46 ns）。
- **片选路径**：`mem_a_cs` / `mem_b_cs` 到 `rdata` 为同步逻辑，需满足到各自 `clk` 的建立时间要求。
- **写操作时序**：`wdata` 与 `addr` 需在时钟沿前满足建立时间要求。
- **并发读写时序**：写端口与读端口独立，关键路径互不干扰。同一周期读写不同地址时，两者延迟与独立操作一致。
- **高扇出网络**：大容量配置（Config D）中 `mem_a_clk` 负载达 65,600+，后端需做时钟树综合（CTS）和写数据网络缓冲。

### 7.9 综合 Warning 说明

| Warning 编号 | 描述 | 影响 | 建议 |
|-------------|------|------|------|
| VER-281 | DC 忽略 RTL 内 `initial` 块 | 无功能影响 | 预期行为，无需处理 |
| PWR-536 / PWR-24 | tie cell 无内部功耗表征 | 功耗报告精度降低 | 使用完整 .lib 时自动消除 |
| OPT-1208 | 开启时序输出反相 | 形式验证需 SVF 文件 | 保留 `.svf` 文件用于 Formality |
| TIM-134 | 高扇出网络（clk / wdata） | 后端布线压力 | 大容量配置需评估 SRAM 宏替代 |

---

---

> **公开分发说明**：本文中的工艺宏型号、宏时序库名与工艺库角落名均以占位形式给出（`CBB_SRAM_*` / `CBB_ROM_*` / "TSMC 12nm 标准单元库"）。实际型号由后端 Memory Compiler 与所选工艺库决定；接入时请按宏 databook 复核固定接值（`RTSEL` / `WTSEL` / `PTSEL` / `BWEB*` 等）与端口极性，以及 `Port A/B` 的读写分工。
