// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CODING
// Create Date  : 2026/09/03
// Description  : 8b/10b Encoder (IBM / IEEE 802.3 Clause 36)
//                Structured 5b/6b + 3b/4b sub-encoder architecture with RD state machine.
//                Architecture:
//                  data_i[7:0] = {fgh[2:0], abcde[4:0]}
//                    abcde -> 5b/6b sub-encoder (32 entries, depends on RD) -> 6-bit
//                    fgh   -> 3b/4b sub-encoder (8 entries, depends on RD after 5b/6b) -> 4-bit
//                  sym_o[9:0] = {sym_6b, sym_4b}, RD update via popcount of sym_o.
//                  Per IBM 8b/10b spec: the 3b/4b sub-encoder uses the RD *after* the
//                  5b/6b sub-block (mid-symbol RD, rd_mid); D.x.7 uses the primary
//                  encoding 1110/0001, with the alternate 0111/1000 only for the
//                  run-length rule x={17,18,20}@RD- / x={11,13,14}@RD+.
//                Parameters: PIPELINE (0/1/2), RD_EXT (0/1).
// =====================================================================================================================
`ifndef CBB_8B10B_ENC_V
`define CBB_8B10B_ENC_V
module CBB_8B10B_ENC
  #(
   parameter PIPELINE                            = 1,                          // 0: comb, 1: 1-stage reg, 2: 2-stage reg
   parameter RD_EXT                              = 0                           // 0: rd_o tied 0, 1: rd_o active
   )
   (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset (active low)
   input           [7:0]                         data_i,                       // 8-bit input data: {fgh[2:0], abcde[4:0]}
   input                                         ctrl_i,                       // Control code flag: 1=K-code, 0=D-code
   input                                         valid_i,                      // Input valid indicator
   input                                         rd_i,                         // External RD input (used only when RD_EXT=1)
   output          [9:0]                         sym_o,                        // 10-bit encoded output symbol
   output                                        valid_o,                      // Output valid indicator
   output                                        rd_o                          // Running disparity output
   );

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
wire               [4:0]                         abcde;                        // 5-bit sub-block input
wire               [2:0]                         fgh;                          // 3-bit sub-block input
reg                [5:0]                         sym_6b;                       // 5b/6b sub-encoder output
reg                [3:0]                         sym_4b;                       // 3b/4b sub-encoder output
wire               [9:0]                         sym_comb;                     // Assembled symbol {sym_6b, sym_4b}
wire               [3:0]                         ones;                         // Popcount of sym_comb
wire               [1:0]                         disp;                         // Disparity class of sym_comb
wire               [2:0]                         ones6b;                       // Popcount of sym_6b
wire               [1:0]                         disp6b;                       // Disparity class of sym_6b
wire                                             rd_mid;                       // RD after 5b/6b sub-block (drives 3b/4b selection)
wire                                             next_rd;                      // Next RD state
wire               [9:0]                         s1_sym;                       // Stage 1 symbol
wire                                             s1_valid;                     // Stage 1 valid
wire                                             s1_rd;                        // Stage 1 RD
wire               [9:0]                         s2_sym;                       // Stage 2 symbol
wire                                             s2_valid;                     // Stage 2 valid
wire                                             s2_rd;                        // Stage 2 RD
reg                                              current_rd = 1'b0;            // RD state: 0=RD-, 1=RD+ (init RD-)

// ---------------------------------------------------------------------------------------------------------------------
// Input Decomposition
// ---------------------------------------------------------------------------------------------------------------------
assign abcde            = data_i[4:0];
assign fgh              = data_i[7:5];

// ---------------------------------------------------------------------------------------------------------------------
// 5b/6b Sub-Encoder - 32 entries, selected by current_rd
//   current_rd=0 (RD-): use rd_minus codeword (need positive disparity)
//   current_rd=1 (RD+): use rd_plus codeword (need negative disparity)
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : SYM_6B_ENC_PROC
  case (abcde)
    5'h00   : sym_6b = (current_rd == 1'b0) ? 6'b100111 : 6'b011000;           // D.0
    5'h01   : sym_6b = (current_rd == 1'b0) ? 6'b011101 : 6'b100010;           // D.1
    5'h02   : sym_6b = (current_rd == 1'b0) ? 6'b101101 : 6'b010010;           // D.2
    5'h03   : sym_6b = 6'b110001;                                              // D.3  balanced
    5'h04   : sym_6b = (current_rd == 1'b0) ? 6'b110101 : 6'b001010;           // D.4
    5'h05   : sym_6b = 6'b101001;                                              // D.5  balanced
    5'h06   : sym_6b = 6'b011001;                                              // D.6  balanced
    5'h07   : sym_6b = (current_rd == 1'b0) ? 6'b111000 : 6'b000111;           // D.7
    5'h08   : sym_6b = (current_rd == 1'b0) ? 6'b111001 : 6'b000110;           // D.8
    5'h09   : sym_6b = 6'b100101;                                              // D.9  balanced
    5'h0a   : sym_6b = 6'b010101;                                              // D.10 balanced
    5'h0b   : sym_6b = 6'b110100;                                              // D.11 balanced
    5'h0c   : sym_6b = 6'b001101;                                              // D.12 balanced
    5'h0d   : sym_6b = 6'b101100;                                              // D.13 balanced
    5'h0e   : sym_6b = 6'b011100;                                              // D.14 balanced
    5'h0f   : sym_6b = (current_rd == 1'b0) ? 6'b010111 : 6'b101000;           // D.15
    5'h10   : sym_6b = (current_rd == 1'b0) ? 6'b011011 : 6'b100100;           // D.16
    5'h11   : sym_6b = 6'b100011;                                              // D.17 balanced
    5'h12   : sym_6b = 6'b010011;                                              // D.18 balanced
    5'h13   : sym_6b = 6'b110010;                                              // D.19 balanced
    5'h14   : sym_6b = 6'b001011;                                              // D.20 balanced
    5'h15   : sym_6b = 6'b101010;                                              // D.21 balanced
    5'h16   : sym_6b = 6'b011010;                                              // D.22 balanced
    5'h17   : sym_6b = (current_rd == 1'b0) ? 6'b111010 : 6'b000101;           // D.23
    5'h18   : sym_6b = (current_rd == 1'b0) ? 6'b110011 : 6'b001100;           // D.24
    5'h19   : sym_6b = 6'b100110;                                              // D.25 balanced
    5'h1a   : sym_6b = 6'b010110;                                              // D.26 balanced
    5'h1b   : sym_6b = (current_rd == 1'b0) ? 6'b110110 : 6'b001001;           // D.27
    5'h1c   : sym_6b = (ctrl_i == 1'b1) ? ((current_rd == 1'b0) ? 6'b001111 : 6'b110000) : 6'b001110; // D.28 bal / K.28
    5'h1d   : sym_6b = (current_rd == 1'b0) ? 6'b101110 : 6'b010001;           // D.29
    5'h1e   : sym_6b = (current_rd == 1'b0) ? 6'b011110 : 6'b100001;           // D.30
    5'h1f   : sym_6b = (current_rd == 1'b0) ? 6'b101011 : 6'b010100;           // D.31
    default : sym_6b = 6'b000000;
  endcase

end

// ---------------------------------------------------------------------------------------------------------------------
// 3b/4b Sub-Encoder - 8 entries, selected by rd_mid (RD after 5b/6b per IBM 8b/10b spec)
//   D/K variant pairs per Widmer table: .1 1001/0110(K), .2 0101/1010(K), .5 1010/0101(K), .6 0110/1001(K)
//   D.x.7: primary (P7) 1110/0001; alternate (A7) 0111/1000 only for x={17,18,20}@RD- / x={11,13,14}@RD+ (run-length rule)
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : SYM_4B_ENC_PROC
  case (fgh)
    3'h0    : sym_4b = (rd_mid == 1'b0) ? 4'b1011 : 4'b0100;                   // .0
    3'h1    : sym_4b = (ctrl_i == 1'b1) ? ((rd_mid == 1'b0) ? 4'b0110 : 4'b1001)
                                        : 4'b1001;                             // .1 (K variant per table)
    3'h2    : sym_4b = (ctrl_i == 1'b1) ? ((rd_mid == 1'b0) ? 4'b1010 : 4'b0101)
                                        : 4'b0101;                             // .2 (K variant per table)
    3'h3    : sym_4b = (rd_mid == 1'b0) ? 4'b1100 : 4'b0011;                   // .3
    3'h4    : sym_4b = (rd_mid == 1'b0) ? 4'b1101 : 4'b0010;                   // .4
    3'h5    : sym_4b = (ctrl_i == 1'b1) ? ((rd_mid == 1'b0) ? 4'b0101 : 4'b1010)
                                        : 4'b1010;                             // .5 (K variant per table)
    3'h6    : sym_4b = (ctrl_i == 1'b1) ? ((rd_mid == 1'b0) ? 4'b1001 : 4'b0110)
                                        : 4'b0110;                             // .6 (K variant per table)
    3'h7    : begin                                                            // .7
                if (ctrl_i == 1'b1)
                  sym_4b = (rd_mid == 1'b0) ? 4'b0111 : 4'b1000;               // K.x.7 (= D.x.A7 pattern)
                else if ((rd_mid == 1'b0 && (abcde == 5'd17 || abcde == 5'd18 || abcde == 5'd20)) ||
                         (rd_mid == 1'b1 && (abcde == 5'd11 || abcde == 5'd13 || abcde == 5'd14)))
                  sym_4b = (rd_mid == 1'b0) ? 4'b0111 : 4'b1000;               // D.x.A7 (run-length rule)
                else
                  sym_4b = (rd_mid == 1'b0) ? 4'b1110 : 4'b0001;               // D.x.P7 (primary)
              end
    default : sym_4b = 4'b0000;
  endcase

end

// ---------------------------------------------------------------------------------------------------------------------
// Mid-symbol RD (rd_mid): RD after the 5b/6b sub-block, drives the 3b/4b sub-encoder
//   balanced (disp6b=00) -> hold; positive (disp6b=01, 4 ones) -> RD+; negative (disp6b=10, 2 ones) -> RD-
// ---------------------------------------------------------------------------------------------------------------------
assign ones6b           = sym_6b[0] + sym_6b[1] + sym_6b[2] + sym_6b[3] + sym_6b[4] + sym_6b[5];

assign disp6b           = (ones6b == 3'd3) ? 2'b00 :                                               // balanced (3 ones)
                          (ones6b == 3'd4) ? 2'b01 :                                               // positive disparity (4 ones, +2)
                          (ones6b == 3'd2) ? 2'b10 :                                               // negative disparity (2 ones, -2)
                          2'b11;                                                                   // invalid (defensive)

assign rd_mid           = (disp6b == 2'b00) ? current_rd :
                          (disp6b == 2'b01) ? 1'b1 :
                          (disp6b == 2'b10) ? 1'b0 :
                          current_rd;

// ---------------------------------------------------------------------------------------------------------------------
// Assemble Symbol + Disparity via popcount
// ---------------------------------------------------------------------------------------------------------------------
assign sym_comb         = {sym_6b, sym_4b};

assign ones             = sym_comb[0] + sym_comb[1] + sym_comb[2] + sym_comb[3] + sym_comb[4]
                          + sym_comb[5] + sym_comb[6] + sym_comb[7] + sym_comb[8] + sym_comb[9];

assign disp             = (ones == 4'd5) ? 2'b00 : (ones == 4'd6) ? 2'b01 : (ones == 4'd4) ? 2'b10 : 2'b11;

// ---------------------------------------------------------------------------------------------------------------------
// RD Next State
//   balanced (disp=00) -> hold; positive (disp=01) -> RD+; negative (disp=10) -> RD-
// ---------------------------------------------------------------------------------------------------------------------
assign next_rd          = (disp == 2'b00) ? current_rd :
                          (disp == 2'b01) ? 1'b1 :
                          (disp == 2'b10) ? 1'b0 :
                          current_rd;

// ---------------------------------------------------------------------------------------------------------------------
// RD State Register
//   RD_EXT=1: external rd_i overrides internal tracking on valid_i
//   PIPELINE=0: RD tracking not meaningful for combinational path, hold reset value
//   rd_i referenced structurally via parameter ternary so it is always "read" (W240 clean)
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (PIPELINE >= 1)
  begin : GEN_RD_REG_BRANCH
    always @(posedge clk or negedge rst_n)
    begin : RD_REG_PROC
      if (rst_n == 1'b0)
      begin
        current_rd      <= 1'b0;
      end
      else if (valid_i == 1'b1)
      begin
        if (RD_EXT == 1)
        begin
          current_rd    <= rd_i;
        end
        else
        begin
          current_rd    <= next_rd;
        end
      end
    end
  end
  else
  begin : GEN_RD_HOLD_BRANCH
    always @(*)
    begin : RD_HOLD_PROC
      current_rd        = 1'b0;
    end
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Pipeline Stage 1
//   PIPELINE >= 1 : register stage after encoder logic
//   PIPELINE == 0 : combinational pass-through
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (PIPELINE >= 1)
  begin : GEN_STAGE1_BRANCH
    reg            [9:0]                         reg_sym;                  // Registered symbol
    reg                                          reg_valid;                // Registered valid
    reg                                          reg_rd;                   // Registered RD

    always @(posedge clk or negedge rst_n)
    begin : SYM_REG_PROC
      if (rst_n == 1'b0)
      begin
        reg_sym         <= 10'b0000000000;
      end
      else
      begin
        reg_sym         <= sym_comb;
      end
    end

    always @(posedge clk or negedge rst_n)
    begin : VALID_REG_PROC
      if (rst_n == 1'b0)
      begin
        reg_valid       <= 1'b0;
      end
      else
      begin
        reg_valid       <= valid_i;
      end
    end

    always @(posedge clk or negedge rst_n)
    begin : RD_OUT_REG_PROC
      if (rst_n == 1'b0)
      begin
        reg_rd          <= 1'b0;
      end
      else
      begin
        reg_rd          <= next_rd;
      end
    end

    assign s1_sym       = reg_sym;
    assign s1_valid     = reg_valid;
    assign s1_rd        = reg_rd;
  end
  else
  begin : GEN_STAGE1_BYPASS_BRANCH
    assign s1_sym       = sym_comb;
    assign s1_valid     = valid_i;
    assign s1_rd        = next_rd;
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Pipeline Stage 2
//   PIPELINE == 2 : second register stage (no combinational logic between)
//   PIPELINE <= 1 : pass-through
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (PIPELINE == 2)
  begin : GEN_STAGE2_BRANCH
    reg            [9:0]                         reg_sym;                  // Registered stage 1 symbol
    reg                                          reg_valid;                // Registered stage 1 valid
    reg                                          reg_rd;                   // Registered stage 1 RD

    always @(posedge clk or negedge rst_n)
    begin : SYM_REG2_PROC
      if (rst_n == 1'b0)
      begin
        reg_sym         <= 10'b0000000000;
      end
      else
      begin
        reg_sym         <= s1_sym;
      end
    end

    always @(posedge clk or negedge rst_n)
    begin : VALID_REG2_PROC
      if (rst_n == 1'b0)
      begin
        reg_valid       <= 1'b0;
      end
      else
      begin
        reg_valid       <= s1_valid;
      end
    end

    always @(posedge clk or negedge rst_n)
    begin : RD_REG2_PROC
      if (rst_n == 1'b0)
      begin
        reg_rd          <= 1'b0;
      end
      else
      begin
        reg_rd          <= s1_rd;
      end
    end

    assign s2_sym       = reg_sym;
    assign s2_valid     = reg_valid;
    assign s2_rd        = reg_rd;
  end
  else
  begin : GEN_STAGE2_BYPASS_BRANCH
    assign s2_sym       = s1_sym;
    assign s2_valid     = s1_valid;
    assign s2_rd        = s1_rd;
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Output Assignment
//   rd_i port: present always, used only when RD_EXT=1 (external RD overrides internal tracking)
// ---------------------------------------------------------------------------------------------------------------------
assign sym_o            = s2_sym;
assign valid_o          = s2_valid;
// s2_rd referenced structurally via parameter ternary so it is always "read" (W528 clean)
assign rd_o             = (RD_EXT == 1) ? s2_rd : 1'b0;

endmodule
`endif
// =====================================================================================================================
// Modified history
// =====================================================================================================================
//
