// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026-07-24
// Description  : Single Port Synchronous RAM (SP SRAM)
//                Synchronous write, synchronous read (1-cycle latency).
//                Supports TSMC_12 / FPGA_XILINX / FPGA_ALTERA macros.
// NOTE         : Foundry hard-macro model names and library corner names are replaced by neutral
//               placeholders for public distribution. Bind the memory-compiler output of your own
//               process at the placeholder instance, and re-check the fixed tie-off values against
//               your macro databook.
// =====================================================================================================================

`ifndef CBB_RAM_SP_V
`define CBB_RAM_SP_V

module CBB_RAM_SP
  #(
   parameter MEM_DATA_WIDTH                      = 8,                          // Data width
   parameter MEM_ADDR_WIDTH                      = 4,                          // Address width
   parameter INIT_FILE                           = ""
   )
   (
   input                                         mem_clk,                      // Write/Read clock
   input                                         mem_cs,                       // Chip select, active-high (1: valid)
   input                                         mem_rwe,                      // Read/Write enable, 1: write, 0: read
   input           [MEM_DATA_WIDTH-1:0]          mem_bwe,                      // Bit write enable, active-high (1: write bit, 0: keep old)
   input           [MEM_ADDR_WIDTH-1:0]          mem_addr,                     // Read/Write address
   input           [MEM_DATA_WIDTH-1:0]          mem_wdata,                    // Write data
   output reg      [MEM_DATA_WIDTH-1:0]          mem_rdata                     // Read data output (1-cycle latency)
   );

localparam MEM_DEPTH                             = (1 << MEM_ADDR_WIDTH);

integer                                          i;                            // bit index for mem_bwe masked write

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
wire                                             macro_ceb_n;
wire                                             macro_web_n;
wire               [MEM_DATA_WIDTH-1:0]          macro_bweb_n;
`endif

`ifdef TSMC_12
// ----------------------------------------------------------------------------------------------------------------------
// TSMC 12nm SRAM Hard Macro (16x8)
// Constraint : MEM_ADDR_WIDTH must be 4 and MEM_DATA_WIDTH must be 8 for TSMC macro.
// ----------------------------------------------------------------------------------------------------------------------

// Active-low macro controls; preserve bitwise four-state behavior.
assign macro_ceb_n      = ~mem_cs;
assign macro_web_n      = ~mem_rwe;
assign macro_bweb_n     = ~mem_bwe;

CBB_SRAM_16X8_1P
U_CBB_SRAM_16X8_1P
(
.CLK                                   ( mem_clk                               ),
.CEB                                   ( macro_ceb_n                           ),
.WEB                                   ( macro_web_n                           ),
.A                                     ( mem_addr                              ),
.D                                     ( mem_wdata                             ),
.Q                                     ( mem_rdata                             ),
.BWEB                                  ( macro_bweb_n                          ),
.BIST                                  ( 1'b0                                  ),
.CEBM                                  ( 1'b1                                  ),
.WEBM                                  ( 1'b1                                  ),
.AM                                    ( BIST_ADDR_ZERO                        ),
.DM                                    ( BIST_DATA_ZERO                        ),
.BWEBM                                 ( BIST_DATA_ZERO                        ),
.RTSEL                                 ( 2'b01                                 ),
.WTSEL                                 ( 2'b01                                 ),
.SLP                                   ( 1'b0                                  ),
.DSLP                                  ( 1'b0                                  ),
.SD                                    ( 1'b0                                  ),
.PUDELAY                               (                                       )
);

`else
// ----------------------------------------------------------------------------------------------------------------------
// Behavioral Logic
// ----------------------------------------------------------------------------------------------------------------------

always @(posedge mem_clk)
begin : MEM_READ_PROC
  if ((mem_cs == 1'b1) && (mem_rwe == 1'b0))
  begin
    mem_rdata           <= mem[mem_addr];
  end
end

always @(posedge mem_clk)
begin : MEM_WRITE_PROC
  if ((mem_cs == 1'b1) && (mem_rwe == 1'b1))
  begin
    for (i = 0; i < MEM_DATA_WIDTH; i = i + 1)
    begin : WRITE_A_BIT_LOOP
      if (mem_bwe[i] == 1'b1)
      begin
        mem[mem_addr][i]      <= mem_wdata[i];
      end
    end
  end
end

`endif

// ----------------------------------------------------------------------------------------------------------------------
// Assertions
// ----------------------------------------------------------------------------------------------------------------------
`ifdef SOC_ASSERT_ON
  `ifdef CBB_RAM_SP_ASSERT_ON
    `include "cbb_ram_sp_assert.sv"
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
// V1.1         | 2026-07-31 | CBB Team     | Added cs_n/cen, removed TSMC_12 macro
// V1.2         | 2026-08-10 | CBB Team     | Added TSMC_12 SRAM macro instantiation
// V1.3         | 2026-08-12 | CBB Team     | Removed READ_MODE/assertions/generate; sync read only
// V1.4         | 2026-08-18 | CBB Team     | Unified port naming (cs_n -> csn)
// V1.5         | 2026-09-21 | CBB Team     | Normalize RTL style, name loops and extract macro control expressions
// V1.6         | 2026-09-23 | CBB Team     | Refine assignment alignment and comments; no functional change
// V1.7         | 2026-09-24 | CBB Team     | Move simulation memory initialization to TB assertion include
// V1.8         | 2026-09-24 | CBB Team     | Move parameter legality checks to TB assertion include
// V1.9         | 2026-11-03 | CBB Team     | Header template alignment: copyright, designer, project tag and non-template fields
// ======================================================================================================================
