// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : -
// Project      : CBB
// Create Date  : 2026/07/28
// Description  : Demultiplexing Pulse with Feedback Synchronizer (CBB_CDC_DEMUX_PUL_FB)
//                Source clock domain multi-bit data is held stable, a request
//                toggles a synchronizer; the synchronized pulse controls a MUX
//                in the destination clock domain to gate the stable source data.
//                Acknowledge handshake flows back to the source domain.
//                Technology selection via macros (see cbb_cdc_define.v).
//                Port naming follows Synopsys DWBB convention:
//                clk_s/rst_s_n/init_s_n/data_s/valid_s, clk_d/rst_d_n/init_d_n/data_d/valid_d, ack_s, test.
// =====================================================================================================================
`ifndef CBB_CDC_DEMUX_PUL_FB_V
`define CBB_CDC_DEMUX_PUL_FB_V
`include "cbb_cdc_define.v"

module CBB_CDC_DEMUX_PUL_FB
    #(
    parameter integer STAGES                      = 2,                          // Number of sync stages (>= 2)
    parameter integer WIDTH                       = 64                          // Data width
    )
    (
   input wire                                    clk_s,                        // Source clock
   input wire                                    rst_s_n,                      // Async reset, source domain (active low)
   input wire                                    init_s_n,                     // Sync reset, source domain (active low)
   input wire      [WIDTH-1:0]                   data_s,                       // Source domain data
   input wire                                    valid_s,                      // Source domain valid
   input wire                                    clk_d,                        // Destination clock
   input wire                                    rst_d_n,                      // Async reset, destination domain (active low)
   input wire                                    init_d_n,                     // Sync reset, destination domain (active low)
   output wire     [WIDTH-1:0]                   data_d,                       // Destination domain data
   output wire                                   valid_d,                      // Destination domain data valid
   output wire                                   ack_s,                        // Acknowledge to source domain
   input wire                                    test                          // Test / hold control
    );

// synopsys translate_off
initial begin : PARAM_CHECK_PROC
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
  else if (valid_s == 1'b1)
    req_src               <= 1'b1;
  else if (ack_s == 1'b1)
    req_src               <= 1'b0;
end

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
  else if ((valid_s == 1'b1) && (req_src == 1'b0))
    data_reg              <= data_s;
end

// ---------------------------------------------------------------------------------------------------------------------
// Source Domain: Toggle Generation for Request
// ---------------------------------------------------------------------------------------------------------------------
reg                                              toggle_req;

always @(posedge clk_s or negedge rst_s_n)
begin : TGL_REQ_PROC
  if (rst_s_n == 1'b0)
    toggle_req            <= 1'b0;
  else if (init_s_n == 1'b0)
    toggle_req            <= 1'b0;
  else if ((valid_s == 1'b1) && (req_src == 1'b0))
    toggle_req            <= ~toggle_req;
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
      assign toggle_sync_din           = init_d_n & (test ? toggle_sync[0] : toggle_req);
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
      assign toggle_sync_din           = init_d_n & (test ? toggle_sync[0] : toggle_req);
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
      assign toggle_sync_din           = init_d_n & (test ? toggle_sync[0] : toggle_req);
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
    toggle_sync[0]     <= toggle_req;
    for (t = 1; t < STAGES; t = t + 1)
    toggle_sync[t] <= toggle_sync[t-1];
  end
end
wire toggle_dst = toggle_sync[STAGES-1];
`endif

// ---------------------------------------------------------------------------------------------------------------------
// Destination Domain: Toggle-to-Pulse Conversion
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

wire req_dst_pulse = toggle_dst ^ toggle_dly;

// ---------------------------------------------------------------------------------------------------------------------
// Destination Domain: MUX + Output Register (data is not synchronized)
//   req_dst_pulse -> select data_reg (stable source data), then hold
// ---------------------------------------------------------------------------------------------------------------------
wire               [WIDTH-1:0]                   mux_data;
reg                [WIDTH-1:0]                   data_out_reg;

assign mux_data              = (req_dst_pulse == 1'b1) ? data_reg : data_out_reg;

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
assign valid_d               = req_dst_pulse;

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
    ack_dst               <= toggle_dst;
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
assign ack_s            = ack_sync[STAGES-1] ^ ack_sync[STAGES-2];
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
assign ack_s            = ack_sync[STAGES-1] ^ ack_sync[STAGES-2];
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
assign ack_s            = ack_sync[STAGES-1] ^ ack_sync[STAGES-2];
`else
reg                [STAGES-1:0]                  ack_sync;
reg                                              ack_dly;
integer a;
always @(posedge clk_s or negedge rst_s_n)
begin : ACK_SYNC_PROC
  if (rst_s_n == 1'b0)
  begin
    ack_sync           <= {STAGES{1'b0}};
    ack_dly            <= 1'b0;
  end
  else if (init_s_n == 1'b0)
  begin
    ack_sync           <= {STAGES{1'b0}};
    ack_dly            <= 1'b0;
  end
  else
  begin
    ack_sync[0]        <= ack_dst;
    for (a = 1; a < STAGES; a = a + 1)
    ack_sync[a]    <= ack_sync[a-1];
    ack_dly            <= ack_sync[STAGES-1];
  end
end
assign ack_s            = ack_sync[STAGES-1] ^ ack_dly;
`endif

endmodule
// =====================================================================================================================
// Modification History:
// 2026/07/28 v1.0 Initial version
// 2026/08/11 v1.1 Enterprise delivery: reg->wire fix, SE/SI port removal, coverage optimization
// 2026/08/19 v1.2 Split async reset into rst_src_n/rst_dst_n
// 2026/08/20 v1.3 DWBB-aligned ports: clk_s/rst_s_n/init_s_n/data_s/valid_s, clk_d/rst_d_n/init_d_n/data_d/valid_d, ack_s, test
// =====================================================================================================================

`endif
