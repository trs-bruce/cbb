// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CODING
// Create Date  : 2026/09/03
// Description  : 4b/5b Balance Predictor (IEEE 802.3 / FDDI Standard)
//                Predicts DC balance and transition density of the 5-bit symbol that would be
//                produced by CBB_4B5B_ENC for a given {ctrl_i, data_i}, without instantiating
//                the full encoder.
//                Architecture: 32x4 LUT ROM (combinational) addressed by {ctrl_i, data_i[3:0]},
//                ROM output format: {transition_ok, ones_count[2:0]},
//                configurable pipeline: 0 (combinational pass-through), 1 register stage.
//                ROM Content:
//                  - transition_ok = (ones_count >= 2): NRZI transition density sufficient
//                  - ones_count[2:0]: number of '1' bits in the encoded 5-bit symbol
//                Code Table (IEEE 802.3 Clause 24 / FDDI PMD):
//                  - Data codes   : 16 entries, ones_count = 2~4, transition_ok = 1
//                  - Control codes: 7 standard, ones_count = 0~5, transition_ok varies
//                  - RSVD         : 9 entries (addr 0x17~0x1F), ones_count = 0, transition_ok = 0
// =====================================================================================================================
`ifndef CBB_4B5B_UNBAL_V
`define CBB_4B5B_UNBAL_V
module CBB_4B5B_UNBAL
  #(
   parameter PIPELINE                            = 1                           // 0: comb, 1: 1-stage reg (2: NOT supported)
   )
   (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset (active low)
   input           [3:0]                         data_i,                       // 4-bit raw data (ctrl_i=0) / ctrl type select (ctrl_i=1)
   input                                         ctrl_i,                       // Control code flag: 1=control, 0=data
   input                                         valid_i,                      // Input valid indicator
   output          [3:0]                         bal_o,                        // Balance info: {transition_ok, ones_count[2:0]}
   output                                        valid_o                       // Output valid (valid_i delayed by PIPELINE cycles)
   );

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
wire               [4:0]                         rom_addr;                     // ROM address {ctrl_i, data_i}
reg                [3:0]                         balance_rom;                  // 32x4 balance ROM: {tok, ones[2:0]}

// ---------------------------------------------------------------------------------------------------------------------
// ROM Address
// ---------------------------------------------------------------------------------------------------------------------
assign rom_addr         = {ctrl_i, data_i};

// ---------------------------------------------------------------------------------------------------------------------
// Balance ROM - 32 entries x 4 bits, combinational
//   Format: {transition_ok, ones_count[2:0]}
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : BALANCE_ROM_PROC
  case (rom_addr)
    // Data Codes (ctrl_i=0): 16 entries - sym | ones | tok
    5'h00   : balance_rom = 4'b1100;                                           // D0   -> 11110, ones=4, tok=1
    5'h01   : balance_rom = 4'b1010;                                           // D1   -> 01001, ones=2, tok=1
    5'h02   : balance_rom = 4'b1010;                                           // D2   -> 10100, ones=2, tok=1
    5'h03   : balance_rom = 4'b1011;                                           // D3   -> 10101, ones=3, tok=1
    5'h04   : balance_rom = 4'b1010;                                           // D4   -> 01010, ones=2, tok=1
    5'h05   : balance_rom = 4'b1011;                                           // D5   -> 01011, ones=3, tok=1
    5'h06   : balance_rom = 4'b1011;                                           // D6   -> 01110, ones=3, tok=1
    5'h07   : balance_rom = 4'b1100;                                           // D7   -> 01111, ones=4, tok=1
    5'h08   : balance_rom = 4'b1010;                                           // D8   -> 10010, ones=2, tok=1
    5'h09   : balance_rom = 4'b1011;                                           // D9   -> 10011, ones=3, tok=1
    5'h0a   : balance_rom = 4'b1011;                                           // D10  -> 10110, ones=3, tok=1
    5'h0b   : balance_rom = 4'b1100;                                           // D11  -> 10111, ones=4, tok=1
    5'h0c   : balance_rom = 4'b1011;                                           // D12  -> 11010, ones=3, tok=1
    5'h0d   : balance_rom = 4'b1100;                                           // D13  -> 11011, ones=4, tok=1
    5'h0e   : balance_rom = 4'b1011;                                           // D14  -> 11100, ones=3, tok=1
    5'h0f   : balance_rom = 4'b1100;                                           // D15  -> 11101, ones=4, tok=1
    // Control Codes (ctrl_i=1): 7 standard + 9 reserved - sym | ones | tok
    5'h10   : balance_rom = 4'b1101;                                           // IDLE -> 11111, ones=5, tok=1
    5'h11   : balance_rom = 4'b1010;                                           // J    -> 11000, ones=2, tok=1
    5'h12   : balance_rom = 4'b1010;                                           // K    -> 10001, ones=2, tok=1
    5'h13   : balance_rom = 4'b1011;                                           // T    -> 01101, ones=3, tok=1
    5'h14   : balance_rom = 4'b1011;                                           // R    -> 00111, ones=3, tok=1
    5'h15   : balance_rom = 4'b0001;                                           // H    -> 00100, ones=1, tok=0
    5'h16   : balance_rom = 4'b0000;                                           // Q    -> 00000, ones=0, tok=0
    // RSVD: all map to sym=00000, ones=0, tok=0
    5'h17   : balance_rom = 4'b0000;                                           // RSVD -> 00000
    5'h18   : balance_rom = 4'b0000;                                           // RSVD -> 00000
    5'h19   : balance_rom = 4'b0000;                                           // RSVD -> 00000
    5'h1a   : balance_rom = 4'b0000;                                           // RSVD -> 00000
    5'h1b   : balance_rom = 4'b0000;                                           // RSVD -> 00000
    5'h1c   : balance_rom = 4'b0000;                                           // RSVD -> 00000
    5'h1d   : balance_rom = 4'b0000;                                           // RSVD -> 00000
    5'h1e   : balance_rom = 4'b0000;                                           // RSVD -> 00000
    5'h1f   : balance_rom = 4'b0000;                                           // RSVD -> 00000
    default : balance_rom = 4'b0000;                                           // Never reached (full 5-bit case)
  endcase

end

// ---------------------------------------------------------------------------------------------------------------------
// Pipeline Stage
//   PIPELINE == 1 : one register stage after balance ROM
//   PIPELINE == 0 : combinational pass-through
//   other       : not supported - drive X to catch any upstream dependency
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (PIPELINE == 1)
  begin : GEN_STAGE1_REG_BRANCH
    reg            [3:0]                         reg_bal;                  // Registered balance info
    reg                                          reg_valid;                // Registered valid

    always @(posedge clk or negedge rst_n)
    begin : BAL_REG_PROC
      if (rst_n == 1'b0)
      begin
        reg_bal         <= 4'b0000;
      end
      else
      begin
        reg_bal         <= balance_rom;
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

    assign bal_o        = reg_bal;
    assign valid_o      = reg_valid;
  end
  else if (PIPELINE == 0)
  begin : GEN_STAGE0_BYPASS_BRANCH
    assign bal_o        = balance_rom;
    assign valid_o      = valid_i;
  end
  else
  begin : GEN_UNSUPPORTED_BRANCH
    assign bal_o        = {4{1'bx}};
    assign valid_o      = 1'bx;
  end
endgenerate

endmodule
`endif
// =====================================================================================================================
// Modified history
// =====================================================================================================================
//
