// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026-07-24
// Description  : True Dual Port Synchronous RAM (DP SRAM)
// NOTE         : Foundry hard-macro model names and library corner names are replaced by neutral
//               placeholders for public distribution. Bind the memory-compiler output of your own
//               process at the placeholder instance, and re-check the fixed tie-off values against
//               your macro databook.
// =====================================================================================================================

`ifndef CBB_RAM_DP_V
`define CBB_RAM_DP_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
//                True Dual Port: Both Port A and Port B can read/write independently.
//                No reset port — aligned with real SRAM hard macro behavior.
//                Supports TSMC_12 / FPGA_XILINX / FPGA_ALTERA macros.
// ---------------------------------------------------------------------------------------------------------------------

module CBB_RAM_DP
  #(
   parameter MEM_DATA_WIDTH                      = 32,                         // Data width (TSMC macro: 32 bits)
   parameter MEM_ADDR_WIDTH                      = 8,                          // Address width (TSMC macro: 256 words, 2^8)
   parameter INIT_FILE                           = ""
   )
   (
   input                                         mem_a_clk,                    // Port A clock
   input                                         mem_a_cs,                     // Port A chip select, active-high (1: valid)
   input                                         mem_a_rwe,                    // Port A read/write enable, 1: write, 0: read
   input           [MEM_DATA_WIDTH-1:0]          mem_a_bwe,                    // Port A bit write enable, active-high (1: write bit, 0: keep old)
   input           [MEM_ADDR_WIDTH-1:0]          mem_a_addr,                   // Port A read/write address
   input           [MEM_DATA_WIDTH-1:0]          mem_a_wdata,                  // Port A write data
   output reg      [MEM_DATA_WIDTH-1:0]          mem_a_rdata,                  // Port A read data (1-cycle latency)

   input                                         mem_b_clk,                    // Port B clock
   input                                         mem_b_cs,                     // Port B chip select, active-high (1: valid)
   input                                         mem_b_rwe,                    // Port B read/write enable, 1: write, 0: read
   input           [MEM_DATA_WIDTH-1:0]          mem_b_bwe,                    // Port B bit write enable, active-high (1: write bit, 0: keep old)
   input           [MEM_ADDR_WIDTH-1:0]          mem_b_addr,                   // Port B read/write address
   input           [MEM_DATA_WIDTH-1:0]          mem_b_wdata,                  // Port B write data
   output reg      [MEM_DATA_WIDTH-1:0]          mem_b_rdata                   // Port B read data (1-cycle latency)
   );

localparam MEM_DEPTH                             = (1 << MEM_ADDR_WIDTH);      // 2^MEM_ADDR_WIDTH words

integer                                          i;                            // Port A bit index / synthesis word index
integer                                          j;                            // Port B bit index / synthesis bit index

// ----------------------------------------------------------------------------------------------------------------------
// Memory Array
// ----------------------------------------------------------------------------------------------------------------------

`ifdef FPGA_XILINX
(* ram_style = "block" *)
`elsif FPGA_ALTERA
(* ramstyle = "M20K" *)
`endif
reg                [MEM_DATA_WIDTH-1:0]          mem [0:MEM_DEPTH-1];

// NAME_SIG09 exception: retain public mem_* clock names for existing callers.
`ifdef TSMC_12
localparam         [MEM_ADDR_WIDTH-1:0]          BIST_ADDR_ZERO = {MEM_ADDR_WIDTH{1'b0}};
localparam         [MEM_DATA_WIDTH-1:0]          BIST_DATA_ZERO = {MEM_DATA_WIDTH{1'b0}};
wire                                             macro_ceba_n;
wire                                             macro_weba_n;
wire               [MEM_DATA_WIDTH-1:0]          macro_bweba_n;
wire                                             macro_cebb_n;
wire                                             macro_webb_n;
wire               [MEM_DATA_WIDTH-1:0]          macro_bwebb_n;
`endif

`ifdef TSMC_12
// ----------------------------------------------------------------------------------------------------------------------
// TSMC 12nm SRAM Hard Macro (256x32)
// Polarity   : CEB/WEB/BWEB are all active-low (confirmed by MC Verilog model).
//              CEBA = ~mem_a_cs, WEBA = ~mem_a_rwe, BWEBA = ~mem_a_bwe; Port B likewise.
// Constraint : MEM_ADDR_WIDTH must be 8 and MEM_DATA_WIDTH must be 32 for TSMC macro.
// ----------------------------------------------------------------------------------------------------------------------

// Active-low macro controls; preserve bitwise four-state behavior.
assign macro_ceba_n     = ~mem_a_cs;
assign macro_weba_n     = ~mem_a_rwe;
assign macro_bweba_n    = ~mem_a_bwe;
assign macro_cebb_n     = ~mem_b_cs;
assign macro_webb_n     = ~mem_b_rwe;
assign macro_bwebb_n    = ~mem_b_bwe;

CBB_SRAM_256X32_DP
U_CBB_SRAM_256X32_DP
(
.SLP                                   ( 1'b0                                  ),
.DSLP                                  ( 1'b0                                  ),
.SD                                    ( 1'b0                                  ),
.PUDELAY                               (                                       ),
.WTSEL                                 ( 2'b01                                 ),
.RTSEL                                 ( 2'b01                                 ),
.AA                                    ( mem_a_addr                            ),
.DA                                    ( mem_a_wdata                           ),
.BWEBA                                 ( macro_bweba_n                         ), // 0: bit write-enabled (mem_a_bwe[i]=1 writes bit i)
.WEBA                                  ( macro_weba_n                          ), // 0: write enable (mem_a_cs=1 & mem_a_rwe=1)
.CEBA                                  ( macro_ceba_n                          ), // 0: chip enable
.CLKA                                  ( mem_a_clk                             ),
.AB                                    ( mem_b_addr                            ),
.DB                                    ( mem_b_wdata                           ),
.BWEBB                                 ( macro_bwebb_n                         ), // 0: bit write-enabled (mem_b_bwe[i]=1 writes bit i)
.WEBB                                  ( macro_webb_n                          ), // 0: write enable (mem_b_cs=1 & mem_b_rwe=1)
.CEBB                                  ( macro_cebb_n                          ), // 0: chip enable
.CLKB                                  ( mem_b_clk                             ),
.AMA                                   ( BIST_ADDR_ZERO                        ),
.DMA                                   ( BIST_DATA_ZERO                        ),
.BWEBMA                                ( BIST_DATA_ZERO                        ),
.WEBMA                                 ( 1'b1                                  ),
.CEBMA                                 ( 1'b1                                  ),
.AMB                                   ( BIST_ADDR_ZERO                        ),
.DMB                                   ( BIST_DATA_ZERO                        ),
.BWEBMB                                ( BIST_DATA_ZERO                        ),
.WEBMB                                 ( 1'b1                                  ),
.CEBMB                                 ( 1'b1                                  ),
.BIST                                  ( 1'b0                                  ),
.CLKM                                  ( 1'b0                                  ),
.QA                                    ( mem_a_rdata                           ),
.QB                                    ( mem_b_rdata                           )
);

`else
// ----------------------------------------------------------------------------------------------------------------------
// Behavioral Logic
// ----------------------------------------------------------------------------------------------------------------------

`ifndef SYNTHESIS
// ----------------------------------------------------------------------------------------------------------------------
// True Dual-Port Write (simulation only)
// Both ports can write independently with separate clocks.
// Each port write is per-bit masked by its own mem_x_bwe.
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge mem_a_clk)
begin : MEM_A_WRITE_PROC
  if ((mem_a_cs == 1'b1) && (mem_a_rwe == 1'b1))
  begin
    for (i = 0; i < MEM_DATA_WIDTH; i = i + 1)
    begin : WRITE_A_BIT_LOOP
      if (mem_a_bwe[i] == 1'b1)
      begin
        mem[mem_a_addr][i]    <= mem_a_wdata[i];
      end
    end
  end
end

always @(posedge mem_b_clk)
begin : MEM_B_WRITE_PROC
  if ((mem_b_cs == 1'b1) && (mem_b_rwe == 1'b1))
  begin
    for (j = 0; j < MEM_DATA_WIDTH; j = j + 1)
    begin : WRITE_B_BIT_LOOP
      if (mem_b_bwe[j] == 1'b1)
      begin
        mem[mem_b_addr][j]    <= mem_b_wdata[j];
      end
    end
  end
end
`else
// ----------------------------------------------------------------------------------------------------------------------
// Synthesis-Friendly Single-Clock Write Model
// Note: For true dual-port implementation, use TSMC_12 hard macro.
// This model merges B-port write into mem_a_clk domain for DC compatibility.
// Decode each word and bit separately so writes to different addresses remain independent.
// For the same address and enabled bit, Port B has priority over Port A.
// Zero-extend addresses for comparison with the 32-bit integer word index.
// Area/timing numbers are reference values only.
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge mem_a_clk)
begin : MEM_WRITE_PROC
  for (i = 32'sd0; i < MEM_DEPTH; i = i + 32'sd1)
  begin : WRITE_WORD_LOOP
    for (j = 32'sd0; j < MEM_DATA_WIDTH; j = j + 32'sd1)
    begin : WRITE_BIT_LOOP
      if ((mem_b_cs == 1'b1) && (mem_b_rwe == 1'b1) &&
      ({{(32'sd32-MEM_ADDR_WIDTH){1'b0}}, mem_b_addr} == i) && (mem_b_bwe[j] == 1'b1))
      begin
        mem[i][j]       <= mem_b_wdata[j];
      end
      else if ((mem_a_cs == 1'b1) && (mem_a_rwe == 1'b1) &&
      ({{(32'sd32-MEM_ADDR_WIDTH){1'b0}}, mem_a_addr} == i) && (mem_a_bwe[j] == 1'b1))
      begin
        mem[i][j]       <= mem_a_wdata[j];
      end
    end
  end
end
`endif

// ----------------------------------------------------------------------------------------------------------------------
// Port A Read
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge mem_a_clk)
begin : MEM_A_READ_PROC
  if ((mem_a_cs == 1'b1) && (mem_a_rwe == 1'b0))
  begin
    mem_a_rdata         <= mem[mem_a_addr];
  end
end

// ----------------------------------------------------------------------------------------------------------------------
// Port B Read
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge mem_b_clk)
begin : MEM_B_READ_PROC
  if ((mem_b_cs == 1'b1) && (mem_b_rwe == 1'b0))
  begin
    mem_b_rdata         <= mem[mem_b_addr];
  end
end

`endif

// ----------------------------------------------------------------------------------------------------------------------
// Assertions
// ----------------------------------------------------------------------------------------------------------------------
`ifdef SOC_ASSERT_ON
  `ifdef CBB_RAM_DP_ASSERT_ON
    `include "cbb_ram_dp_assert.sv"
  `endif
`endif

endmodule

`endif

// ======================================================================================================================
// Revision History
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// ----------------------------------------------------------------------------------------------------------------------
// V1.0         | 2026-07-24 | CBB Team     | Initial release
// V1.1         | 2026-07-31 | CBB Team     | Added cs_n/cen ports
// V1.2         | 2026-08-10 | CBB Team     | Aligned with CBB_RAM_SP v3.0
// V1.3         | 2026-08-25 | CBB Team     | Interface upgrade: mem_x_csn -> mem_x_cs (active-high), mem_x_wen (1: read) -> mem_x_rwe (1: write); parameters renamed to MEM_*; added mem_a_bwe/mem_b_bwe per-bit write masks; TSMC_12 macro mapping inverted accordingly (CEB/WEB/BWEB)
// V1.4         | 2026-09-21 | CBB Team     | Normalize RTL style, name loops and extract macro control expressions
// V1.5         | 2026-09-23 | CBB Team     | Refine assignment alignment and comments; no functional change
// V1.6         | 2026-09-24 | CBB Team     | Move simulation memory initialization to TB assertion include
// V1.7         | 2026-09-24 | CBB Team     | Move parameter legality checks to TB assertion include
// V1.8         | 2026-09-28 | CBB Team     | Make synthesis write priority explicit per word and bit
// V1.9         | 2026-11-03 | CBB Team     | Header template alignment: copyright, designer, project tag and non-template fields
// ======================================================================================================================
