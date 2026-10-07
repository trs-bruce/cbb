// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : -
// Project      : CBB
// Create Date  : 2026/07/28
// Description  : Level-Level Synchronizer with Feedback (CBB_CDC_LVL_FB)
//                Handshake-based level crossing with acknowledge feedback.
//                Technology selection via macros (see cbb_cdc_define.v).
//                Port naming follows Synopsys DWBB convention:
//                clk_s/rst_s_n/init_s_n/data_s, clk_d/rst_d_n/init_d_n/data_d, ack_s, test.
// =====================================================================================================================
`ifndef CBB_CDC_LVL_FB_V
`define CBB_CDC_LVL_FB_V
`include "cbb_cdc_define.v"

module CBB_CDC_LVL_FB
    #(
    parameter integer STAGES                      = 2                           // Number of sync stages (>= 2)
    )
    (
   input wire                                    clk_s,                        // Source clock
   input wire                                    rst_s_n,                      // Async reset, source domain (active low)
   input wire                                    init_s_n,                     // Sync reset, source domain (active low)
   input wire                                    data_s,                       // Source domain level signal
   input wire                                    clk_d,                        // Destination clock
   input wire                                    rst_d_n,                      // Async reset, destination domain (active low)
   input wire                                    init_d_n,                     // Sync reset, destination domain (active low)
   output wire                                   data_d,                       // Synchronized level signal
   output wire                                   ack_s,                        // Acknowledge to source domain
   input wire                                    test                          // Test mode enable
    );

// synopsys translate_off
initial begin : STAGE_CHECK_PROC
  if (STAGES < 2)
    $error("STAGES must be >= 2 (actual: %0d)", STAGES);
end
// synopsys translate_on

// ---------------------------------------------------------------------------------------------------------------------
// Source Domain: Request Generation
// ---------------------------------------------------------------------------------------------------------------------
reg                                              req_src;

always @(posedge clk_s or negedge rst_s_n)
begin : REQ_SRC_PROC
  if (rst_s_n == 1'b0)
    req_src               <= 1'b0;
  else if (init_s_n == 1'b0)
    req_src               <= 1'b0;
  else if (data_s == 1'b1)
    req_src               <= 1'b1;
  else if (ack_s == 1'b1)
    req_src               <= 1'b0;
end

// ---------------------------------------------------------------------------------------------------------------------
// Forward Sync Chain: Request
// ---------------------------------------------------------------------------------------------------------------------
`ifdef TSMC_12
wire               [STAGES-1:0]                  req_sync;
genvar rg;
generate
  for (rg = 0; rg < STAGES; rg = rg + 1)
  begin : REQ_SYNC_LOOP
    if (rg == 0)
    begin : STAGE0_BRANCH
      wire                                       req_sync_din;
      assign req_sync_din              = init_d_n & (test ? req_sync[0] : req_src);
      SDFSYNCNQD1BWP7D5T16P96CPD U_REQ_SYNC (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( req_sync_din                          ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( req_sync[0]                           )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       req_sync_din;
      assign req_sync_din              = init_d_n & (test ? req_sync[rg] : req_sync[rg-1]);
      SDFSYNCNQD1BWP7D5T16P96CPD U_REQ_SYNC (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( req_sync_din                          ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( req_sync[rg]                          )
      );
    end
  end
endgenerate
wire req_dst = req_sync[STAGES-1];
`elsif FPGA_XILINX
wire               [STAGES-1:0]                  req_sync;
genvar rxf;
generate
  for (rxf = 0; rxf < STAGES; rxf = rxf + 1)
  begin : REQ_SYNC_LOOP
    if (rxf == 0)
    begin : STAGE0_BRANCH
      wire                                       req_sync_din;
      assign req_sync_din              = init_d_n & (test ? req_sync[0] : req_src);
      FDCE U_REQ_SYNC (
      .Q                               ( req_sync[0]                           ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( req_sync_din                          )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       req_sync_din;
      assign req_sync_din              = init_d_n & (test ? req_sync[rxf] : req_sync[rxf-1]);
      FDCE U_REQ_SYNC (
      .Q                               ( req_sync[rxf]                         ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( req_sync_din                          )
      );
    end
  end
endgenerate
wire req_dst = req_sync[STAGES-1];
`elsif FPGA_ALTERA
wire               [STAGES-1:0]                  req_sync;
genvar ra;
generate
  for (ra = 0; ra < STAGES; ra = ra + 1)
  begin : REQ_SYNC_LOOP
    if (ra == 0)
    begin : STAGE0_BRANCH
      wire                                       req_sync_din;
      assign req_sync_din              = init_d_n & (test ? req_sync[0] : req_src);
      dffeas U_REQ_SYNC (
      .q                               ( req_sync[0]                           ),
      .d                               ( req_sync_din                          ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( req_sync_din                          )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       req_sync_din;
      assign req_sync_din              = init_d_n & (test ? req_sync[ra] : req_sync[ra-1]);
      dffeas U_REQ_SYNC (
      .q                               ( req_sync[ra]                          ),
      .d                               ( req_sync_din                          ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( req_sync_din                          )
      );
    end
  end
endgenerate
wire req_dst = req_sync[STAGES-1];
`else
reg                [STAGES-1:0]                  req_sync;
integer r;
always @(posedge clk_d or negedge rst_d_n)
begin : REQ_SYNC_PROC
  if (rst_d_n == 1'b0)
    req_sync           <= {STAGES{1'b0}};
  else if (init_d_n == 1'b0)
    req_sync           <= {STAGES{1'b0}};
  else if (test == 1'b1)
    req_sync           <= req_sync;
  else
  begin
    req_sync[0]        <= req_src;
    for (r = 1; r < STAGES; r = r + 1)
    req_sync[r]    <= req_sync[r-1];
  end
end
wire req_dst = req_sync[STAGES-1];
`endif

assign data_d                = req_dst;

// ---------------------------------------------------------------------------------------------------------------------
// Destination Domain: Acknowledge Generation
// ---------------------------------------------------------------------------------------------------------------------
reg                                              ack_dst;

always @(posedge clk_d or negedge rst_d_n)
begin : ACK_DST_PROC
  if (rst_d_n == 1'b0)
    ack_dst               <= 1'b0;
  else if (init_d_n == 1'b0)
    ack_dst               <= 1'b0;
  else
    ack_dst               <= req_dst;
end

// ---------------------------------------------------------------------------------------------------------------------
// Backward Sync Chain: Acknowledge
// ---------------------------------------------------------------------------------------------------------------------
`ifdef TSMC_12
wire               [STAGES-1:0]                  ack_sync;
genvar ag;
generate
  for (ag = 0; ag < STAGES; ag = ag + 1)
  begin : ACK_SYNC_LOOP
    if (ag == 0)
    begin : STAGE0_BRANCH
      wire                                       ack_sync_din;
      assign ack_sync_din              = init_s_n & ack_dst;
      SDFSYNCNQD1BWP7D5T16P96CPD U_ACK_SYNC (
      .CDN                             ( rst_s_n                               ),
      .CP                              ( clk_s                                 ),
      .D                               ( ack_sync_din                          ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( ack_sync[0]                           )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       ack_sync_din;
      assign ack_sync_din              = init_s_n & ack_sync[ag-1];
      SDFSYNCNQD1BWP7D5T16P96CPD U_ACK_SYNC (
      .CDN                             ( rst_s_n                               ),
      .CP                              ( clk_s                                 ),
      .D                               ( ack_sync_din                          ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( ack_sync[ag]                          )
      );
    end
  end
endgenerate
assign ack_s            = ack_sync[STAGES-1];
`elsif FPGA_XILINX
wire               [STAGES-1:0]                  ack_sync;
genvar axf;
generate
  for (axf = 0; axf < STAGES; axf = axf + 1)
  begin : ACK_SYNC_LOOP
    if (axf == 0)
    begin : STAGE0_BRANCH
      wire                                       ack_sync_din;
      assign ack_sync_din              = init_s_n & ack_dst;
      FDCE U_ACK_SYNC (
      .Q                               ( ack_sync[0]                           ),
      .C                               ( clk_s                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_s_n                               ),
      .D                               ( ack_sync_din                          )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       ack_sync_din;
      assign ack_sync_din              = init_s_n & ack_sync[axf-1];
      FDCE U_ACK_SYNC (
      .Q                               ( ack_sync[axf]                         ),
      .C                               ( clk_s                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_s_n                               ),
      .D                               ( ack_sync_din                          )
      );
    end
  end
endgenerate
assign ack_s            = ack_sync[STAGES-1];
`elsif FPGA_ALTERA
wire               [STAGES-1:0]                  ack_sync;
genvar aa;
generate
  for (aa = 0; aa < STAGES; aa = aa + 1)
  begin : ACK_SYNC_LOOP
    if (aa == 0)
    begin : STAGE0_BRANCH
      wire                                       ack_sync_din;
      assign ack_sync_din              = init_s_n & ack_dst;
      dffeas U_ACK_SYNC (
      .q                               ( ack_sync[0]                           ),
      .d                               ( ack_sync_din                          ),
      .clk                             ( clk_s                                 ),
      .clrn                            ( rst_s_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( ack_sync_din                          )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       ack_sync_din;
      assign ack_sync_din              = init_s_n & ack_sync[aa-1];
      dffeas U_ACK_SYNC (
      .q                               ( ack_sync[aa]                          ),
      .d                               ( ack_sync_din                          ),
      .clk                             ( clk_s                                 ),
      .clrn                            ( rst_s_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( ack_sync_din                          )
      );
    end
  end
endgenerate
assign ack_s            = ack_sync[STAGES-1];
`else
reg                [STAGES-1:0]                  ack_sync;
integer a;
always @(posedge clk_s or negedge rst_s_n)
begin : ACK_SYNC_PROC
  if (rst_s_n == 1'b0)
    ack_sync           <= {STAGES{1'b0}};
  else if (init_s_n == 1'b0)
    ack_sync           <= {STAGES{1'b0}};
  else
  begin
    ack_sync[0]        <= ack_dst;
    for (a = 1; a < STAGES; a = a + 1)
    ack_sync[a]    <= ack_sync[a-1];
  end
end
assign ack_s            = ack_sync[STAGES-1];
`endif

endmodule
// =====================================================================================================================
// v1.3  2026-08-20  DWBB-aligned ports: clk_s/rst_s_n/init_s_n/data_s, clk_d/rst_d_n/init_d_n/data_d, ack_s, test
// =====================================================================================================================
