// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CODING
// Create Date  : 2026/09/03
// Description  : 4b/5b Encoder (IEEE 802.3 / FDDI Standard)
//                Encodes 4-bit data + 1-bit control identifier into 5-bit line symbols.
//                Pure combinational LUT ROM with optional output register stage.
//                Architecture: 32x5 LUT ROM (combinational) addressed by {ctrl_i, data_i[3:0]},
//                configurable pipeline: 0 (combinational pass-through), 1 register stage.
//                Code Table (IEEE 802.3 Clause 24 / FDDI PMD):
//                  - 16 Data codes   : ctrl_i=0, data_i[3:0] -> 5-bit symbol
//                  -  7 Control codes: ctrl_i=1, data_i[3:0]=0~6 -> control symbols
//                  -  9 Reserved     : ctrl_i=1, data_i[3:0]=7~15 -> RSVD=00000
// =====================================================================================================================
`ifndef CBB_4B5B_ENC_V
`define CBB_4B5B_ENC_V
module CBB_4B5B_ENC
  #(
   parameter PIPELINE                            = 1                           // 0: comb, 1: 1-stage reg (2: NOT supported)
   )
   (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset (active low)
   input           [3:0]                         data_i,                       // 4-bit raw data (ctrl_i=0) / ctrl type select (ctrl_i=1)
   input                                         ctrl_i,                       // Control code flag: 1=control, 0=data
   input                                         valid_i,                      // Input valid indicator
   output          [4:0]                         sym_o,                        // 5-bit encoded output symbol
   output                                        valid_o                       // Output valid (valid_i delayed by PIPELINE cycles)
   );

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
wire               [4:0]                         lut_addr;                     // LUT address {ctrl_i, data_i}
reg                [4:0]                         lut_rom;                      // 32x5 LUT ROM output

// ---------------------------------------------------------------------------------------------------------------------
// LUT Address
// ---------------------------------------------------------------------------------------------------------------------
assign lut_addr         = {ctrl_i, data_i};

// ---------------------------------------------------------------------------------------------------------------------
// LUT ROM - 32 entries x 5 bits, combinational
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : LUT_ROM_PROC
  case (lut_addr)
    // Data Codes (ctrl_i=0): 16 entries
    5'h00   : lut_rom = 5'b11110;                                              // D0   -> 11110
    5'h01   : lut_rom = 5'b01001;                                              // D1   -> 01001
    5'h02   : lut_rom = 5'b10100;                                              // D2   -> 10100
    5'h03   : lut_rom = 5'b10101;                                              // D3   -> 10101
    5'h04   : lut_rom = 5'b01010;                                              // D4   -> 01010
    5'h05   : lut_rom = 5'b01011;                                              // D5   -> 01011
    5'h06   : lut_rom = 5'b01110;                                              // D6   -> 01110
    5'h07   : lut_rom = 5'b01111;                                              // D7   -> 01111
    5'h08   : lut_rom = 5'b10010;                                              // D8   -> 10010
    5'h09   : lut_rom = 5'b10011;                                              // D9   -> 10011
    5'h0a   : lut_rom = 5'b10110;                                              // D10  -> 10110
    5'h0b   : lut_rom = 5'b10111;                                              // D11  -> 10111
    5'h0c   : lut_rom = 5'b11010;                                              // D12  -> 11010
    5'h0d   : lut_rom = 5'b11011;                                              // D13  -> 11011
    5'h0e   : lut_rom = 5'b11100;                                              // D14  -> 11100
    5'h0f   : lut_rom = 5'b11101;                                              // D15  -> 11101
    // Control Codes (ctrl_i=1): 7 standard + 9 reserved
    5'h10   : lut_rom = 5'b11111;                                              // IDLE -> 11111
    5'h11   : lut_rom = 5'b11000;                                              // J    -> 11000 (SSD1)
    5'h12   : lut_rom = 5'b10001;                                              // K    -> 10001 (SSD2)
    5'h13   : lut_rom = 5'b01101;                                              // T    -> 01101 (ESD1)
    5'h14   : lut_rom = 5'b00111;                                              // R    -> 00111 (ESD2)
    5'h15   : lut_rom = 5'b00100;                                              // H    -> 00100 (HALT)
    5'h16   : lut_rom = 5'b00000;                                              // Q    -> 00000 (QUIET)
    5'h17   : lut_rom = 5'b00000;                                              // RSVD -> 00000
    5'h18   : lut_rom = 5'b00000;                                              // RSVD -> 00000
    5'h19   : lut_rom = 5'b00000;                                              // RSVD -> 00000
    5'h1a   : lut_rom = 5'b00000;                                              // RSVD -> 00000
    5'h1b   : lut_rom = 5'b00000;                                              // RSVD -> 00000
    5'h1c   : lut_rom = 5'b00000;                                              // RSVD -> 00000
    5'h1d   : lut_rom = 5'b00000;                                              // RSVD -> 00000
    5'h1e   : lut_rom = 5'b00000;                                              // RSVD -> 00000
    5'h1f   : lut_rom = 5'b00000;                                              // RSVD -> 00000
    default : lut_rom = 5'b00000;                                              // Never reached (full 5-bit case)
  endcase

end

// ---------------------------------------------------------------------------------------------------------------------
// Pipeline Stage
//   PIPELINE == 1 : one register stage after LUT ROM
//   PIPELINE == 0 : combinational pass-through
//   other       : not supported - drive X to catch any upstream dependency
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (PIPELINE == 1)
  begin : GEN_STAGE1_REG_BRANCH
    reg            [4:0]                         reg_sym;                  // Registered symbol
    reg                                          reg_valid;                // Registered valid

    always @(posedge clk or negedge rst_n)
    begin : SYM_REG_PROC
      if (rst_n == 1'b0)
      begin
        reg_sym         <= 5'b00000;
      end
      else
      begin
        reg_sym         <= lut_rom;
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

    assign sym_o        = reg_sym;
    assign valid_o      = reg_valid;
  end
  else if (PIPELINE == 0)
  begin : GEN_STAGE0_BYPASS_BRANCH
    assign sym_o        = lut_rom;
    assign valid_o      = valid_i;
  end
  else
  begin : GEN_UNSUPPORTED_BRANCH
    assign sym_o        = {5{1'bx}};
    assign valid_o      = 1'bx;
  end
endgenerate

endmodule
`endif
// =====================================================================================================================
// Modified history
// =====================================================================================================================
//
