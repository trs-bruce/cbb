// ======================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : -
// Project      : CBB
// Create Date  : 2026/07/28
// Description  : Level-Level Synchronizer (CBB_CDC_LVL)
//                Multi-stage DFF chain for passing level signals across clock domains.
//                Technology selection via macros (see cbb_cdc_define.v).
//                All sync registers use active-low async reset (rst_d_n) and
//                active-low synchronous reset (init_d_n).
//                Port naming follows Synopsys DWBB DW_sync convention:
//                clk_d / rst_d_n / init_d_n / data_s / test / data_d.
// ======================================================================================================================
`ifndef CBB_CDC_LVL_V
`define CBB_CDC_LVL_V
`include "cbb_cdc_define.v"

module CBB_CDC_LVL
  #(
   parameter integer STAGES                      = 2                           // Number of sync stages (>= 2)
   )
   (
   input wire                                    clk_d,                        // Destination clock
   input wire                                    rst_d_n,                      // Async reset (active low)
   input wire                                    init_d_n,                     // Sync reset (active low)
   input wire                                    data_s,                       // Source domain level signal
   input wire                                    test,                         // Test mode enable
   output wire                                   data_d                        // Synchronized level signal
   );

// ----------------------------------------------------------------------------------------------------------------------
// Synchronizer Implementation
// Technology selection: TSMC_12 / FPGA_XILINX / FPGA_ALTERA / default RTL
// init_d_n retains its DWBB interface name (NAME_SIG12 compatibility exception).
// sync_reg retains its existing name for waveform/debug compatibility.
// Dedicated synchronizer cells are intentional in technology-specific branches.
// ----------------------------------------------------------------------------------------------------------------------
`ifdef TSMC_12
wire               [STAGES-1:0]                  sync_reg;
wire               [STAGES-1:0]                  sync_d;
genvar                                           sg;
generate
  for (sg = 0; sg < STAGES; sg = sg + 1)
  begin : SYNC_CHAIN_LOOP
    if (sg == 0)
    begin : STAGE0_BRANCH
      assign sync_d[0]            = init_d_n & ((test == 1'b1) ? sync_reg[0] : data_s);

      SDFSYNCNQD1BWP7D5T16P96CPD
      U_SDFSYNCNQD1BWP7D5T16P96CPD
      (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( sync_d[0]                             ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( sync_reg[0]                           )
      );
    end
    else
    begin : STAGE_N_BRANCH
      assign sync_d[sg]           = init_d_n & ((test == 1'b1) ? sync_reg[sg] : sync_reg[sg-1]);

      SDFSYNCNQD1BWP7D5T16P96CPD
      U_SDFSYNCNQD1BWP7D5T16P96CPD
      (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( sync_d[sg]                            ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( sync_reg[sg]                          )
      );
    end
  end
endgenerate
assign data_d           = sync_reg[STAGES-1];
`elsif FPGA_XILINX
wire               [STAGES-1:0]                  sync_reg;
wire               [STAGES-1:0]                  sync_d;
genvar                                           sx;
generate
  for (sx = 0; sx < STAGES; sx = sx + 1)
  begin : SYNC_CHAIN_LOOP
    if (sx == 0)
    begin : STAGE0_BRANCH
      assign sync_d[0]            = init_d_n & ((test == 1'b1) ? sync_reg[0] : data_s);

      FDCE
      U_FDCE
      (
      .Q                               ( sync_reg[0]                           ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( sync_d[0]                             )
      );
    else

      FDCE
      U_FDCE
      (
=======
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[sx] : sync_reg[sx-1]);
      FDCE U_SYNC (
>>>>>>> origin/main
      .Q                               ( sync_reg[sx]                          ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( sync_d[sx]                            )
      );
    end
  end
endgenerate
assign data_d           = sync_reg[STAGES-1];
`elsif FPGA_ALTERA
wire               [STAGES-1:0]                  sync_reg;
wire               [STAGES-1:0]                  sync_d;
genvar                                           sa;
generate
  for (sa = 0; sa < STAGES; sa = sa + 1)
  begin : SYNC_CHAIN_LOOP
    if (sa == 0)
    begin : STAGE0_BRANCH
      assign sync_d[0]            = init_d_n & ((test == 1'b1) ? sync_reg[0] : data_s);

      dffeas
      U_DFFEAS
      (
      .q                               ( sync_reg[0]                           ),
      .d                               ( sync_d[0]                             ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( sync_d[0]                             )
      );
    end
    else
      U_DFFEAS
      (
      .q                               ( sync_reg[sa]                          ),
      .d                               ( sync_d[sa]                            ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( sync_d[sa]                            )
      );
    end
  end
endgenerate
assign data_d           = sync_reg[STAGES-1];
`else
reg                [STAGES-1:0]                  sync_reg;
integer                                          s;
always @(posedge clk_d or negedge rst_d_n)
begin : SYNC_CHAIN_PROC
  if (rst_d_n == 1'b0)
  begin
    sync_reg            <= {STAGES{1'b0}};
  end
  else if (init_d_n == 1'b0)
  begin
    sync_reg            <= {STAGES{1'b0}};
  end
  else if (test == 1'b1)
  begin
    sync_reg            <= sync_reg;                                           // Test mode: hold sync chain
  end
  else
  begin
    sync_reg[0]         <= data_s;
    for (s = 1; s < STAGES; s = s + 1)
    begin : SYNC_SHIFT_LOOP
      sync_reg[s]       <= sync_reg[s-1];
    end
  end
end
assign data_d           = sync_reg[STAGES-1];
`endif

// ----------------------------------------------------------------------------------------------------------------------
// Assertions
// ----------------------------------------------------------------------------------------------------------------------
`ifdef SOC_ASSERT_ON
  `ifdef CBB_CDC_LVL_ASSERT_ON
    `include "cbb_cdc_lvl_assert.sv"
  `endif
`endif

endmodule
// ======================================================================================================================
// v1.4  2026-09-24  Move STAGES legality check into the assertion include
// ======================================================================================================================
