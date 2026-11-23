// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026-07-24
// Description  : Two-Port Synchronous RAM (2PRF / Simple Dual Port)
//                Port A write with per-bit write enable, Port B read.
//                Independent clocks (mem_a_clk / mem_b_clk).
//                Default config 256x32 matches TSMC hard macro.
//                For larger capacity, instantiate multiple CBB_RAM_TP
//                at upper level and perform address/data banking externally.
//                Supports TSMC_12 / FPGA_XILINX / FPGA_ALTERA macros.
// =====================================================================================================================

`ifndef CBB_RAM_TP_V
`define CBB_RAM_TP_V

module CBB_RAM_TP
  #(
   parameter MEM_DATA_WIDTH                      = 32,                         // Data width (TSMC macro: 32 bits)
   parameter MEM_ADDR_WIDTH                      = 8,                          // Address width (TSMC macro: 256 words, 2^8)
   parameter INIT_FILE                           = ""
   )
   (
   input                                         mem_a_clk,                    // Write clock (Port A)
   input                                         mem_b_clk,                    // Read clock (Port B)
   input                                         mem_a_cs,                     // Port A chip select, active-high (1: valid)
   input                                         mem_b_cs,                     // Port B chip select, active-high (1: valid)
   input                                         mem_a_we,                     // Port A write enable, active-high (1: write, 0: no-op)
   input           [MEM_DATA_WIDTH-1:0]          mem_a_bwe,                    // Port A bit write enable, active-high (1: write bit, 0: keep old)
   input           [MEM_ADDR_WIDTH-1:0]          mem_a_addr,                   // Port A write address
   input           [MEM_DATA_WIDTH-1:0]          mem_a_wdata,                  // Port A write data
   input           [MEM_ADDR_WIDTH-1:0]          mem_b_addr,                   // Port B read address
   output reg      [MEM_DATA_WIDTH-1:0]          mem_b_rdata                   // Port B read data (1-cycle latency)
   );

localparam MEM_DEPTH                             = (1 << MEM_ADDR_WIDTH);      // 2^MEM_ADDR_WIDTH words

integer                                          i;                            // bit index for mem_a_bwe masked write

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
wire                                             macro_web_n;
wire                                             macro_reb_n;
wire               [MEM_DATA_WIDTH-1:0]          macro_bweb_n;
`endif

`ifdef TSMC_12
// ----------------------------------------------------------------------------------------------------------------------
// TSMC 12nm 2PRF Hard Macro
// Macro      : CBB_SRAM_256X32_2P (256 words x 32 bits)
// Type       : 2PRF (Simple Dual Port) — Port A write, Port B read
// Strategy   : CBB layer directly instantiates ONE macro; no internal banking.
//              If the caller needs larger capacity, instantiate multiple
//              CBB_RAM_TP at the upper level and bank externally.
// Polarity   : WEB/REB/BWEB are all active-low (confirmed by MC Verilog model).
//              WEB  = ~(mem_a_cs & mem_a_we), REB = ~mem_b_cs, BWEB = ~mem_a_bwe.
// Clocking   : CLKW driven by mem_a_clk (write), CLKR driven by mem_b_clk (read).
//              Independent clocks support synchronous or asynchronous operation.
// Constraint : MEM_ADDR_WIDTH must be 8 and MEM_DATA_WIDTH must be 32 for TSMC macro.
// ----------------------------------------------------------------------------------------------------------------------

// Active-low macro controls; preserve bitwise four-state behavior.
assign macro_web_n      = ~(mem_a_cs & mem_a_we);
assign macro_reb_n      = ~mem_b_cs;
assign macro_bweb_n     = ~mem_a_bwe;

// NAME_INS01/02 exception: synthesis scripts target u_tsmc_tp_ram by hierarchical name.
CBB_SRAM_256X32_2P
u_tsmc_tp_ram
(
.CLKW                                  ( mem_a_clk                             ),
.CLKR                                  ( mem_b_clk                             ),
.AA                                    ( mem_a_addr                            ),
.AB                                    ( mem_b_addr                            ),
.D                                     ( mem_a_wdata                           ),
.Q                                     ( mem_b_rdata                           ),
.WEB                                   ( macro_web_n                           ), // 0: write enable (mem_a_cs=1 & mem_a_we=1)
.REB                                   ( macro_reb_n                           ), // 0: read enable (mem_b_cs=1)
.BWEB                                  ( macro_bweb_n                          ), // 0: bit write-enabled (mem_a_bwe[i]=1 writes bit i)
// BIST mode ports (disable)
.BIST                                  ( 1'b0                                  ),
.AMA                                   ( BIST_ADDR_ZERO                        ),
.AMB                                   ( BIST_ADDR_ZERO                        ),
.DM                                    ( BIST_DATA_ZERO                        ),
.BWEBM                                 ( BIST_DATA_ZERO                        ),
.WEBM                                  ( 1'b1                                  ),
.REBM                                  ( 1'b1                                  ),
// Power management (normal mode)
.SLP                                   ( 1'b0                                  ),
.DSLP                                  ( 1'b0                                  ),
.SD                                    ( 1'b0                                  ),
// Test / trim pins: fixed values required by the delivered 256x32 M1 macro model.
.RCT                                   ( 2'b01                                 ),
.WCT                                   ( 2'b01                                 ),
.KP                                    ( 3'b011                                ),
// Output (unconnected)
.PUDELAY                               (                                       )
);

`else
// ----------------------------------------------------------------------------------------------------------------------
// Behavioral Logic
// ----------------------------------------------------------------------------------------------------------------------

// ----------------------------------------------------------------------------------------------------------------------
// Write Port (A) — driven by mem_a_clk, per-bit masked by mem_a_bwe
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge mem_a_clk)
begin : MEM_WRITE_PROC
  if ((mem_a_cs == 1'b1) && (mem_a_we == 1'b1))
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

// ----------------------------------------------------------------------------------------------------------------------
// Read Port (B) — driven by mem_b_clk
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge mem_b_clk)
begin : MEM_READ_PROC
  if (mem_b_cs == 1'b1)
  begin
    mem_b_rdata         <= mem[mem_b_addr];
  end
end

`endif

// ----------------------------------------------------------------------------------------------------------------------
// Assertions
// ----------------------------------------------------------------------------------------------------------------------
`ifdef SOC_ASSERT_ON
  `ifdef CBB_RAM_TP_ASSERT_ON
    `include "cbb_ram_tp_assert.sv"
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
// V1.1         | 2026-07-31 | CBB Team     | Added csn/cen ports, ADDR_WIDTH as parameter
// V1.2         | 2026-08-13 | CBB Team     | 2PRF, 256x32, aligned with TSMC macro
// V1.3         | 2026-08-18 | CBB Team     | Unified port naming (cs_n -> csn)
// V1.4         | 2026-08-25 | CBB Team     | Interface upgrade: split mem_csn into per-port mem_a_cs/mem_b_cs (active-high), mem_a_wen -> mem_a_we (active-high), removed mem_b_ren (covered by mem_b_cs), added mem_a_bwe per-bit write mask; parameters renamed to MEM_*; TSMC_12 macro mapping inverted accordingly (WEB/REB/BWEB)
// V1.5         | 2026-09-21 | CBB Team     | Normalize RTL style, name loops and extract macro control expressions
// V1.6         | 2026-09-23 | CBB Team     | Refine assignment alignment and comments; no functional change
// V1.7         | 2026-09-24 | CBB Team     | Move simulation memory initialization to TB assertion include
// V1.8         | 2026-09-24 | CBB Team     | Move parameter legality checks to TB assertion include
// V1.9         | 2026-09-30 | CBB Team     | Match TSMC 2PRF test/trim ties to delivered macro model
// V1.10        | 2026-11-03 | CBB Team     | Header template alignment: copyright, designer, project tag and non-template fields
// ======================================================================================================================
