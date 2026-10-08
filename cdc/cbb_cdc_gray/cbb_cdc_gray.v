// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : -
// Project      : CBB
// Create Date  : 2026/07/28
// Description  : Gray Code Synchronizer (CBB_CDC_GRAY)
//                Binary -> Gray -> Synchronize -> Gray -> Binary.
//                Technology selection via macros (see cbb_cdc_define.v).
//                Port naming follows Synopsys DWBB convention:
//                clk_s/rst_s_n/init_s_n/data_s, clk_d/rst_d_n/init_d_n/data_d, test.
// =====================================================================================================================
`ifndef CBB_CDC_GRAY_V
`define CBB_CDC_GRAY_V
`include "cbb_cdc_define.v"

module CBB_CDC_GRAY
    #(
    parameter integer STAGES                      = 2,                          // Number of sync stages (>= 2)
    parameter integer WIDTH                       = 8                           // Data width
    )
    (
   input wire                                    clk_s,                        // Source clock
   input wire                                    rst_s_n,                      // Async reset, source domain (active low)
   input wire                                    init_s_n,                     // Sync reset, source domain (active low)
   input wire      [WIDTH-1:0]                   data_s,                       // Source domain binary data
   input wire                                    clk_d,                        // Destination clock
   input wire                                    rst_d_n,                      // Async reset, destination domain (active low)
   input wire                                    init_d_n,                     // Sync reset, destination domain (active low)
   output wire     [WIDTH-1:0]                   data_d,                       // Destination domain binary data
   input wire                                    test                          // Test mode enable
    );

// synopsys translate_off
initial begin : PARAM_CHECK_PROC
  if (STAGES < 2)
    $error("STAGES must be >= 2 (actual: %0d)", STAGES);
end
// synopsys translate_on

// ---------------------------------------------------------------------------------------------------------------------
// Source Domain: Binary -> Gray
// ---------------------------------------------------------------------------------------------------------------------
reg                [WIDTH-1:0]                   gray_reg;

always @(posedge clk_s or negedge rst_s_n)
begin : BIN2GRAY_PROC
  if (rst_s_n == 1'b0)
    gray_reg              <= {WIDTH{1'b0}};
  else if (init_s_n == 1'b0)
    gray_reg              <= {WIDTH{1'b0}};
  else
    gray_reg              <= data_s ^ {1'b0, data_s[WIDTH-1:1]};
end

// ---------------------------------------------------------------------------------------------------------------------
// Forward Sync Chain: Gray Data
// ---------------------------------------------------------------------------------------------------------------------
`ifdef TSMC_12
wire               [WIDTH-1:0]                   gray_sync_reg [STAGES-1:0];
genvar gs, gb;
generate
  for (gs = 0; gs < STAGES; gs = gs + 1)
  begin : GRAY_SYNC_LOOP
    for (gb = 0; gb < WIDTH; gb = gb + 1)
    begin : BIT_LOOP
      if (gs == 0)
      begin : STAGE0_BRANCH
        wire                                     gray_sync_reg_din;
        assign gray_sync_reg_din                 = init_d_n & (test ? gray_sync_reg[0][gb] : gray_reg[gb]);
        SDFSYNCNQD1BWP7D5T16P96CPD U_SYNC (
        .CDN                           ( rst_d_n                               ),
        .CP                            ( clk_d                                 ),
        .D                             ( gray_sync_reg_din                     ),
        .SE                            ( 1'b0                                  ),
        .SI                            ( 1'b0                                  ),
        .Q                             ( gray_sync_reg[0][gb]                  )
        );
      end
      else
      begin : STAGE_N_BRANCH
        wire                                     gray_sync_reg_din;
        assign gray_sync_reg_din                 = init_d_n & (test ? gray_sync_reg[gs][gb] : gray_sync_reg[gs-1][gb]);
        SDFSYNCNQD1BWP7D5T16P96CPD U_SYNC (
        .CDN                           ( rst_d_n                               ),
        .CP                            ( clk_d                                 ),
        .D                             ( gray_sync_reg_din                     ),
        .SE                            ( 1'b0                                  ),
        .SI                            ( 1'b0                                  ),
        .Q                             ( gray_sync_reg[gs][gb]                 )
        );
      end
    end
  end
endgenerate
wire [WIDTH-1:0] gray_sync = gray_sync_reg[STAGES-1];
`elsif FPGA_XILINX
wire               [WIDTH-1:0]                   gray_sync_reg [STAGES-1:0];
genvar xs, xb;
generate
  for (xs = 0; xs < STAGES; xs = xs + 1)
  begin : GRAY_SYNC_LOOP
    for (xb = 0; xb < WIDTH; xb = xb + 1)
    begin : BIT_LOOP
      if (xs == 0)
      begin : STAGE0_BRANCH
        wire                                     gray_sync_reg_din;
        assign gray_sync_reg_din                 = init_d_n & (test ? gray_sync_reg[0][xb] : gray_reg[xb]);
        FDCE U_SYNC (
        .Q                             ( gray_sync_reg[0][xb]                  ),
        .C                             ( clk_d                                 ),
        .CE                            ( 1'b1                                  ),
        .CLR                           ( rst_d_n                               ),
        .D                             ( gray_sync_reg_din                     )
        );
      end
      else
      begin : STAGE_N_BRANCH
        wire                                     gray_sync_reg_din;
        assign gray_sync_reg_din                 = init_d_n & (test ? gray_sync_reg[xs][xb] : gray_sync_reg[xs-1][xb]);
        FDCE U_SYNC (
        .Q                             ( gray_sync_reg[xs][xb]                 ),
        .C                             ( clk_d                                 ),
        .CE                            ( 1'b1                                  ),
        .CLR                           ( rst_d_n                               ),
        .D                             ( gray_sync_reg_din                     )
        );
      end
    end
  end
endgenerate
wire [WIDTH-1:0] gray_sync = gray_sync_reg[STAGES-1];
`elsif FPGA_ALTERA
wire               [WIDTH-1:0]                   gray_sync_reg [STAGES-1:0];
genvar as_, ab;
generate
  for (as_ = 0; as_ < STAGES; as_ = as_ + 1)
  begin : GRAY_SYNC_LOOP
    for (ab = 0; ab < WIDTH; ab = ab + 1)
    begin : BIT_LOOP
      if (as_ == 0)
      begin : STAGE0_BRANCH
        wire                                     gray_sync_reg_din;
        assign gray_sync_reg_din                 = init_d_n & (test ? gray_sync_reg[0][ab] : gray_reg[ab]);
        dffeas U_SYNC (
        .q                             ( gray_sync_reg[0][ab]                  ),
        .d                             ( gray_sync_reg_din                     ),
        .clk                           ( clk_d                                 ),
        .clrn                          ( rst_d_n                               ),
        .ena                           ( 1'b1                                  ),
        .asyncload                     ( 1'b0                                  ),
        .sload                         ( 1'b0                                  ),
        .sclr                          ( 1'b0                                  ),
        .aload                         ( 1'b0                                  ),
        .data                          ( gray_sync_reg_din                     )
        );
      end
      else
      begin : STAGE_N_BRANCH
        wire                                     gray_sync_reg_din;
        assign gray_sync_reg_din                 = init_d_n & (test ? gray_sync_reg[as_][ab] : gray_sync_reg[as_-1][ab]);
        dffeas U_SYNC (
        .q                             ( gray_sync_reg[as_][ab]                ),
        .d                             ( gray_sync_reg_din                     ),
        .clk                           ( clk_d                                 ),
        .clrn                          ( rst_d_n                               ),
        .ena                           ( 1'b1                                  ),
        .asyncload                     ( 1'b0                                  ),
        .sload                         ( 1'b0                                  ),
        .sclr                          ( 1'b0                                  ),
        .aload                         ( 1'b0                                  ),
        .data                          ( gray_sync_reg_din                     )
        );
      end
    end
  end
endgenerate
wire [WIDTH-1:0] gray_sync = gray_sync_reg[STAGES-1];

`else
reg                [WIDTH-1:0]                   gray_sync_reg [STAGES-1:0];
integer s;
always @(posedge clk_d or negedge rst_d_n)
begin : RTL_SYNC_PROC
  if (rst_d_n == 1'b0) begin
    for (s = 0; s < STAGES; s = s + 1)
    gray_sync_reg[s] <= {WIDTH{1'b0}};
  end else if (init_d_n == 1'b0) begin
    for (s = 0; s < STAGES; s = s + 1)
    gray_sync_reg[s] <= {WIDTH{1'b0}};
  end else if (test == 1'b1) begin
    for (s = 0; s < STAGES; s = s + 1)
    gray_sync_reg[s] <= gray_sync_reg[s];   // test mode: hold
  end else begin
    gray_sync_reg[0] <= gray_reg;
    for (s = 1; s < STAGES; s = s + 1)
    gray_sync_reg[s] <= gray_sync_reg[s-1];
  end
end
wire [WIDTH-1:0] gray_sync = gray_sync_reg[STAGES-1];
`endif

// ---------------------------------------------------------------------------------------------------------------------
// Destination Domain: Gray -> Binary (combinational)
// ---------------------------------------------------------------------------------------------------------------------
wire               [WIDTH-1:0]                   bin;

assign bin[WIDTH-1]          = gray_sync[WIDTH-1];

genvar gi;
generate
  for (gi = 0; gi < WIDTH-1; gi = gi + 1)
  begin : GRAY2BIN_LOOP
    assign bin[gi]      = gray_sync[gi] ^ bin[gi+1];
  end
endgenerate

assign data_d                = bin;

endmodule
// =====================================================================================================================
// Modification History:
// 2026/07/28 v1.0 Initial version
// 2026/08/11 v1.1 Enterprise delivery: reg->wire fix, SE/SI port removal, coverage optimization
// 2026/08/20 v1.2 DWBB-aligned ports: clk_s/rst_s_n/init_s_n/data_s, clk_d/rst_d_n/init_d_n/data_d, test
// =====================================================================================================================

`endif
