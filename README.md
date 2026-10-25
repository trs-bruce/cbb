# CBB — 特瑞思可复用 IP 模块库（开源部分）

**成都市特瑞思科技有限公司（TeraSilicon）** CBB（Common Building Block）库的开源专区。这里的每个模块都来自**经过完整验证**的企业级 IP 库（UT 覆盖率、SpyGlass lint、DC 综合 PPA），覆盖跨时钟域（CDC）、编码、FIFO、计数器、仲裁、时钟复位、整数/浮点运算、存储与 SIMD 等主题。

配套讲解见微信公众号 **「成都市特瑞思科技有限公司」** 系列文章 **《CBB 每日一讲》**（每天拆解一个模块：解决什么问题、设计好在哪里、边界在哪里）。

## 目录结构

按主题分组，每组一个目录；每个模块一个子目录，内含 RTL 源码与用户指南（UG），图随文放在 `figures/`：

```
cbb/
├── README.md / LICENSE
├── cdc/                          # CDC 与编码基础
│   ├── cbb_cdc_define.v          # CDC 家族公共宏定义
│   ├── cbb_bin2gray/
│   │   ├── cbb_bin2gray.v        # RTL 源码
│   │   └── cbb_bin2gray_ug.md    # 用户指南
│   ├── cbb_gray2bin/
│   │   └── ...
│   ├── cbb_cdc_lvl/
│   ├── cbb_cdc_lvl_fb/
│   ├── cbb_cdc_edge_r/
│   │   ├── cbb_cdc_edge_r.v
│   │   ├── cbb_cdc_edge_r_ug.md
│   │   └── figures/cbb_cdc_edge_r_timing.svg
│   ├── cbb_cdc_edge_f/
│   ├── cbb_8b10b_enc/
│   │   ├── cbb_8b10b_enc.v
│   │   ├── cbb_8b10b_enc_ug.md
│   │   └── figures/cbb_8b10b_enc_wave_*.png
│   ├── cbb_8b10b_dec/
│   ├── cbb_8b10b_unbal/
│   ├── cbb_4b5b_enc/
│   │   ├── cbb_4b5b_enc.v
│   │   ├── cbb_4b5b_enc_ug.md
│   │   └── figures/cbb_4b5b_enc_wave_*.png
│   ├── cbb_4b5b_dec/
│   ├── cbb_4b5b_unbal/
│   ├── cbb_parity/
│   ├── cbb_crc_p/
│   └── cbb_crc_s/
└── （更多主题分组随系列推进陆续开放）
```

## 已开放模块

| 模块 | 说明 | 对应系列文章 |
| --- | --- | --- |
| `cbb_bin2gray` | 二进制→格雷码编码器（纯组合） | 第 1 期 |
| `cbb_gray2bin` | 格雷码→二进制译码器 | 第 2 期 |
| `cbb_cdc_lvl` | 单比特电平同步器（参数化同步链） | 第 3 期 |
| `cbb_cdc_lvl_fb` | 电平同步器·反馈版（带送达确认） | 第 4 期 |
| `cbb_cdc_edge_r` | 上升沿同步器（事件→单拍脉冲） | 第 5 期 |
| `cbb_cdc_edge_f` | 下降沿同步器（完成/撤销通知） | 第 6 期 |
| `cbb_cdc_p2p` | 脉冲同步器（Toggle 编码，快/慢速可配） | 第 7 期 |
| `cbb_cdc_gray` | 格雷码同步器（多比特总线跨域，相邻值仅 1 bit 变化） | 第 8 期 |
| `cbb_cdc_demux_lvl` | 电平选通型 DMUX 同步器（数据钉死直穿 + valid 同步链选通） | 第 9 期 |
| `cbb_cdc_demux_lvl_fb` | 带反馈的电平选通型 DMUX 同步器（目的域 ack 回传，源端收到 ack 才撤 valid） | 第 10 期 |
| `cbb_cdc_demux_pul_l` | 脉冲触发型 DMUX 同步器（源端电平打拍测沿成脉冲，同步链搬 toggle，目的域恢复单周期脉冲） | 第 11 期 |
| `cbb_cdc_demux_pul_p` | 脉冲直通型 DMUX 同步器（源端脉冲直接翻转 toggle，链路最短） | 第 12 期 |
| `cbb_cdc_demux_pul_fb` | 带反馈握手的脉冲 DMUX 同步器（目的域 ack 单拍回执，源端 req 闭环清零） | 第 13 期 |
| `cbb_afifo` | 异步 FIFO（Gray 码指针跨域 + 双口共享存储，Show-ahead 读） | 第 14 期 |
| `cbb_8b10b_enc` | 8b/10b 编码器（IEEE 802.3 Clause 36，RD 状态机，5b/6b + 3b/4b 结构化子编码） | 第 17 期 |
| `cbb_8b10b_dec` | 8b/10b 解码器（码表解码 + K 码识别 + 非法码字/RD 校验，528-bit 精简 ROM） | 第 18 期 |
| `cbb_8b10b_unbal` | 8b/10b 平衡预测器（BM0 范围预判 / BM1 与编码器逐符号精确一致的 RD 级联模型） | 第 19 期 |
| `cbb_4b5b_enc` | 4b/5b 编码器（IEEE 802.3 Clause 24 / FDDI，32×5 查找表，无 RD 状态机） | 第 20 期 |
| `cbb_4b5b_dec` | 4b/5b 解码器（码表逆映射 + 非法码字检测，6 控制码 / 10 非法码） | 第 21 期 |
| `cbb_4b5b_unbal` | 4b/5b 平衡预测器（跳变密度与 ones 计数预判，无状态查表） | 第 22 期 |
| `cbb_parity` | 参数化奇/偶校验生成器（1~256 bit，纯组合 XOR/XNOR 归约树） | 第 23 期 |
| `cbb_crc_p` | 并行组合 CRC 生成/校验器（多项式 2~64 bit、数据 1~2560 bit、双支路中间余数比对） | 第 24 期 |
| `cbb_crc_s` | 串行 CRC 生成/校验器（drain 排空发送、上下文切换、逐拍比较校验、stall 保持） | 第 25 期 |

## 使用说明

- **许可证**：Apache-2.0，可自由用于商业与非商业项目（详见 [LICENSE](LICENSE)）。
- **源码定位**：本仓库源码用于**分享与评审**，模块引用的 CDC 公共宏在同组目录的 `cbb_cdc_define.v`；仿真/综合环境（testbench、filelist、脚本）不随本仓库提供。
- **工艺相关**：RTL 中 TSMC 12nm 等工艺宏分支（`TSMC_12` / `FPGA_XILINX` / `FPGA_ALTERA`）保留用于参考，默认 RTL 分支无任何工艺依赖。
- **质量口径**：每个模块的企业级验证报告（UT 覆盖率、SpyGlass lint、DC 综合 PPA）随系列文章讲解，摘要见各期文章。

## 联系我们

- 商务合作 / IP 定制：微信公众号「成都市特瑞思科技有限公司」后台留言
- 问题反馈：GitHub Issues

*© 2026 成都市特瑞思科技有限公司（TeraSilicon, Inc.）*
