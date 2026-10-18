// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CODING
// Create Date  : 2026/09/03
// Description  : 8b/10b Decoder (IBM / IEEE 802.3 Clause 36)
//                Structured 5b/6b + 3b/4b sub-decoder architecture.
//                ROM: 64x7 + 16x5 = 528 bits total (compares to 12,288 bits for flat 1024x12).
//                Architecture:
//                  sym_i[9:0] = {sym_6b[5:0], sym_4b[3:0]}
//                    sym_6b -> 5b/6b sub-decoder (64x7) -> {err6, is_k6, data5[4:0]}
//                    sym_4b -> 3b/4b sub-decoder (16x5) -> {err4, is_k4, data3[2:0]}
//                  Combine + K-detect + RD check (popcount) + Pipeline -> output.
//                Disparity computed from input symbol via popcount (no ROM storage needed):
//                  ones=5 -> balanced, ones=6 -> positive(+2), ones=4 -> negative(-2), else illegal.
//                Parameters: PIPELINE (0/1/2), RD_EXT (0/1).
// =====================================================================================================================
`ifndef CBB_8B10B_DEC_V
`define CBB_8B10B_DEC_V
module CBB_8B10B_DEC
  #(
   parameter PIPELINE                            = 1,                          // 0: comb, 1: 1-stage reg, 2: 2-stage reg
   parameter RD_EXT                              = 0                           // 0: rd_o tied 0, 1: rd_o active
   )
   (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset (active low)
   input           [9:0]                         sym_i,                        // 10-bit input symbol (aligned with valid_i)
   input                                         valid_i,                      // Input valid indicator
   output          [7:0]                         data_o,                       // 8-bit decoded data / control type ID
   output                                        ctrl_o,                       // Control code flag: 1=K-code, 0=D-code
   output                                        err_o,                        // Illegal codeword flag: 1=illegal symbol
   output                                        valid_o,                      // Output valid indicator
   output                                        rd_o                          // Running disparity output
   );

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
reg                [6:0]                         dec6;                         // 5b/6b sub-decode: {err6, is_k6, data5[4:0]}
reg                [4:0]                         dec4;                         // 3b/4b sub-decode: {err4, is_k4, data3[2:0]}
wire               [3:0]                         ones;                         // Popcount of sym_i
wire                                             err6;                         // 6b codeword error
wire                                             is_k6;                        // 6b K-flag
wire               [4:0]                         data5;                        // 6b decoded data
wire                                             err4;                         // 4b codeword error
wire                                             is_k4;                        // 4b K-flag
wire               [2:0]                         data3;                        // 4b decoded data
wire                                             err_raw;                      // Combined raw error (sub-decoders + disparity)
wire                                             ctrl_raw;                     // Combined raw ctrl
wire               [7:0]                         data_raw;                     // Combined raw data
wire                                             invalid_disp;                 // Invalid disparity flag
wire               [2:0]                         ones6b_d;                     // Popcount of sym_i[9:4] (for K28 4b disambiguation)
wire               [1:0]                         disp6b_d;                     // Disparity class of sym_i[9:4]
wire                                             rd_mid_d;                     // RD after 5b/6b sub-block (K28 4b disambiguation)
reg                [2:0]                         k28_y;                        // K28.y y-value after RD-aware remap
wire               [2:0]                         data3_eff;                    // Effective 3b/4b decode output
wire                                             valid_k28;                    // K28.x valid flag
wire                                             valid_k7fam;                  // K23.7/K27.7/K29.7/K30.7 valid flag
wire                                             valid_k;                      // Valid K-code flag
wire               [1:0]                         disp;                         // Disparity class of sym_i
wire               [1:0]                         disp_eff;                     // Effective disparity (invalid -> 2'b11)
wire                                             rd_mismatch;                  // RD consistency violation flag
wire                                             err_pre;                      // Pre-pipeline error flag
wire                                             next_rd_comb;                 // Next RD state (combinational)
wire               [9:0]                         s1_data;                      // Stage 1 data: {err, ctrl, data[7:0]}
wire                                             s1_valid;                     // Stage 1 valid
wire                                             s1_rd;                        // Stage 1 RD
wire               [9:0]                         s2_data;                      // Stage 2 data
wire                                             s2_valid;                     // Stage 2 valid
wire                                             s2_rd;                        // Stage 2 RD
reg                                              current_rd = 1'b0;            // RD state: 0=RD-, 1=RD+ (init RD-)

// ---------------------------------------------------------------------------------------------------------------------
// 5b/6b Sub-Decoder - 64 entries x 7 bits = {err, is_k, data[4:0]}
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : DEC6_PROC
  case (sym_i[9:4])
    // D.0  RD-=100111, RD+=011000
    6'b100111 : dec6 = {1'b0, 1'b0, 5'h00};
    6'b011000 : dec6 = {1'b0, 1'b0, 5'h00};
    // D.1  RD-=011101, RD+=100010
    6'b011101 : dec6 = {1'b0, 1'b0, 5'h01};
    6'b100010 : dec6 = {1'b0, 1'b0, 5'h01};
    // D.2  RD-=101101, RD+=010010
    6'b101101 : dec6 = {1'b0, 1'b0, 5'h02};
    6'b010010 : dec6 = {1'b0, 1'b0, 5'h02};
    // D.3  balanced 110001
    6'b110001 : dec6 = {1'b0, 1'b0, 5'h03};
    // D.4  RD-=110101, RD+=001010
    6'b110101 : dec6 = {1'b0, 1'b0, 5'h04};
    6'b001010 : dec6 = {1'b0, 1'b0, 5'h04};
    // D.5  balanced 101001
    6'b101001 : dec6 = {1'b0, 1'b0, 5'h05};
    // D.6  balanced 011001
    6'b011001 : dec6 = {1'b0, 1'b0, 5'h06};
    // D.7  RD-=111000, RD+=000111
    6'b111000 : dec6 = {1'b0, 1'b0, 5'h07};
    6'b000111 : dec6 = {1'b0, 1'b0, 5'h07};
    // D.8  RD-=111001, RD+=000110
    6'b111001 : dec6 = {1'b0, 1'b0, 5'h08};
    6'b000110 : dec6 = {1'b0, 1'b0, 5'h08};
    // D.9  balanced 100101
    6'b100101 : dec6 = {1'b0, 1'b0, 5'h09};
    // D.10 balanced 010101
    6'b010101 : dec6 = {1'b0, 1'b0, 5'h0a};
    // D.11 balanced 110100
    6'b110100 : dec6 = {1'b0, 1'b0, 5'h0b};
    // D.12 balanced 001101
    6'b001101 : dec6 = {1'b0, 1'b0, 5'h0c};
    // D.13 balanced 101100
    6'b101100 : dec6 = {1'b0, 1'b0, 5'h0d};
    // D.14 balanced 011100
    6'b011100 : dec6 = {1'b0, 1'b0, 5'h0e};
    // D.15 RD-=010111, RD+=101000
    6'b010111 : dec6 = {1'b0, 1'b0, 5'h0f};
    6'b101000 : dec6 = {1'b0, 1'b0, 5'h0f};
    // D.16 RD-=011011, RD+=100100
    6'b011011 : dec6 = {1'b0, 1'b0, 5'h10};
    6'b100100 : dec6 = {1'b0, 1'b0, 5'h10};
    // D.17 balanced 100011
    6'b100011 : dec6 = {1'b0, 1'b0, 5'h11};
    // D.18 balanced 010011
    6'b010011 : dec6 = {1'b0, 1'b0, 5'h12};
    // D.19 balanced 110010
    6'b110010 : dec6 = {1'b0, 1'b0, 5'h13};
    // D.20 balanced 001011
    6'b001011 : dec6 = {1'b0, 1'b0, 5'h14};
    // D.21 balanced 101010
    6'b101010 : dec6 = {1'b0, 1'b0, 5'h15};
    // D.22 balanced 011010
    6'b011010 : dec6 = {1'b0, 1'b0, 5'h16};
    // D.23 RD-=111010, RD+=000101
    6'b111010 : dec6 = {1'b0, 1'b0, 5'h17};
    6'b000101 : dec6 = {1'b0, 1'b0, 5'h17};
    // D.24 RD-=110011, RD+=001100
    6'b110011 : dec6 = {1'b0, 1'b0, 5'h18};
    6'b001100 : dec6 = {1'b0, 1'b0, 5'h18};
    // D.25 balanced 100110
    6'b100110 : dec6 = {1'b0, 1'b0, 5'h19};
    // D.26 balanced 010110
    6'b010110 : dec6 = {1'b0, 1'b0, 5'h1a};
    // D.27 RD-=110110, RD+=001001
    6'b110110 : dec6 = {1'b0, 1'b0, 5'h1b};
    6'b001001 : dec6 = {1'b0, 1'b0, 5'h1b};
    // D.28 balanced 001110
    6'b001110 : dec6 = {1'b0, 1'b0, 5'h1c};
    // D.29 RD-=101110, RD+=010001
    6'b101110 : dec6 = {1'b0, 1'b0, 5'h1d};
    6'b010001 : dec6 = {1'b0, 1'b0, 5'h1d};
    // D.30 RD-=011110, RD+=100001
    6'b011110 : dec6 = {1'b0, 1'b0, 5'h1e};
    6'b100001 : dec6 = {1'b0, 1'b0, 5'h1e};
    // D.31 RD-=101011, RD+=010100
    6'b101011 : dec6 = {1'b0, 1'b0, 5'h1f};
    6'b010100 : dec6 = {1'b0, 1'b0, 5'h1f};
    // K.28 (abcde=0x1C)  RD-=001111, RD+=110000
    6'b001111 : dec6 = {1'b0, 1'b1, 5'h1c};                                    // is_k=1 (K28.x family)
    6'b110000 : dec6 = {1'b0, 1'b1, 5'h1c};                                    // is_k=1
    // K23.7 uses the D23 6b pair (111010/000101, already listed above); there is no
    // dedicated "K.7" 6b codeword. 011111/100000 are +/-4 disparity and always illegal.
    default   : dec6 = {1'b1, 1'b0, 5'h00};                                    // Invalid 6b codeword
  endcase

end

// ---------------------------------------------------------------------------------------------------------------------
// 3b/4b Sub-Decoder - 16 entries x 5 bits = {err, is_k, data[2:0]}
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : DEC4_PROC
  case (sym_i[3:0])
    // D.x.0 (fgh=0): RD-=1011, RD+=0100
    4'b1011 : dec4 = {1'b0, 1'b0, 3'h0};
    4'b0100 : dec4 = {1'b0, 1'b0, 3'h0};
    // D.x.1 (fgh=1): balanced 1001
    4'b1001 : dec4 = {1'b0, 1'b0, 3'h1};
    // D.x.2 (fgh=2): balanced 0101
    4'b0101 : dec4 = {1'b0, 1'b0, 3'h2};
    // D.x.3 (fgh=3): RD-=1100, RD+=0011
    4'b1100 : dec4 = {1'b0, 1'b0, 3'h3};
    4'b0011 : dec4 = {1'b0, 1'b0, 3'h3};
    // D.x.4 (fgh=4): RD-=1101, RD+=0010
    4'b1101 : dec4 = {1'b0, 1'b0, 3'h4};
    4'b0010 : dec4 = {1'b0, 1'b0, 3'h4};
    // D.x.5 (fgh=5): balanced 1010
    4'b1010 : dec4 = {1'b0, 1'b0, 3'h5};
    // D.x.6 (fgh=6): balanced 0110
    4'b0110 : dec4 = {1'b0, 1'b0, 3'h6};
    // K.7 / D.x.A7 (fgh=7): RD-=0111, RD+=1000 (shared pattern; K/D resolved at combine stage)
    4'b0111 : dec4 = {1'b0, 1'b1, 3'h7};                                       // is_k4=1, data=7
    4'b1000 : dec4 = {1'b0, 1'b1, 3'h7};                                       // is_k4=1, data=7
    // D.x.P7 (fgh=7): RD-=1110, RD+=0001 (primary pair, most D.x.7 codes)
    4'b1110 : dec4 = {1'b0, 1'b0, 3'h7};                                       // is_k4=0, data=7
    4'b0001 : dec4 = {1'b0, 1'b0, 3'h7};                                       // is_k4=0, data=7
    default : dec4 = {1'b1, 1'b0, 3'h0};                                       // Invalid 4b codeword
  endcase

end

// ---------------------------------------------------------------------------------------------------------------------
// Disparity - popcount of 10-bit input symbol
// ---------------------------------------------------------------------------------------------------------------------
assign ones             = sym_i[0] + sym_i[1] + sym_i[2] + sym_i[3] + sym_i[4]
                          + sym_i[5] + sym_i[6] + sym_i[7] + sym_i[8] + sym_i[9];

// ---------------------------------------------------------------------------------------------------------------------
// Combine Sub-Decoders
// ---------------------------------------------------------------------------------------------------------------------
assign {err6, is_k6, data5}  = dec6;
assign {err4, is_k4, data3}  = dec4;

// K-code detection: only specific combinations are valid K-codes
//   is_k6=1 & data5=0x1C            -> K28.y family (y = data3 = 0-7)
//   data5 in {23,27,29,30} & is_k4  -> K23.7 / K27.7 / K29.7 / K30.7 (K.7 4b pair + D2x 6b)
//   D.x.A7 shares the K.7 4b pattern (0111/1000) but has data5 outside the K.7 family
//     (x in {17,18,20,11,13,14} per the run-length rule); it decodes as D.x.7, ctrl=0.
assign invalid_disp     = (ones != 4'd5) && (ones != 4'd6) && (ones != 4'd4);
assign valid_k28        = is_k6 & (data5 == 5'h1c);                                                // K28.0-K28.7
assign valid_k7fam      = (~err6) & is_k4 & ((data5 == 5'h17) | (data5 == 5'h1b) |
                                             (data5 == 5'h1d) | (data5 == 5'h1e));                 // K23.7/K27.7/K29.7/K30.7
assign valid_k          = valid_k28 | valid_k7fam;

// ---------------------------------------------------------------------------------------------------------------------
// K28 4b disambiguation
//   The K-variant 4b pairs for y=1/2/5/6 swap physical patterns vs the D-table convention
//   (e.g. K28.2+ is 110000 1010, where 4b 1010 is D.x.5's RD- pattern).  Decoding the y
//   value therefore needs rd_mid (RD after the 5b/6b sub-block).  K28 6b (001111/110000)
//   is always non-balanced, so rd_mid is disparity-derived and independent of current_rd.
// ---------------------------------------------------------------------------------------------------------------------
assign ones6b_d         = sym_i[9] + sym_i[8] + sym_i[7] + sym_i[6] + sym_i[5] + sym_i[4];
assign disp6b_d         = (ones6b_d == 3'd3) ? 2'b00 :
                          (ones6b_d == 3'd4) ? 2'b01 :
                          (ones6b_d == 3'd2) ? 2'b10 : 2'b11;
assign rd_mid_d         = (disp6b_d == 2'b01) ? 1'b1 :
                          (disp6b_d == 2'b10) ? 1'b0 : current_rd;

always @(*)
begin : K28_REMAP_PROC
  case (sym_i[3:0])
    4'b1011 : k28_y = 3'd0;                                                    // .0 RD- / D pair
    4'b0100 : k28_y = 3'd0;                                                    // .0 RD+
    4'b0011 : k28_y = 3'd3;                                                    // .3 RD+ / D pair
    4'b1100 : k28_y = 3'd3;                                                    // .3 RD-
    4'b0010 : k28_y = 3'd4;                                                    // .4 RD+ / D pair
    4'b1101 : k28_y = 3'd4;                                                    // .4 RD-
    4'b0111 : k28_y = 3'd7;                                                    // K.7 / D.x.A7 pattern
    4'b1000 : k28_y = 3'd7;                                                    // K.7 / D.x.A7 pattern
    4'b0110 : k28_y = rd_mid_d ? 3'd6 : 3'd1;                                  // .6 RD+ / .1 RD- (K swap)
    4'b1001 : k28_y = rd_mid_d ? 3'd1 : 3'd6;                                  // .1 RD+ / .6 RD- (K swap)
    4'b1010 : k28_y = rd_mid_d ? 3'd5 : 3'd2;                                  // .5 RD+ / .2 RD- (K swap)
    4'b0101 : k28_y = rd_mid_d ? 3'd2 : 3'd5;                                  // .2 RD+ / .5 RD- (K swap)
    default : k28_y = 3'd0;
  endcase
end

assign data3_eff        = (valid_k28 && (err4 == 1'b0)) ? k28_y : data3;

assign err_raw          = err6 | err4 | invalid_disp;
assign ctrl_raw         = (err_raw == 1'b0) & valid_k;
assign data_raw         = {data3_eff, data5};

assign disp             = (ones == 4'd5)  ? 2'b00 :                                                // balanced (5 ones)
                          (ones == 4'd6)  ? 2'b01 :                                                // positive disparity (6 ones, +2)
                          (ones == 4'd4)  ? 2'b10 :                                                // negative disparity (4 ones, -2)
                          2'b11;                                                 // invalid disparity
assign disp_eff         = (err_raw == 1'b1) ? 2'b11 : disp;

// ---------------------------------------------------------------------------------------------------------------------
// RD State Machine & Consistency Check
//   positive disp (01) needs RD- (0); negative disp (10) needs RD+ (1)
// ---------------------------------------------------------------------------------------------------------------------
assign rd_mismatch      = (err_raw == 1'b0) &&
                          (((disp_eff == 2'b01) && (current_rd == 1'b1)) ||
                          ((disp_eff == 2'b10) && (current_rd == 1'b0)));

assign err_pre          = err_raw | rd_mismatch;

assign next_rd_comb     = (disp_eff == 2'b00) ? current_rd :
                          (disp_eff == 2'b01) ? 1'b1 :
                          (disp_eff == 2'b10) ? 1'b0 :
                          current_rd;

// ---------------------------------------------------------------------------------------------------------------------
// RD State Register
//   PIPELINE=0: RD tracking not meaningful for combinational path, hold reset value
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
        current_rd      <= next_rd_comb;
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
//   PIPELINE >= 1 : register stage after decode logic
//   PIPELINE == 0 : combinational pass-through
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (PIPELINE >= 1)
  begin : GEN_STAGE1_BRANCH
    reg            [9:0]                         reg_data;                 // Registered {err, ctrl, data}
    reg                                          reg_valid;                // Registered valid
    reg                                          reg_rd;                   // Registered RD

    always @(posedge clk or negedge rst_n)
    begin : DATA_REG_PROC
      if (rst_n == 1'b0)
      begin
        reg_data        <= 10'b0000000000;
      end
      else
      begin
        reg_data        <= {err_pre, ctrl_raw, data_raw};
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

    if (RD_EXT == 1)
    begin : GEN_S1_RD_BRANCH
      always @(posedge clk or negedge rst_n)
      begin : RD_OUT_REG_PROC
        if (rst_n == 1'b0)
        begin
          reg_rd        <= 1'b0;
        end
        else
        begin
          reg_rd        <= next_rd_comb;
        end
      end
    end

    assign s1_data      = reg_data;
    assign s1_valid     = reg_valid;
    assign s1_rd        = (RD_EXT == 1) ? reg_rd : 1'b0;
  end
  else
  begin : GEN_STAGE1_BYPASS_BRANCH
    assign s1_data      = {err_pre, ctrl_raw, data_raw};
    assign s1_valid     = valid_i;
    assign s1_rd        = next_rd_comb;
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
    reg            [9:0]                         reg_data;                 // Registered stage 1 data
    reg                                          reg_valid;                // Registered stage 1 valid
    reg                                          reg_rd;                   // Registered stage 1 RD

    always @(posedge clk or negedge rst_n)
    begin : DATA_REG2_PROC
      if (rst_n == 1'b0)
      begin
        reg_data        <= 10'b0000000000;
      end
      else
      begin
        reg_data        <= s1_data;
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

    if (RD_EXT == 1)
    begin : GEN_S2_RD_BRANCH
      always @(posedge clk or negedge rst_n)
      begin : RD_REG2_PROC
        if (rst_n == 1'b0)
        begin
          reg_rd        <= 1'b0;
        end
        else
        begin
          reg_rd        <= s1_rd;
        end
      end
    end

    assign s2_data      = reg_data;
    assign s2_valid     = reg_valid;
    assign s2_rd        = (RD_EXT == 1) ? reg_rd : 1'b0;
  end
  else
  begin : GEN_STAGE2_BYPASS_BRANCH
    assign s2_data      = s1_data;
    assign s2_valid     = s1_valid;
    assign s2_rd        = s1_rd;
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Output Assignment
// ---------------------------------------------------------------------------------------------------------------------
assign data_o           = s2_data[7:0];
assign ctrl_o           = s2_data[8];
assign err_o            = s2_data[9];
assign valid_o          = s2_valid;

generate
  if (RD_EXT == 0)
  begin : GEN_RD_OFF_BRANCH
    assign rd_o         = 1'b0;
  end
  else
  begin : GEN_RD_ON_BRANCH
    assign rd_o         = s2_rd;
  end
endgenerate

endmodule
`endif
// =====================================================================================================================
// Modified history
// =====================================================================================================================
//
