// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026-07-20
// Description  : Single-Port Synchronous ROM
//                Synchronous read-only memory (1-cycle latency).
//                Default config 256x32 matches TSMC hard macro.
//                For larger capacity, instantiate multiple CBB_ROM
//                at upper level and perform address/data banking externally.
//                Supports TSMC_12 / FPGA_XILINX / FPGA_ALTERA macros.
//                Generic ROM contents are selected by image macros in cbb_rom_assert.sv.
// =====================================================================================================================

`ifndef CBB_ROM_V
`define CBB_ROM_V

module CBB_ROM
  #(
   parameter MEM_ADDR_WIDTH                      = 8,                          // TSMC macro: 8 bits (256 words)
   parameter MEM_DATA_WIDTH                      = 32,                         // TSMC macro: 32 bits
   parameter INIT_FILE                           = ""                          // Simulation image file; ignored by zero placeholder
   )
   (
   input                                         mem_clk,                      // Read clock
   input                                         mem_cs,                       // Chip select / read enable, active-high (1: valid)
   input           [MEM_ADDR_WIDTH-1:0]          mem_addr,                     // Read address
   output reg      [MEM_DATA_WIDTH-1:0]          mem_rdata                     // Read data output (1-cycle latency)
   );

localparam MEM_DEPTH                             = (1 << MEM_ADDR_WIDTH);      // 256

// ----------------------------------------------------------------------------------------------------------------------
// Memory Array
// ----------------------------------------------------------------------------------------------------------------------

`ifdef FPGA_XILINX
(* rom_style = "block" *)
`elsif FPGA_ALTERA
(* ramstyle = "M20K" *)
`endif
wire               [MEM_DATA_WIDTH-1:0]          mem [0:MEM_DEPTH-1];

// NAME_SIG09 exception: retain public mem_clk port for existing callers.
`ifdef TSMC_12
localparam         [MEM_ADDR_WIDTH-1:0]          BIST_ADDR_ZERO = {MEM_ADDR_WIDTH{1'b0}};
wire                                             macro_ceb_n;
`endif

`ifdef TSMC_12
// ----------------------------------------------------------------------------------------------------------------------
// TSMC 12nm ROM Hard Macro
// Macro      : CBB_ROM_256X32 (256 words x 32 bits)
// Type       : Single-Port Synchronous ROM
// Strategy   : CBB layer directly instantiates ONE macro; no internal banking.
//              If the caller needs larger capacity, instantiate multiple
//              CBB_ROM at the upper level and bank externally.
// Polarity   : CEB is active-low; mem_cs connects via an inverter
//              (active-high port inverted to macro's CEB).
// Clocking   : CLK driven by mem_clk; pure synchronous output.
// Note       : INIT_FILE is ignored in TSMC mode; ROM content is fixed at
//              silicon compile time via the .rom.v file.
// Constraint : MEM_ADDR_WIDTH must be 8 and MEM_DATA_WIDTH must be 32 for TSMC macro.
// ----------------------------------------------------------------------------------------------------------------------

// Convert active-high chip select to the macro active-low enable.
assign macro_ceb_n      = ~mem_cs;

CBB_ROM_256X32
U_CBB_ROM_256X32
(
.A                                     ( mem_addr                              ),
.AM                                    ( BIST_ADDR_ZERO                        ),
.CEBM                                  ( 1'b1                                  ),
.BIST                                  ( 1'b0                                  ),
.CEB                                   ( macro_ceb_n                           ),
.CLK                                   ( mem_clk                               ),
.SD                                    ( 1'b0                                  ),
.PUDELAY                               (                                       ),
.RTSEL                                 ( 2'b01                                 ),
.PTSEL                                 ( 2'b01                                 ),
.TRB                                   ( 2'b01                                 ),
.TM                                    ( 1'b0                                  ),
.Q                                     ( mem_rdata                             )
);

`else
// ----------------------------------------------------------------------------------------------------------------------
// Behavioral Logic
// ----------------------------------------------------------------------------------------------------------------------

// ----------------------------------------------------------------------------------------------------------------------
// Read Port — driven by mem_clk
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge mem_clk)
begin : MEM_READ_PROC
  if (mem_cs == 1'b1)
  begin
    mem_rdata           <= mem[mem_addr];
  end
end

`endif

// ----------------------------------------------------------------------------------------------------------------------
// Assertions
// The include also supplies generic ROM image drivers and parameter checks.
// Scripts must enable both SOC_ASSERT_ON and CBB_ROM_ASSERT_ON.
// Select CBB_ROM_ZERO_IMAGE for lint/synthesis or CBB_ROM_SIM_IMAGE for simulation.
// TSMC_12 uses the hard macro and excludes the generic image drivers.
// CODE-SIG05 exception: retain this include at module end as requested by the project.
// ----------------------------------------------------------------------------------------------------------------------
`ifdef SOC_ASSERT_ON
  `ifdef CBB_ROM_ASSERT_ON
    `include "cbb_rom_assert.sv"
  `endif
`endif

endmodule

`endif

// ======================================================================================================================
// Revision History
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// ----------------------------------------------------------------------------------------------------------------------
// V1.0         | 2026-07-20 | CBB Team     | Initial release
// V1.1         | 2026-07-31 | CBB Team     | Removed TSMC_12 macro branch; pure behavioral RTL
// V1.2         | 2026-08-06 | CBB Team     | Added TSMC_12/FPGA macro support; merged cs_n/oe_n
// V1.3         | 2026-08-13 | CBB Team     | Removed SYNC_OUT/assertions/generate/rst_n; sync read only
// V1.4         | 2026-08-18 | CBB Team     | Unified port naming (mem_ prefix, csn); added section comments
// V1.5         | 2026-09-21 | CBB Team     | Normalize RTL style and extract macro chip-select expression
// V1.6         | 2026-09-24 | CBB Team     | Move simulation memory initialization to TB assertion include
// V1.7         | 2026-09-24 | CBB Team     | Move parameter legality checks to TB assertion include
// V1.8         | 2026-09-28 | CBB Team     | Move ROM generate index declaration to the assertion include
// V1.9         | 2026-09-28 | CBB Team     | Restore the Assertions include at module end and document image controls
// V1.10        | 2026-09-28 | CBB Team     | Move ROM image drivers to the assertion include with explicit image modes
// V1.11        | 2026-09-28 | CBB Team     | Tie generic ROM words to zero for SpyGlass lint checking
// V1.12        | 2026-09-28 | CBB Team     | Add parameterized constant ROM contents for generic synthesis
// V1.13        | 2026-11-03 | CBB Team     | Header template alignment: copyright, designer, project tag and non-template fields
// ======================================================================================================================
