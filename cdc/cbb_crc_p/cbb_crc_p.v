// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CRC_P
// Create Date  : 2026-07-22
// Description  : Universal Parallel Combinational CRC Generator/Checker (Pure Combinational)
//                Features: parameterized polynomial (2~64bit), data width (1~2560bit),
//                configurable CRC init value & output inversion, 4 bit/byte ordering modes,
//                dual-path independent intermediate remainder comparison for error checking.
//                crc_ok = (A XOR B == 0), where A is forward CRC remainder from data_in,
//                B is reverse-compensated remainder from crc_in — NOT direct crc_out vs crc_in compare.
// =====================================================================================================================

`ifndef CBB_CRC_P_V
`define CBB_CRC_P_V
module CBB_CRC_P
   #(
    parameter                                     DATA_WIDTH     = 16,          // Input data bit width (1 ~ 2560)
    parameter                                     POLY_SIZE      = 16,          // CRC polynomial bit width (2 ~ 64)
    parameter                                     CRC_CFG        = 7,           // CRC config mode (0 ~ 7)
    parameter                                     BIT_ORDER      = 3,           // Bit/byte ordering mode (0 ~ 3)
    parameter       [15:0]                        POLY_COEF0     = 16'd4129,    // Polynomial coeff bits 0~15  (must be odd)
    parameter       [15:0]                        POLY_COEF1     = 16'd0,       // Polynomial coeff bits 16~31
    parameter       [15:0]                        POLY_COEF2     = 16'd0,       // Polynomial coeff bits 32~47
    parameter       [15:0]                        POLY_COEF3     = 16'd0        // Polynomial coeff bits 48~63
    )
    (
   input           [DATA_WIDTH-1:0]              data_in,                      // Input data for CRC computation
   input           [POLY_SIZE-1:0]               crc_in,                       // Input CRC for verification
   output                                        crc_ok,                       // CRC check result (A XOR B == 0)
   output          [POLY_SIZE-1:0]               crc_out                       // Generated CRC output
    );

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals
// ---------------------------------------------------------------------------------------------------------------------
wire               [63:0]                        poly_full;                    // Full 64-bit polynomial from 4 coeff segments
wire               [POLY_SIZE-1:0]               polynomial;                   // Truncated polynomial vector
wire               [POLY_SIZE-1:0]               init_val;                     // CRC initial value (all-0 or all-1)
wire               [DATA_WIDTH-1:0]              data_reordered;               // Bit-reordered data_in
wire               [POLY_SIZE-1:0]               crc_reordered;                // Bit-reordered crc_in
wire               [POLY_SIZE-1:0]               remainder_a;                  // Data path: forward CRC intermediate remainder A
wire               [POLY_SIZE-1:0]               crc_inv_cancelled;            // crc_in after inversion cancel
wire               [POLY_SIZE-1:0]               remainder_b;                  // crc_in path: reverse-compensated remainder B
wire               [POLY_SIZE-1:0]               inv_output_mask;              // Output bit inversion mask (from CRC_CFG)
wire               [POLY_SIZE-1:0]               xor_result;                   // A XOR B comparison vector

// ---------------------------------------------------------------------------------------------------------------------
// Polynomial Vector & Initial Value
// ---------------------------------------------------------------------------------------------------------------------
assign poly_full        = {POLY_COEF3, POLY_COEF2, POLY_COEF1, POLY_COEF0};
assign polynomial       = poly_full[POLY_SIZE-1:0];
assign init_val         = (CRC_CFG[0] == 1'b1) ? {POLY_SIZE{1'b1}} : {POLY_SIZE{1'b0}};

// ---------------------------------------------------------------------------------------------------------------------
// Bit Reorder (Data Path & crc_in Path)
// ---------------------------------------------------------------------------------------------------------------------
assign data_reordered   = bit_reorder_data(data_in);
assign crc_reordered    = bit_reorder_crc(crc_in);

// ---------------------------------------------------------------------------------------------------------------------
// Data Path: Forward CRC Matrix → Intermediate Remainder A
//   A = crc_forward(reordered_data, init_val, polynomial)
//   This is the raw remainder BEFORE any output bit inversion.
// ---------------------------------------------------------------------------------------------------------------------
assign remainder_a      = crc_forward(data_reordered, init_val, polynomial);

// ---------------------------------------------------------------------------------------------------------------------
// crc_in Path: Inversion Cancel + Reverse Matrix → Intermediate Remainder B
//   Step 1: Undo sender's output bit inversion (XOR is self-inverse over GF(2))
//   Step 2: Reverse matrix restores B (identity for dual-path comparison architecture)
//
//   Sender chain  : data → A → invert(A) → crc_out (transmitted)
//   Receiver chain: crc_in (= invert(A)) → undo invert → A → B (= A)
//   Then          : A XOR B = 0 → crc_ok = 1 (no error)
// ---------------------------------------------------------------------------------------------------------------------
assign crc_inv_cancelled     = crc_reordered ^ inv_output_mask;
assign remainder_b           = crc_inv_cancelled;

// ---------------------------------------------------------------------------------------------------------------------
// Output Bit Inversion Mask (from CRC_CFG)
//   CRC_CFG=0/1 : none       → mask = 0
//   CRC_CFG=2/3 : even bits  → mask[j] = ~j[0]
//   CRC_CFG=4/5 : odd bits   → mask[j] =  j[0]
//   CRC_CFG=6/7 : full       → mask = 1
// ---------------------------------------------------------------------------------------------------------------------
genvar gi;
generate
  for (gi = 0; gi < POLY_SIZE; gi = gi + 1)
  begin : INV_MASK_GEN_LOOP
    if (CRC_CFG == 0 || CRC_CFG == 1)
      assign inv_output_mask[gi]  = 1'b0;
    else if (CRC_CFG == 2 || CRC_CFG == 3)
      assign inv_output_mask[gi]  = ~gi[0];
    else if (CRC_CFG == 4 || CRC_CFG == 5)
      assign inv_output_mask[gi]  = gi[0];
    else
      assign inv_output_mask[gi]  = 1'b1;
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// CRC Output: Apply inversion to intermediate remainder A
// ---------------------------------------------------------------------------------------------------------------------
assign crc_out          = remainder_a ^ inv_output_mask;

// ---------------------------------------------------------------------------------------------------------------------
// CRC Check: Compare intermediate remainders A and B
// ---------------------------------------------------------------------------------------------------------------------
assign xor_result       = remainder_a ^ remainder_b;
assign crc_ok           = (xor_result == {POLY_SIZE{1'b0}}) ? 1'b1 : 1'b0;

// ---------------------------------------------------------------------------------------------------------------------
// Function: bit_reorder_data
// Reorder data_in bits according to BIT_ORDER:
//   0 = MSB first / MSB byte   → identity
//   1 = LSB first / LSB byte   → full bit reversal
//   2 = MSB first / LSB byte   → byte reversal (requires DATA_WIDTH multiple of 8)
//   3 = LSB first / MSB byte   → bit reversal within each byte
// ---------------------------------------------------------------------------------------------------------------------
function [DATA_WIDTH-1:0] bit_reorder_data;
  input           [DATA_WIDTH-1:0]              din;
  integer                i;
  integer                byte_idx;
  integer                bit_in_byte;
  begin
    case (BIT_ORDER)
      0: bit_reorder_data = din;
      1: for (i = 0; i < DATA_WIDTH; i = i + 1)
      bit_reorder_data[i] = din[DATA_WIDTH-1-i];
      2: for (i = 0; i < DATA_WIDTH; i = i + 1)
      begin
        byte_idx              = i / 8;
        bit_in_byte           = i % 8;
        bit_reorder_data[i]   = din[(DATA_WIDTH/8-1-byte_idx)*8 + bit_in_byte];
      end
      3: for (i = 0; i < DATA_WIDTH; i = i + 1)
      begin
        byte_idx              = i / 8;
        bit_in_byte           = i % 8;
        bit_reorder_data[i]   = din[byte_idx*8 + (7-bit_in_byte)];
      end
      default: bit_reorder_data  = din;
    endcase
  end
endfunction

// ---------------------------------------------------------------------------------------------------------------------
// Function: bit_reorder_crc
// Same reorder logic as bit_reorder_data, applied to crc_in (POLY_SIZE width).
// ---------------------------------------------------------------------------------------------------------------------
function [POLY_SIZE-1:0] bit_reorder_crc;
  input           [POLY_SIZE-1:0]               cin;
  integer               i;
  integer               byte_idx;
  integer               bit_in_byte;
  begin
    case (BIT_ORDER)
      0: bit_reorder_crc = cin;
      1: for (i = 0; i < POLY_SIZE; i = i + 1)
      bit_reorder_crc[i] = cin[POLY_SIZE-1-i];
      2: for (i = 0; i < POLY_SIZE; i = i + 1)
      begin
        byte_idx              = i / 8;
        bit_in_byte           = i % 8;
        bit_reorder_crc[i]    = cin[(POLY_SIZE/8-1-byte_idx)*8 + bit_in_byte];
      end
      3: for (i = 0; i < POLY_SIZE; i = i + 1)
      begin
        byte_idx              = i / 8;
        bit_in_byte           = i % 8;
        bit_reorder_crc[i]    = cin[byte_idx*8 + (7-bit_in_byte)];
      end
      default: bit_reorder_crc   = cin;
    endcase
  end
endfunction

// ---------------------------------------------------------------------------------------------------------------------
// Function: crc_forward
// Parallel CRC computation via unrolled LFSR (MSB-first, after bit reorder).
// Synthesis tool unrolls the loop into a pure combinational XOR tree.
//
// Per-bit LFSR update:
//   feedback = state[POLY_SIZE-1] ^ data_bit
//   state    = {state[POLY_SIZE-2:0], 1'b0} ^ (feedback ? polynomial : 0)
// ---------------------------------------------------------------------------------------------------------------------
function [POLY_SIZE-1:0] crc_forward;
  input           [DATA_WIDTH-1:0]              data;
  input           [POLY_SIZE-1:0]               init;
  input           [POLY_SIZE-1:0]               poly;
  integer                k;
  reg                                            feedback;
  reg              [POLY_SIZE-1:0]               state;
  begin
    state           = init;
    for (k = 0; k < DATA_WIDTH; k = k + 1)
    begin
      feedback      = state[POLY_SIZE-1] ^ data[DATA_WIDTH-1-k];
      state         = {state[POLY_SIZE-2:0], 1'b0};
      if (feedback == 1'b1)
        state       = state ^ poly;
      else
        state       = state;
    end
    crc_forward     = state;
  end
endfunction

endmodule
`endif
// =====================================================================================================================
// Modified history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-07-22 | CBB Team     | Initial version
// =====================================================================================================================
