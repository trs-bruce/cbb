// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : -
// Project      : CBB
// Create Date  : 2026/07/28
// Description  : Rising-Edge Pulse Synchronizer (CBB_CDC_EDGE_R)
//                Two-stage destination-domain DFF level synchronizer followed by
//                rising-edge detection, producing a 1-clk_d-cycle pulse.
//                Technology selection via macros (see cbb_cdc_define.v).
//                Port naming follows Synopsys DWBB convention:
//                clk_d / rst_d_n / init_d_n / data_s / test / event_d.
// =====================================================================================================================
`ifndef CBB_CDC_EDGE_R_V
`define CBB_CDC_EDGE_R_V
`include "cbb_cdc_define.v"

module CBB_CDC_EDGE_R
    #(
    parameter integer STAGES                      = 2                           // Number of sync stages (>= 2)
    )
    (
   input wire                                    clk_d,                        // Destination clock
   input wire                                    rst_d_n,                      // Async reset (active low)
   input wire                                    init_d_n,                     // Sync reset (active low)
   input wire                                    data_s,                       // Source domain level signal
   input wire                                    test,                         // Test mode enable
   output wire                                   event_d                       // Rising-edge pulse in dst domain
    );

// synopsys translate_off
initial begin : STAGE_CHECK_PROC
  if (STAGES < 2)
    $error("STAGES must be >= 2 (actual: %0d)", STAGES);
end
// synopsys translate_on

// ---------------------------------------------------------------------------------------------------------------------
// Level Synchronizer (destination domain, STAGES DFFs)
// Technology selection: TSMC_12 / FPGA_XILINX / FPGA_ALTERA / default RTL
// (USE_STDCELL removed: unified into TSMC_12 to eliminate macro redundancy)
// ---------------------------------------------------------------------------------------------------------------------
`ifdef TSMC_12
wire               [STAGES-1:0]                  sync_reg;
genvar sg;
generate
  for (sg = 0; sg < STAGES; sg = sg + 1)
  begin : SYNC_CHAIN_LOOP
    if (sg == 0)
    begin : STAGE0_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[0] : data_s);
      SDFSYNCNQD1BWP7D5T16P96CPD U_SYNC (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( sync_reg_din                          ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( sync_reg[0]                           )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[sg] : sync_reg[sg-1]);
      SDFSYNCNQD1BWP7D5T16P96CPD U_SYNC (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( sync_reg_din                          ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( sync_reg[sg]                          )
      );
    end
  end
endgenerate
wire sync_dst = sync_reg[STAGES-1];
`elsif FPGA_XILINX
wire               [STAGES-1:0]                  sync_reg;
genvar sx;
generate
  for (sx = 0; sx < STAGES; sx = sx + 1)
  begin : SYNC_CHAIN_LOOP
    if (sx == 0)
    begin : STAGE0_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[0] : data_s);
      FDCE U_SYNC (
      .Q                               ( sync_reg[0]                           ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( sync_reg_din                          )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[sx] : sync_reg[sx-1]);
      FDCE U_SYNC (
      .Q                               ( sync_reg[sx]                          ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( sync_reg_din                          )
      );
    end
  end
endgenerate
wire sync_dst = sync_reg[STAGES-1];
`elsif FPGA_ALTERA
wire               [STAGES-1:0]                  sync_reg;
genvar sa;
generate
  for (sa = 0; sa < STAGES; sa = sa + 1)
  begin : SYNC_CHAIN_LOOP
    if (sa == 0)
    begin : STAGE0_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[0] : data_s);
      dffeas U_SYNC (
      .q                               ( sync_reg[0]                           ),
      .d                               ( sync_reg_din                          ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( sync_reg_din                          )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[sa] : sync_reg[sa-1]);
      dffeas U_SYNC (
      .q                               ( sync_reg[sa]                          ),
      .d                               ( sync_reg_din                          ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( sync_reg_din                          )
      );
    end
  end
endgenerate
wire sync_dst = sync_reg[STAGES-1];
`else
reg                [STAGES-1:0]                  sync_reg;
integer s;
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
    sync_reg            <= sync_reg;        // test mode: hold sync chain
  end
  else
  begin
    sync_reg[0]         <= data_s;
    for (s = 1; s < STAGES; s = s + 1)
    sync_reg[s]     <= sync_reg[s-1];
  end
end
wire sync_dst = sync_reg[STAGES-1];
`endif

// ---------------------------------------------------------------------------------------------------------------------
// Destination Domain: Rising-Edge Detect -> Pulse
// ---------------------------------------------------------------------------------------------------------------------
reg                                              sync_dly;

always @(posedge clk_d or negedge rst_d_n)
begin : DST_EDGE_PROC
  if (rst_d_n == 1'b0)
    sync_dly              <= 1'b0;
  else if (init_d_n == 1'b0)
    sync_dly              <= 1'b0;
  else
    sync_dly              <= sync_dst;
end

assign event_d               = sync_dst & ~sync_dly;

endmodule
// =====================================================================================================================
// v1.3  2026-08-20  DWBB-aligned ports: clk_d/rst_d_n/init_d_n/data_s/test/event_d
// =====================================================================================================================
