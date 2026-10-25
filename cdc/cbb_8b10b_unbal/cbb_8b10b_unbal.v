// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CODING
// Create Date  : 2026/09/03
// Description  : 8b/10b Balance Predictor (IBM / IEEE 802.3 Clause 36)
//                Predicts the DC balance characteristics of the 10-bit symbol that would be
//                produced by CBB_8B10B_ENC for a given {ctrl_i, data_i}, without instantiating
//                the full encoder.
//                Architecture: 5b/6b + 3b/4b sub-block ones-count ROM (structured, consistent
//                with CBB_8B10B_ENC).
//                BAL_MODE=0 (default, stateless): {is_balanced, ones_cnt_max, ones_cnt_min}
//                  Range from direct same-polarity sub-block sums (always covers encoder output).
//                BAL_MODE=1 (RD-aware): RD state machine + precise ones_cnt + rd_o
//                  Encoder-accurate model mirroring CBB_8B10B_ENC's mid-symbol RD cascade:
//                  6b selected by rd_lookup; rd_mid = f(6b ones count); 4b selected by rd_mid;
//                  ones_cnt = 6b_sel + 4b_sel; RD update by total-symbol disparity.
//                Configurable pipeline: 0 (combinational pass-through), 1 register stage.
//                K-code Handling:
//                  - K.28 (abcde=0x1C, ctrl_i=1): special 5b/6b ones (4/2)
//                  - D.31 (abcde=0x1F, ctrl_i=0): valid D-code, 5b/6b ones (4/2)
//                    (101011/010100); abcde=0x1F with ctrl_i=1 is not a valid K code point
//                  - K.7  3b/4b (fgh=7): always same ones (3/1) - no D/K distinction in 3b/4b
// =====================================================================================================================
`ifndef CBB_8B10B_UNBAL_V
`define CBB_8B10B_UNBAL_V
module CBB_8B10B_UNBAL
  #(
   parameter PIPELINE                            = 1,                          // 0: comb, 1: 1-stage reg (2: NOT supported)
   parameter BAL_MODE                            = 0                           // 0: stateless range, 1: RD-aware precise
   )
   (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset (active low)
   input           [7:0]                         data_i,                       // 8-bit input data: {fgh[2:0], abcde[4:0]}
   input                                         ctrl_i,                       // Control code flag: 1=K-code, 0=D-code
   input                                         valid_i,                      // Input valid indicator
   input                                         rd_i,                         // External RD injection (used only when BAL_MODE=1)
   output          [8:0]                         bal_o,                        // 9-bit balance info (encoding depends on BAL_MODE)
   output                                        valid_o,                      // Output valid indicator
   output                                        rd_o                          // Current RD state output (used only when BAL_MODE=1)
   );

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
wire               [4:0]                         abcde;                        // 5-bit sub-block input
wire               [2:0]                         fgh;                          // 3-bit sub-block input
wire                                             is_k28;                       // K.28.x detection flag
reg                [7:0]                         ones_6b;                      // 5b/6b ones ROM: {ones_rdm[3:0], ones_rdp[3:0]}
reg                [7:0]                         ones_4b;                      // 3b/4b ones ROM: {ones_rdm[3:0], ones_rdp[3:0]}
wire               [3:0]                         ones_rdm_6b;                  // 6b ones count, RD- version
wire               [3:0]                         ones_rdp_6b;                  // 6b ones count, RD+ version
wire               [3:0]                         ones_rdm_4b;                  // 4b ones count, RD- version
wire               [3:0]                         ones_rdp_4b;                  // 4b ones count, RD+ version
wire               [4:0]                         ones_total_rdm;               // Total ones, RD- version (0~10)
wire               [4:0]                         ones_total_rdp;               // Total ones, RD+ version (0~10)
wire               [8:0]                         bal_comb;                     // Mode-selected balance output

// ---------------------------------------------------------------------------------------------------------------------
// Input Decomposition
// ---------------------------------------------------------------------------------------------------------------------
assign abcde            = data_i[4:0];
assign fgh              = data_i[7:5];

// ---------------------------------------------------------------------------------------------------------------------
// K-code Detection
//   K.28.x: ctrl_i=1, abcde=0x1C (all fgh values)
//   abcde=0x1F maps to D.31 (valid D-code, 5b/6b ones 4/2); ctrl_i=1 at 0x1F is not a
//   valid K code point -- the ROM table handles it identically to D.31.
//   No special detection needed - the ROM table handles it directly.
// ---------------------------------------------------------------------------------------------------------------------
assign is_k28           = (ctrl_i == 1'b1) && (abcde == 5'h1c);

// ---------------------------------------------------------------------------------------------------------------------
// 5b/6b Sub-block Ones-Count ROM - 32 entries
//   Format: {ones_rdm[3:0], ones_rdp[3:0]}
//   ones_rdm: ones count in RD- version of the 6-bit symbol
//   ones_rdp: ones count in RD+ version of the 6-bit symbol
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : ONES_6B_ROM_PROC
  case (abcde)
    //  D.x   ones(RD-) ones(RD+)
    5'h00   : ones_6b = {4'd4, 4'd2};                                          // D.0:  100111 / 011000
    5'h01   : ones_6b = {4'd4, 4'd2};                                          // D.1:  011101 / 100010
    5'h02   : ones_6b = {4'd4, 4'd2};                                          // D.2:  101101 / 010010
    5'h03   : ones_6b = {4'd3, 4'd3};                                          // D.3:  110001 balanced
    5'h04   : ones_6b = {4'd4, 4'd2};                                          // D.4:  110101 / 001010
    5'h05   : ones_6b = {4'd3, 4'd3};                                          // D.5:  101001 balanced
    5'h06   : ones_6b = {4'd3, 4'd3};                                          // D.6:  011001 balanced
    5'h07   : ones_6b = {4'd3, 4'd3};                                          // D.7:  111000 / 000111 (both 3)
    5'h08   : ones_6b = {4'd4, 4'd2};                                          // D.8:  111001 / 000110
    5'h09   : ones_6b = {4'd3, 4'd3};                                          // D.9:  100101 balanced
    5'h0a   : ones_6b = {4'd3, 4'd3};                                          // D.10: 010101 balanced
    5'h0b   : ones_6b = {4'd3, 4'd3};                                          // D.11: 110100 balanced
    5'h0c   : ones_6b = {4'd3, 4'd3};                                          // D.12: 001101 balanced
    5'h0d   : ones_6b = {4'd3, 4'd3};                                          // D.13: 101100 balanced
    5'h0e   : ones_6b = {4'd3, 4'd3};                                          // D.14: 011100 balanced
    5'h0f   : ones_6b = {4'd4, 4'd2};                                          // D.15: 010111 / 101000
    5'h10   : ones_6b = {4'd4, 4'd2};                                          // D.16: 011011 / 100100
    5'h11   : ones_6b = {4'd3, 4'd3};                                          // D.17: 100011 balanced
    5'h12   : ones_6b = {4'd3, 4'd3};                                          // D.18: 010011 balanced
    5'h13   : ones_6b = {4'd3, 4'd3};                                          // D.19: 110010 balanced
    5'h14   : ones_6b = {4'd3, 4'd3};                                          // D.20: 001011 balanced
    5'h15   : ones_6b = {4'd3, 4'd3};                                          // D.21: 101010 balanced
    5'h16   : ones_6b = {4'd3, 4'd3};                                          // D.22: 011010 balanced
    5'h17   : ones_6b = {4'd4, 4'd2};                                          // D.23: 111010 / 000101
    5'h18   : ones_6b = {4'd4, 4'd2};                                          // D.24: 110011 / 001100
    5'h19   : ones_6b = {4'd3, 4'd3};                                          // D.25: 100110 balanced
    5'h1a   : ones_6b = {4'd3, 4'd3};                                          // D.26: 010110 balanced
    5'h1b   : ones_6b = {4'd4, 4'd2};                                          // D.27: 110110 / 001001
    5'h1c   : ones_6b = (is_k28 == 1'b1) ? {4'd4, 4'd2} : {4'd3, 4'd3};        // K.28 / D.28
    5'h1d   : ones_6b = {4'd4, 4'd2};                                          // D.29: 101110 / 010001
    5'h1e   : ones_6b = {4'd4, 4'd2};                                          // D.30: 011110 / 100001
    5'h1f   : ones_6b = {4'd4, 4'd2};                                          // D.31: 101011 / 010100 (valid D-code)
    default : ones_6b = {4'd0, 4'd0};
  endcase

end

// ---------------------------------------------------------------------------------------------------------------------
// 3b/4b Sub-block Ones-Count ROM - 8 entries
//   Format: {ones_rdm[3:0], ones_rdp[3:0]}
//   Note: fgh=7 has no D/K distinction in 3b/4b - always same entries
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : ONES_4B_ROM_PROC
  case (fgh)
    //  D.x   ones(RD-) ones(RD+)
    3'h0    : ones_4b = {4'd3, 4'd1};                                          // fgh=0: 1011 / 0100
    3'h1    : ones_4b = {4'd2, 4'd2};                                          // fgh=1: 1001 balanced
    3'h2    : ones_4b = {4'd2, 4'd2};                                          // fgh=2: 0101 balanced
    3'h3    : ones_4b = {4'd2, 4'd2};                                          // fgh=3: 1100 / 0011 (both 2)
    3'h4    : ones_4b = {4'd3, 4'd1};                                          // fgh=4: 1101 / 0010
    3'h5    : ones_4b = {4'd2, 4'd2};                                          // fgh=5: 1010 balanced
    3'h6    : ones_4b = {4'd2, 4'd2};                                          // fgh=6: 0110 balanced
    3'h7    : ones_4b = {4'd3, 4'd1};                                          // fgh=7: 0111 / 1000 (K.7 3b/4b)
    default : ones_4b = {4'd0, 4'd0};
  endcase

end

// ---------------------------------------------------------------------------------------------------------------------
// Total Ones Count (sum of sub-blocks)
// ---------------------------------------------------------------------------------------------------------------------
assign ones_rdm_6b      = ones_6b[7:4];
assign ones_rdp_6b      = ones_6b[3:0];
assign ones_rdm_4b      = ones_4b[7:4];
assign ones_rdp_4b      = ones_4b[3:0];

// ones_total_rdm/rdp: BM0 (range mode) uses these direct same-polarity sums.
// BM1 (precise mode) uses the encoder-accurate rd_mid cascade instead (see GEN_BM1_BRANCH);
// in BM1-only elaborations these signals are intentionally unconnected (lint W528 tolerated).
assign ones_total_rdm   = {1'b0, ones_rdm_6b} + {1'b0, ones_rdm_4b};
assign ones_total_rdp   = {1'b0, ones_rdp_6b} + {1'b0, ones_rdp_4b};

// ---------------------------------------------------------------------------------------------------------------------
// Mode Selection / Balance Output
//   BAL_MODE=0: stateless range {is_balanced, ones_cnt_max, ones_cnt_min}
//   BAL_MODE=1: RD-aware precise {is_balanced, ones_cnt, 4'd0}
//   BM1 的 RD 状态机与 bal_o 寄存按 BAL_MODE/PIPELINE 各自分支产生，
//   避免默认配置(BAL_MODE=0)下 SpyGlass 折叠出 "set but not read"。
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (BAL_MODE == 0)
  begin : GEN_BM0_BRANCH
    wire                                         bm0_is_balanced;                                                       // BM0: balanced flag
    wire           [3:0]                         bm0_ones_min;                                                          // BM0: min ones count
    wire           [3:0]                         bm0_ones_max;                                                          // BM0: max ones count

    assign bm0_ones_min      = (ones_total_rdm < ones_total_rdp) ? ones_total_rdm[3:0] : ones_total_rdp[3:0];
    assign bm0_ones_max      = (ones_total_rdm > ones_total_rdp) ? ones_total_rdm[3:0] : ones_total_rdp[3:0];
    assign bm0_is_balanced   = (bm0_ones_min == bm0_ones_max);
    assign bal_comb          = {bm0_is_balanced, bm0_ones_max, bm0_ones_min};

    if (PIPELINE == 1)
    begin : GEN_BM0_PIPE1_BRANCH
      reg          [8:0]                         reg_bal;                                          // Registered balance info
      reg                                        reg_valid;                                        // Registered valid

      always @(posedge clk or negedge rst_n)
      begin : BAL_REG_PROC
        if (rst_n == 1'b0)
        begin
          reg_bal          <= 9'b000000000;
        end
        else
        begin
          reg_bal          <= bal_comb;
        end
      end

      always @(posedge clk or negedge rst_n)
      begin : VALID_REG_PROC
        if (rst_n == 1'b0)
        begin
          reg_valid        <= 1'b0;
        end
        else
        begin
          reg_valid        <= valid_i;
        end
      end

      assign bal_o      = reg_bal;
      assign valid_o    = reg_valid;
      assign rd_o       = 1'b0;
    end
    else if (PIPELINE == 0)
    begin : GEN_BM0_PIPE0_BRANCH
      assign bal_o      = bal_comb;
      assign valid_o    = valid_i;
      assign rd_o       = 1'b0;
    end
    else
    begin : GEN_BM0_UNSUPPORTED_BRANCH
      assign bal_o      = {9{1'bx}};
      assign valid_o    = 1'bx;
      assign rd_o       = 1'bx;
    end
  end
  else
  begin : GEN_BM1_BRANCH
    wire                                         rd_lookup;                                           // RD used for lookup (rd_i injection)
    wire                                         bm1_is_balanced;                                     // BM1: balanced flag
    wire           [3:0]                         bm1_ones_cnt;                                        // BM1: precise ones count
    wire           [3:0]                         ones_6b_sel;                                         // Selected 6b ones (by rd_lookup)
    wire                                         rd_mid_pred;                                         // Mid-symbol RD (mirrors encoder rd_mid)
    wire                                         next_rd;                                             // Next RD state
    reg                                          current_rd;                                          // RD state: 0=RD-, 1=RD+

    // rd_lookup: rd_i provides external RD injection when BAL_MODE=1
    // (rd_i sampled on valid_i=1, used as lookup RD)
    assign rd_lookup    = (rd_i == 1'b0) ? 1'b0 : 1'b1;

    // Encoder-accurate model (mirrors CBB_8B10B_ENC):
    //   6b selected by rd_lookup; rd_mid = f(6b ones count) with mid-symbol RD cascade;
    //   4b selected by rd_mid; total = 6b_sel + 4b_sel.
    assign ones_6b_sel  = (rd_lookup == 1'b0) ? ones_rdm_6b : ones_rdp_6b;

    assign rd_mid_pred  = (ones_6b_sel == 4'd3) ? rd_lookup :
                          (ones_6b_sel == 4'd4) ? 1'b1 :
                          (ones_6b_sel == 4'd2) ? 1'b0 :
                          rd_lookup;

    assign bm1_ones_cnt      = ones_6b_sel + (rd_mid_pred == 1'b1 ? ones_rdp_4b : ones_rdm_4b);
    assign bm1_is_balanced   = (bm1_ones_cnt == 4'd5);
    assign bal_comb          = {bm1_is_balanced, bm1_ones_cnt, 4'd0};

    // Next RD computation (mirrors encoder total-symbol disparity rule):
    //   Balanced (ones=5) -> RD unchanged; else flip
    assign next_rd      = (bm1_ones_cnt == 4'd5) ? rd_lookup : ~rd_lookup;

    // RD state register
    always @(posedge clk or negedge rst_n)
    begin : RD_REG_PROC
      if (rst_n == 1'b0)
      begin
        current_rd         <= 1'b0;                                                                     // init RD-
      end
      else if (valid_i == 1'b1)
      begin
        current_rd         <= next_rd;
      end
    end

    if (PIPELINE == 1)
    begin : GEN_BM1_PIPE1_BRANCH
      reg          [8:0]                         reg_bal;                                          // Registered balance info
      reg                                        reg_valid;                                        // Registered valid
      reg                                        reg_rd;                                           // Registered RD (output the RD used for this prediction)

      always @(posedge clk or negedge rst_n)
      begin : BAL_REG_PROC
        if (rst_n == 1'b0)
        begin
          reg_bal          <= 9'b000000000;
        end
        else
        begin
          reg_bal          <= bal_comb;
        end
      end

      always @(posedge clk or negedge rst_n)
      begin : VALID_REG_PROC
        if (rst_n == 1'b0)
        begin
          reg_valid        <= 1'b0;
        end
        else
        begin
          reg_valid        <= valid_i;
        end
      end

      always @(posedge clk or negedge rst_n)
      begin : RD_OUT_REG_PROC
        if (rst_n == 1'b0)
        begin
          reg_rd           <= 1'b0;
        end
        else
        begin
          reg_rd           <= current_rd;                                                                // output the RD used for this prediction
        end
      end

      assign bal_o      = reg_bal;
      assign valid_o    = reg_valid;
      assign rd_o       = reg_rd;
    end
    else if (PIPELINE == 0)
    begin : GEN_BM1_PIPE0_BRANCH
      assign bal_o      = bal_comb;
      assign valid_o    = valid_i;
      assign rd_o       = current_rd;
    end
    else
    begin : GEN_BM1_UNSUPPORTED_BRANCH
      assign bal_o      = {9{1'bx}};
      assign valid_o    = 1'bx;
      assign rd_o       = 1'bx;
    end
  end
endgenerate

endmodule
`endif
// =====================================================================================================================
// Modified history
// =====================================================================================================================
//
