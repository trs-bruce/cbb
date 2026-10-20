// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CODING
// Create Date  : 2026/09/03
// Description  : 4b/5b Decoder (IEEE 802.3 / FDDI Standard)
//                Decodes 5-bit encoded symbols back to 4-bit data and control identifiers.
//                Detects illegal codewords not defined in the 4b/5b code table.
//                Architecture: 32x6 LUT ROM (combinational) addressed by sym_i[4:0],
//                ROM output format: {err, ctrl, data[3:0]},
//                configurable pipeline: 0 (combinational), 1, or 2 register stages.
//                Code Table (IEEE 802.3 Clause 24 / FDDI PMD):
//                  - 16 Data codes   : sym_i -> data_o, ctrl_o=0, err_o=0
//                  -  6 Control codes: sym_i -> ctrl_o=1, err_o=0, data_o=type_id
//                  - 10 Illegal codes: err_o=1, data_o=4'b0000, ctrl_o=0
// =====================================================================================================================
`ifndef CBB_4B5B_DEC_V
`define CBB_4B5B_DEC_V
module CBB_4B5B_DEC
  #(
   parameter PIPELINE                            = 1                           // 0: comb, 1: 1-stage reg, 2: 2-stage reg
   )
   (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset (active low)
   input           [4:0]                         sym_i,                        // 5-bit encoded input symbol (aligned with valid_i)
   input                                         valid_i,                      // Input valid indicator
   output          [3:0]                         data_o,                       // 4-bit decoded data / control type ID
   output                                        ctrl_o,                       // Control code flag: 1=control, 0=data
   output                                        err_o,                        // Illegal codeword flag: 1=illegal symbol
   output                                        valid_o                       // Output valid (valid_i delayed by PIPELINE cycles)
   );

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
reg                [5:0]                         lut_rom;                      // 32x6 LUT ROM: {err, ctrl, data[3:0]}
wire               [5:0]                         s1_data;                      // Stage 1 data
wire                                             s1_valid;                     // Stage 1 valid
wire               [5:0]                         s2_data;                      // Stage 2 data
wire                                             s2_valid;                     // Stage 2 valid

// ---------------------------------------------------------------------------------------------------------------------
// LUT ROM - 32 entries x 6 bits, combinational
//   Format: {err, ctrl, data[3:0]}
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : LUT_ROM_PROC
  case (sym_i)
    // Data Codes (16 entries): {1'b0, 1'b0, 4-bit data}
    5'b11110 : lut_rom = {1'b0, 1'b0, 4'b0000};                                // 0x0 -> 11110
    5'b01001 : lut_rom = {1'b0, 1'b0, 4'b0001};                                // 0x1 -> 01001
    5'b10100 : lut_rom = {1'b0, 1'b0, 4'b0010};                                // 0x2 -> 10100
    5'b10101 : lut_rom = {1'b0, 1'b0, 4'b0011};                                // 0x3 -> 10101
    5'b01010 : lut_rom = {1'b0, 1'b0, 4'b0100};                                // 0x4 -> 01010
    5'b01011 : lut_rom = {1'b0, 1'b0, 4'b0101};                                // 0x5 -> 01011
    5'b01110 : lut_rom = {1'b0, 1'b0, 4'b0110};                                // 0x6 -> 01110
    5'b01111 : lut_rom = {1'b0, 1'b0, 4'b0111};                                // 0x7 -> 01111
    5'b10010 : lut_rom = {1'b0, 1'b0, 4'b1000};                                // 0x8 -> 10010
    5'b10011 : lut_rom = {1'b0, 1'b0, 4'b1001};                                // 0x9 -> 10011
    5'b10110 : lut_rom = {1'b0, 1'b0, 4'b1010};                                // 0xA -> 10110
    5'b10111 : lut_rom = {1'b0, 1'b0, 4'b1011};                                // 0xB -> 10111
    5'b11010 : lut_rom = {1'b0, 1'b0, 4'b1100};                                // 0xC -> 11010
    5'b11011 : lut_rom = {1'b0, 1'b0, 4'b1101};                                // 0xD -> 11011
    5'b11100 : lut_rom = {1'b0, 1'b0, 4'b1110};                                // 0xE -> 11100
    5'b11101 : lut_rom = {1'b0, 1'b0, 4'b1111};                                // 0xF -> 11101
    // Control Codes (6 entries): {1'b0, 1'b1, type_id[3:0]}
    5'b11111 : lut_rom = {1'b0, 1'b1, 4'd0};                                   // IDLE  (11111)
    5'b11000 : lut_rom = {1'b0, 1'b1, 4'd1};                                   // J/SSD1 (11000)
    5'b10001 : lut_rom = {1'b0, 1'b1, 4'd2};                                   // K/SSD2 (10001)
    5'b01101 : lut_rom = {1'b0, 1'b1, 4'd3};                                   // T/ESD1 (01101)
    5'b00111 : lut_rom = {1'b0, 1'b1, 4'd4};                                   // R/ESD2 (00111)
    5'b00100 : lut_rom = {1'b0, 1'b1, 4'd5};                                   // H/HALT (00100)
    // Illegal Codewords (10 entries): {1'b1, 1'b0, 4'b0000}
    default  : lut_rom = {1'b1, 1'b0, 4'b0000};                                // Illegal codeword
  endcase

end

// ---------------------------------------------------------------------------------------------------------------------
// Pipeline Stage 1
//   PIPELINE >= 1 : register stage after LUT ROM
//   PIPELINE == 0 : combinational pass-through
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (PIPELINE >= 1)
  begin : GEN_STAGE1_BRANCH
    reg            [5:0]                         reg_data;                 // Registered ROM output
    reg                                          reg_valid;                // Registered valid

    always @(posedge clk or negedge rst_n)
    begin : DATA_REG_PROC
      if (rst_n == 1'b0)
      begin
        reg_data        <= 6'b000000;
      end
      else
      begin
        reg_data        <= lut_rom;
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

    assign s1_data      = reg_data;
    assign s1_valid     = reg_valid;
  end
  else
  begin : GEN_STAGE1_BYPASS_BRANCH
    assign s1_data      = lut_rom;
    assign s1_valid     = valid_i;
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
    reg            [5:0]                         reg_data;                 // Registered stage 1 data
    reg                                          reg_valid;                // Registered stage 1 valid

    always @(posedge clk or negedge rst_n)
    begin : DATA_REG2_PROC
      if (rst_n == 1'b0)
      begin
        reg_data        <= 6'b000000;
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

    assign s2_data      = reg_data;
    assign s2_valid     = reg_valid;
  end
  else
  begin : GEN_STAGE2_BYPASS_BRANCH
    assign s2_data      = s1_data;
    assign s2_valid     = s1_valid;
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Output Assignment
//   s2_data[3:0] = data_o, s2_data[4] = ctrl_o, s2_data[5] = err_o
// ---------------------------------------------------------------------------------------------------------------------
assign data_o           = s2_data[3:0];
assign ctrl_o           = s2_data[4];
assign err_o            = s2_data[5];
assign valid_o          = s2_valid;

endmodule
`endif
// =====================================================================================================================
// Modified history
// =====================================================================================================================
//
