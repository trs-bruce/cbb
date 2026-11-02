// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CODING
// Create Date  : 2026/09/27
// Description  : SEC-DED ECC Decoder (Hamming Code)
// =====================================================================================================================
// Single-bit error correction + Double-bit error detection.
// Data width parameterizable (8–256), optional error-position output.
// Pure combinational implementation (no clock / reset / pipeline stages).
//
// Codeword format (GLOBAL_PARITY fixed = 1):
//   {data_i[DATA_WIDTH-1:0], p_global, p[k-1:0]}
//   - p[j] at codeword position 2^j
//   - data bits fill remaining positions (non-powers-of-2)
// =====================================================================================================================

//  $unit-scope constant functions (visible to port declarations)
// ---------------------------------------------------------------------------------------------------------------------
function automatic integer cbb_clog2(input integer n);
  integer v;
  v = n - 1;
  for (cbb_clog2 = 0; v > 0; cbb_clog2 = cbb_clog2 + 1) v = v >> 1;
endfunction

function automatic integer cbb_calc_hamming_cbits(input integer dw);
  integer kk;
  for (kk = 1; kk <= 15; kk = kk + 1) begin : CBITS_LOOP
    if ((1 << kk) >= dw + kk + 1) return kk;
  end
  return 16;
endfunction


`ifndef CBB_ECC_DEC_V
`define CBB_ECC_DEC_V
module CBB_ECC_DEC #(
   parameter int DATA_WIDTH                      = 64,                         // data bit-width (8 ~ 256)
   parameter int ERR_POS_OUT                     = 0                           // 1 = output error bit position
  ) (
   input wire      [DATA_WIDTH-1:0]                             data_i,
   input wire      [cbb_calc_hamming_cbits(DATA_WIDTH)+1-1:0]   ecc_i,
   input wire                                                   valid_i,

   output wire     [DATA_WIDTH-1:0]                                            data_o,
   output wire     [cbb_calc_hamming_cbits(DATA_WIDTH)-1:0]                    syndrome_o,
   output wire     [1:0]                                                       flag_o,
   output wire     [((ERR_POS_OUT != 0) ? cbb_clog2(DATA_WIDTH) : 1) - 1:0]    err_pos_o,
   output wire                                                                 valid_o
  );

// =====================================================================================================================
// 1. Local Parameter Derivation
// =====================================================================================================================

localparam int HAMMING_CBITS                     = cbb_calc_hamming_cbits(DATA_WIDTH);
localparam int ECC_WIDTH                         = HAMMING_CBITS + 1;                    // GLOBAL_PARITY fixed = 1

// err_pos_o width: cbb_clog2(DATA_WIDTH) when enabled, else 1 (avoids zero-width)
localparam int ERR_POS_WIDTH                     = (ERR_POS_OUT != 0) ? cbb_clog2(DATA_WIDTH) : 1;

// total codeword length = DATA_WIDTH data bits + HAMMING_CBITS parity bits
localparam int CW_TOTAL                          = DATA_WIDTH + HAMMING_CBITS;

wire               [HAMMING_CBITS-1:0]           syndrome_full_comb;
// ---- Global even-parity check (GLOBAL_PARITY = 1) ----
wire                                             global_parity_err_comb;
wire                                             parity_recalc;
// ---- Error classification (combinational) ----
logic              [1:0]                         flag_comb;
wire                                             is_single_err_comb;
wire                                             syndrome_nonzero;
// ---- Error correction & position (combinational) ----
wire               [DATA_WIDTH-1:0]              data_corrected_comb;
wire               [DATA_WIDTH-1:0]              bit_error_vec;  // one-hot error flag per data bit
logic              [ERR_POS_WIDTH-1:0]           err_pos_comb;
genvar gi;


// =====================================================================================================================
// 2. Constant Functions (module scope)
// =====================================================================================================================

// codeword_pos: map 0-indexed data-bit index → 1-indexed codeword position
// Parity bits occupy power-of-2 positions; data bits fill the rest.
function automatic integer codeword_pos(input integer data_idx);
  integer cw_p, data_cnt;
  integer found;
  data_cnt = 0;
  found    = -1;
  for (cw_p = 1; cw_p <= CW_TOTAL; cw_p = cw_p + 1) begin : CODEWORD_SLOT_LOOP
    if ((cw_p & (cw_p - 1)) != 0) begin              // NOT a power of 2 → data slot
      if (data_cnt == data_idx) begin
        found = cw_p;
        cw_p  = CW_TOTAL;                        // early exit
      end
      data_cnt = data_cnt + 1;
    end
  end
  return found;                                        // -1 only if data_idx out of range (defensive)
endfunction

// calc_partial_syn: XOR of data bits[i] in range [lo:hi] whose
// codeword position has bit cb_idx set.
function automatic logic calc_partial_syn(
  input logic     [DATA_WIDTH-1:0]              data,
  input int                                     cb_idx,
  input int                                     lo,
  input int                                     hi
  );
  automatic logic r = 1'b0;
  for (int i = lo; i <= hi; i = i + 1) begin : XOR_ACCUM_LOOP
    if (((codeword_pos(i) >> cb_idx) & 1'b1) != 0)
      r = r ^ data[i];
  end
  return r;
endfunction

// calc_syndrome_bit: full XOR over all data bits for one check-bit index
function automatic logic calc_syndrome_bit(
  input logic     [DATA_WIDTH-1:0]              data,
  input int                                     cb_idx
  );
  return calc_partial_syn(data, cb_idx, 0, DATA_WIDTH - 1);
endfunction

// =====================================================================================================================
// 3. Combinational Logic — Syndrome, Parity, Classify, Correct
// =====================================================================================================================

// ---- 3a. Hamming syndrome (full, combinational) ----
genvar gs;
generate
  for (gs = 0; gs < HAMMING_CBITS; gs = gs + 1) begin : GEN_SYNDROME_LOOP
    assign syndrome_full_comb[gs] = ecc_i[gs] ^ calc_syndrome_bit(data_i, gs);
  end
endgenerate

assign parity_recalc              = (^data_i) ^ (^ecc_i[HAMMING_CBITS-1:0]);
assign global_parity_err_comb     = parity_recalc ^ ecc_i[ECC_WIDTH-1];

assign syndrome_nonzero           = |syndrome_full_comb;

always_comb begin
  // SEC-DED mode — see UG §3.1.2 truth table
  if (syndrome_nonzero == 1'b0 && global_parity_err_comb == 1'b0)
    flag_comb = 2'b00;                                  // no error
  else if (syndrome_nonzero == 1'b0 && global_parity_err_comb)
    flag_comb = 2'b01;                                  // global parity bit itself flipped
  else if (syndrome_nonzero && global_parity_err_comb == 1'b0)
    flag_comb = 2'b10;                                  // double error, detected
  else
    flag_comb = 2'b01;                                  // single error, corrected
end

assign is_single_err_comb         = (flag_comb == 2'b01);


generate
  for (gi = 0; gi < DATA_WIDTH; gi = gi + 1) begin : GEN_CORRECT_LOOP
    localparam int CW_POS                         = codeword_pos(gi);
    wire                                         this_bit_err;
    assign this_bit_err                = (syndrome_full_comb == CW_POS) & is_single_err_comb;
    assign bit_error_vec[gi]           = this_bit_err;
    assign data_corrected_comb[gi]     = data_i[gi] ^ this_bit_err;
  end
endgenerate

// error position encoder: one-hot → binary
always_comb begin
  err_pos_comb = '0;
  for (int i = 0; i < DATA_WIDTH; i = i + 1) begin : ERR_POS_LOOP
    if (bit_error_vec[i] == 1'b1) err_pos_comb = i[ERR_POS_WIDTH-1:0];
  end
end

// =====================================================================================================================
// 4. Output (pure combinational passthrough)
// =====================================================================================================================

assign data_o                          = data_corrected_comb;
assign syndrome_o                      = syndrome_full_comb;
assign flag_o                          = flag_comb;
assign err_pos_o                       = err_pos_comb;
assign valid_o                         = valid_i;

endmodule
`endif

// =====================================================================================================================
// Modified history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-09-27 | CBB Team       | Initial version
// =====================================================================================================================
