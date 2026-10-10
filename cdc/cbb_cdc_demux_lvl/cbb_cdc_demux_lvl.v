// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : -
// Project      : CBB
// Create Date  : 2026/07/28
// Description  : Demultiplexing Level Synchronizer (CBB_CDC_DEMUX_LVL)
//                Source clock domain multi-bit data is held stable, only the
//                select signal passes through a level synchronizer and then
//                controls a MUX in the destination clock domain to gate the
//                stable source data to the destination output.
//                valid_d indicates data_d is valid (data is never masked to 0).
//                Technology selection via macros (see cbb_cdc_define.v).
//                Port naming follows Synopsys DWBB convention:
//                clk_s/rst_s_n/init_s_n/data_s/valid_s, clk_d/rst_d_n/init_d_n/data_d/valid_d, test.
// =====================================================================================================================
`ifndef CBB_CDC_DEMUX_LVL_V
`define CBB_CDC_DEMUX_LVL_V
`include "cbb_cdc_define.v"

module CBB_CDC_DEMUX_LVL
    #(
    parameter integer STAGES                      = 2,
    parameter integer WIDTH                       = 64
    )
    (
   input wire                                    clk_s,
   input wire                                    rst_s_n,
   input wire                                    init_s_n,
   input wire      [WIDTH-1:0]                   data_s,
   input wire                                    valid_s,
   input wire                                    clk_d,
   input wire                                    rst_d_n,
   input wire                                    init_d_n,
   output wire     [WIDTH-1:0]                   data_d,
   output wire                                   valid_d,
   input wire                                    test
    );

// synopsys translate_off
initial begin : PARAM_CHECK_PROC
  if (STAGES < 2)
    $error("STAGES must be >= 2 (actual: %0d)", STAGES);
end
// synopsys translate_on

// ---------------------------------------------------------------------------------------------------------------------
// Source Domain: Data Register (source data held stable)
// ---------------------------------------------------------------------------------------------------------------------
reg                                              valid_src_dly;
reg                [WIDTH-1:0]                   data_reg;

always @(posedge clk_s or negedge rst_s_n)
begin : VALID_DET_PROC
  if (rst_s_n == 1'b0)
    valid_src_dly        <= 1'b0;
  else if (init_s_n == 1'b0)
    valid_src_dly        <= 1'b0;
  else
    valid_src_dly        <= valid_s;
end

always @(posedge clk_s or negedge rst_s_n)
begin : DATA_REG_PROC
  if (rst_s_n == 1'b0)
    data_reg              <= {WIDTH{1'b0}};
  else if (init_s_n == 1'b0)
    data_reg              <= {WIDTH{1'b0}};
  else if (valid_s == 1'b1 && valid_src_dly == 1'b0)
    data_reg              <= data_s;
end

// ---------------------------------------------------------------------------------------------------------------------
// Valid Sync Chain (select signal only, active-low async reset)
// ---------------------------------------------------------------------------------------------------------------------
`ifdef TSMC_12
wire               [STAGES-1:0]                  valid_sync;
genvar vg;
generate
  for (vg = 0; vg < STAGES; vg = vg + 1)
  begin : VALID_SYNC_LOOP
    if (vg == 0)
    begin : STAGE0_BRANCH
      wire                                       valid_sync_din;
      assign valid_sync_din            = init_d_n & (test ? valid_sync[0] : valid_s);
      SDFSYNCNQD1BWP7D5T16P96CPD U_VALID_SYNC (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( valid_sync_din                        ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( valid_sync[0]                         )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       valid_sync_din;
      assign valid_sync_din            = init_d_n & (test ? valid_sync[vg] : valid_sync[vg-1]);
      SDFSYNCNQD1BWP7D5T16P96CPD U_VALID_SYNC (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( valid_sync_din                        ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( valid_sync[vg]                        )
      );
    end
  end
endgenerate
wire valid_dst_int = valid_sync[STAGES-1];
`elsif FPGA_XILINX
wire               [STAGES-1:0]                  valid_sync;
genvar vf;
generate
  for (vf = 0; vf < STAGES; vf = vf + 1)
  begin : VALID_SYNC_LOOP
    if (vf == 0)
    begin : STAGE0_BRANCH
      wire                                       valid_sync_din;
      assign valid_sync_din            = init_d_n & (test ? valid_sync[0] : valid_s);
      FDCE U_VALID_SYNC (
      .Q                               ( valid_sync[0]                         ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( valid_sync_din                        )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       valid_sync_din;
      assign valid_sync_din            = init_d_n & (test ? valid_sync[vf] : valid_sync[vf-1]);
      FDCE U_VALID_SYNC (
      .Q                               ( valid_sync[vf]                        ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( valid_sync_din                        )
      );
    end
  end
endgenerate
wire valid_dst_int = valid_sync[STAGES-1];
`elsif FPGA_ALTERA
wire               [STAGES-1:0]                  valid_sync;
genvar va;
generate
  for (va = 0; va < STAGES; va = va + 1)
  begin : VALID_SYNC_LOOP
    if (va == 0)
    begin : STAGE0_BRANCH
      wire                                       valid_sync_din;
      assign valid_sync_din            = init_d_n & (test ? valid_sync[0] : valid_s);
      dffeas U_VALID_SYNC (
      .q                               ( valid_sync[0]                         ),
      .d                               ( valid_sync_din                        ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( valid_sync_din                        )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       valid_sync_din;
      assign valid_sync_din            = init_d_n & (test ? valid_sync[va] : valid_sync[va-1]);
      dffeas U_VALID_SYNC (
      .q                               ( valid_sync[va]                        ),
      .d                               ( valid_sync_din                        ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( valid_sync_din                        )
      );
    end
  end
endgenerate
wire valid_dst_int = valid_sync[STAGES-1];
`else
reg                [STAGES-1:0]                  valid_sync;
integer v;
always @(posedge clk_d or negedge rst_d_n)
begin : VALID_SYNC_PROC
  if (rst_d_n == 1'b0)
    valid_sync           <= {STAGES{1'b0}};
  else if (init_d_n == 1'b0)
    valid_sync           <= {STAGES{1'b0}};
  else if (test == 1'b1)
    valid_sync           <= valid_sync;
  else
  begin
    valid_sync[0]        <= valid_s;
    for (v = 1; v < STAGES; v = v + 1)
    valid_sync[v]    <= valid_sync[v-1];
  end
end
wire valid_dst_int = valid_sync[STAGES-1];
`endif

// ---------------------------------------------------------------------------------------------------------------------
// Destination Domain: MUX + Output Register (data is not synchronized)
//   mux_sel valid   -> select data_reg (stable source data)
//   mux_sel invalid -> hold previous data_out_reg (feedback)
// ---------------------------------------------------------------------------------------------------------------------
wire               [WIDTH-1:0]                   mux_data;
reg                [WIDTH-1:0]                   data_out_reg;

assign mux_data              = (valid_dst_int == 1'b1) ? data_reg : data_out_reg;

always @(posedge clk_d or negedge rst_d_n)
begin : DATA_OUT_REG_PROC
  if (rst_d_n == 1'b0)
    data_out_reg          <= {WIDTH{1'b0}};
  else if (init_d_n == 1'b0)
    data_out_reg          <= {WIDTH{1'b0}};
  else
    data_out_reg          <= mux_data;
end

assign data_d                = data_out_reg;
assign valid_d               = valid_dst_int;

endmodule
// =====================================================================================================================
// Modification History:
// 2026/07/28 v1.0 Initial version
// 2026/08/11 v1.1 Enterprise delivery: reg->wire fix, SE/SI port removal, coverage optimization
// 2026/08/20 v1.2 DWBB-aligned ports: clk_s/rst_s_n/init_s_n/data_s/valid_s, clk_d/rst_d_n/init_d_n/data_d/valid_d, test
// =====================================================================================================================

`endif
