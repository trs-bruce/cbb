// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : -
// Project      : CBB
// Create Date  : 2026/07/28
// Description  : Demultiplexing Pulse (Pulse-Triggered) Synchronizer (CBB_CDC_DEMUX_PUL_P)
//                Source clock domain multi-bit data is held stable, a valid pulse
//                toggles a synchronizer; the synchronized pulse controls a MUX in
//                the destination clock domain to gate the stable source data.
//                Technology selection via macros (see cbb_cdc_define.v).
//                Port naming follows Synopsys DWBB convention:
//                clk_s/rst_s_n/init_s_n/data_s/valid_s, clk_d/rst_d_n/init_d_n/data_d/valid_d, test.
// =====================================================================================================================
`ifndef CBB_CDC_DEMUX_PUL_P_V
`define CBB_CDC_DEMUX_PUL_P_V
`include "cbb_cdc_define.v"

module CBB_CDC_DEMUX_PUL_P
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
reg                [WIDTH-1:0]                   data_reg;
always @(posedge clk_s or negedge rst_s_n)
begin : DATA_REG_PROC
  if (rst_s_n == 1'b0)
    data_reg              <= {WIDTH{1'b0}};
  else if (init_s_n == 1'b0)
    data_reg              <= {WIDTH{1'b0}};
  else if (valid_s == 1'b1)
    data_reg              <= data_s;
end

// ---------------------------------------------------------------------------------------------------------------------
// Source Domain: Toggle Generation
// ---------------------------------------------------------------------------------------------------------------------
reg                                              toggle_src;
always @(posedge clk_s or negedge rst_s_n)
begin : TOGGLE_SRC_PROC
  if (rst_s_n == 1'b0)
    toggle_src            <= 1'b0;
  else if (init_s_n == 1'b0)
    toggle_src            <= 1'b0;
  else if (valid_s == 1'b1)
    toggle_src            <= ~toggle_src;
end

// ---------------------------------------------------------------------------------------------------------------------
// Forward Toggle Sync Chain (select signal only)
// ---------------------------------------------------------------------------------------------------------------------
`ifdef TSMC_12
wire               [STAGES-1:0]                  toggle_sync;
genvar tg;
generate
  for (tg = 0; tg < STAGES; tg = tg + 1)
  begin : TGL_SYNC_LOOP
    if (tg == 0)
    begin : STAGE0_BRANCH
      wire                                       toggle_sync_din;
      assign toggle_sync_din           = init_d_n & (test ? toggle_sync[0] : toggle_src);
      SDFSYNCNQD1BWP7D5T16P96CPD U_TGL_SYNC (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( toggle_sync_din                       ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( toggle_sync[0]                        )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       toggle_sync_din;
      assign toggle_sync_din           = init_d_n & (test ? toggle_sync[tg] : toggle_sync[tg-1]);
      SDFSYNCNQD1BWP7D5T16P96CPD U_TGL_SYNC (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( toggle_sync_din                       ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( toggle_sync[tg]                       )
      );
    end
  end
endgenerate
wire toggle_dst = toggle_sync[STAGES-1];
`elsif FPGA_XILINX
wire               [STAGES-1:0]                  toggle_sync;
genvar txf;
generate
  for (txf = 0; txf < STAGES; txf = txf + 1)
  begin : TGL_SYNC_LOOP
    if (txf == 0)
    begin : STAGE0_BRANCH
      wire                                       toggle_sync_din;
      assign toggle_sync_din           = init_d_n & (test ? toggle_sync[0] : toggle_src);
      FDCE U_TGL_SYNC (
      .Q                               ( toggle_sync[0]                        ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( toggle_sync_din                       )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       toggle_sync_din;
      assign toggle_sync_din           = init_d_n & (test ? toggle_sync[txf] : toggle_sync[txf-1]);
      FDCE U_TGL_SYNC (
      .Q                               ( toggle_sync[txf]                      ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( toggle_sync_din                       )
      );
    end
  end
endgenerate
wire toggle_dst = toggle_sync[STAGES-1];
`elsif FPGA_ALTERA
wire               [STAGES-1:0]                  toggle_sync;
genvar ta;
generate
  for (ta = 0; ta < STAGES; ta = ta + 1)
  begin : TGL_SYNC_LOOP
    if (ta == 0)
    begin : STAGE0_BRANCH
      wire                                       toggle_sync_din;
      assign toggle_sync_din           = init_d_n & (test ? toggle_sync[0] : toggle_src);
      dffeas U_TGL_SYNC (
      .q                               ( toggle_sync[0]                        ),
      .d                               ( toggle_sync_din                       ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( toggle_sync_din                       )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       toggle_sync_din;
      assign toggle_sync_din           = init_d_n & (test ? toggle_sync[ta] : toggle_sync[ta-1]);
      dffeas U_TGL_SYNC (
      .q                               ( toggle_sync[ta]                       ),
      .d                               ( toggle_sync_din                       ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( toggle_sync_din                       )
      );
    end
  end
endgenerate
wire toggle_dst = toggle_sync[STAGES-1];
`else
reg                [STAGES-1:0]                  toggle_sync;
integer t;
always @(posedge clk_d or negedge rst_d_n)
begin : TGL_SYNC_PROC
  if (rst_d_n == 1'b0)
    toggle_sync        <= {STAGES{1'b0}};
  else if (init_d_n == 1'b0)
    toggle_sync        <= {STAGES{1'b0}};
  else if (test == 1'b1)
    toggle_sync        <= toggle_sync;
  else
  begin
    toggle_sync[0]     <= toggle_src;
    for (t = 1; t < STAGES; t = t + 1)
    toggle_sync[t] <= toggle_sync[t-1];
  end
end
wire toggle_dst = toggle_sync[STAGES-1];
`endif

// ---------------------------------------------------------------------------------------------------------------------
// Destination Domain: Toggle -> Pulse
// ---------------------------------------------------------------------------------------------------------------------
reg                                              toggle_dly;
always @(posedge clk_d or negedge rst_d_n)
begin : TGL2PULSE_PROC
  if (rst_d_n == 1'b0)
    toggle_dly            <= 1'b0;
  else if (init_d_n == 1'b0)
    toggle_dly            <= 1'b0;
  else
    toggle_dly            <= toggle_dst;
end
wire mux_sel = toggle_dst ^ toggle_dly;
assign valid_d          = mux_sel;

// ---------------------------------------------------------------------------------------------------------------------
// Destination Domain: MUX + Output Register (data is not synchronized)
//   mux_sel pulse -> select data_reg (stable source data), then hold
// ---------------------------------------------------------------------------------------------------------------------
wire               [WIDTH-1:0]                   mux_data;
reg                [WIDTH-1:0]                   data_out_reg;

assign mux_data              = (mux_sel == 1'b1) ? data_reg : data_out_reg;

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

endmodule
// =====================================================================================================================
// Modification History:
// 2026/07/28 v1.0 Initial version
// 2026/08/11 v1.1 Enterprise delivery: reg->wire fix, SE/SI port removal, coverage optimization
// 2026/08/20 v1.2 DWBB-aligned ports: clk_s/rst_s_n/init_s_n/data_s/valid_s, clk_d/rst_d_n/init_d_n/data_d/valid_d, test
// =====================================================================================================================

`endif
