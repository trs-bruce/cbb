// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CODING
// Create Date  : 2026/09/27
// Description  : Parameterized SEC-DED ECC Encoder (Hamming + global parity)
// =====================================================================================================================
// Language : Verilog (IEEE 1364-2001)
// Function : Generate Hamming + global parity ECC check bits for
//            memory write-path protection.
//
// Architecture:
//   - Passthrough data path: data_o = data_i (combinational, no pipeline)
//   - Hamming check bits computed via compile-time-unrolled XOR trees
//   - Global parity bit fixed on (GLOBAL_PARITY = 1) for SEC-DED
//   - Pure combinational — no clock / reset / registers
//
// Parameters:
//   DATA_WIDTH    : Data bus width (8 ~ 256, default 64)
//
// Derived (localparam):
//   HAMMING_CBITS : k where 2^k >= DATA_WIDTH + k + 1
//   ECC_WIDTH     : HAMMING_CBITS + 1 (global parity)
// =====================================================================================================================

`ifndef CBB_ECC_ENC_V
`define CBB_ECC_ENC_V
module CBB_ECC_ENC #(
   parameter DATA_WIDTH                          = 64,                         // data bus width (8 ~ 256)

   // Auto-derived parameters —— 必须定义在端口列表之前：
   // ecc_o 的位宽引用 ECC_WIDTH，而 Verilog-2001 端口宽度表达式只能引用参数区常量。
   parameter HAMMING_CBITS                       =
                                                   (DATA_WIDTH <= 4)   ? 3  :
                                                   (DATA_WIDTH <= 11)  ? 4  :
                                                   (DATA_WIDTH <= 26)  ? 5  :
                                                   (DATA_WIDTH <= 57)  ? 6  :
                                                   (DATA_WIDTH <= 120) ? 7  :
                                                   (DATA_WIDTH <= 247) ? 8  : 9,
   parameter ECC_WIDTH                           = HAMMING_CBITS + 1
  ) (
   input           [DATA_WIDTH-1:0]              data_i,
   input                                         valid_i,
   output          [DATA_WIDTH-1:0]              data_o,
   output          [ECC_WIDTH-1:0]               ecc_o,
   output          [1:0]                         flag_o,
   output                                        valid_o
  );

// =====================================================================================================================
// Data passes through unchanged
wire               [DATA_WIDTH-1:0]              data_comb;
wire               [HAMMING_CBITS-1:0]           ecc_hamming_full;
genvar j;
wire                                             ecc_global_full;
wire               [ECC_WIDTH-1:0]               ecc_comb;
assign data_comb        = data_i;

// =====================================================================================================================
// Helper functions for Hamming code position mapping and XOR computation.
// Evaluated at compile time — produce pure XOR trees after synthesis.
// =====================================================================================================================

function is_power_of_two;
  input           [31:0]                        n;
  begin
    is_power_of_two = (n > 0) && ((n & (n - 32'd1)) == 0);
  end
endfunction

function [31:0] get_codeword_pos;
  input           [31:0]                        d_idx;
  input           [31:0]                        data_w;
  input           [31:0]                        hcb;
  integer      pos;
  reg              [31:0]                        d_cnt;
  integer      total;
  begin
    total  = data_w + hcb;
    d_cnt  = 32'hFFFFFFFF;
    get_codeword_pos = 32'hFFFFFFFF;
    for (pos = 1; pos <= total; pos = pos + 1) begin : CODEWORD_POS_LOOP
      if (is_power_of_two(pos) == 1'b0) begin
        d_cnt = d_cnt + 1;
        if (d_cnt == d_idx) begin
          get_codeword_pos = pos;
          pos = total + 1;
        end
      end
    end
  end
endfunction

// Compute XOR for check bit j over data range [lo, hi)
function compute_checkbit_range;
  input           [DATA_WIDTH-1:0]              data_in;
  input           [31:0]                        cb_idx;
  input           [31:0]                        lo;
  input           [31:0]                        hi;
  integer d;
  reg                                            result;
  reg              [31:0]                        cw_pos;
  begin
    result = 1'b0;
    for (d = lo; d < hi; d = d + 1) begin : CODEWORD_XOR_LOOP
      cw_pos = get_codeword_pos(d, DATA_WIDTH, HAMMING_CBITS);
      if (((cw_pos >> cb_idx) & 1'b1) == 1'b1)
        result = result ^ data_in[d];
    end
    compute_checkbit_range = result;
  end
endfunction

// =====================================================================================================================
// Full-tree Hamming check bit generation
// =====================================================================================================================

generate
  for (j = 0; j < HAMMING_CBITS; j = j + 1) begin : GEN_HAMMING_FULL_LOOP
    assign ecc_hamming_full[j]    = compute_checkbit_range(data_i, j, 32'd0, DATA_WIDTH);
  end
endgenerate

// =====================================================================================================================
// Global parity (fixed on)
// =====================================================================================================================
assign ecc_global_full            = (^data_i) ^ (^ecc_hamming_full);

// =====================================================================================================================
// Assembled ECC output
// =====================================================================================================================
assign ecc_comb                   = {ecc_global_full, ecc_hamming_full};

// =====================================================================================================================
// Combinational output passthrough
// =====================================================================================================================
assign data_o                     = data_comb;
assign ecc_o                      = ecc_comb;
assign valid_o                    = valid_i;
assign flag_o                     = {1'b0, valid_o};

endmodule
`endif

// =====================================================================================================================
// Modified history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-09-27 | CBB Team       | Initial version
// =====================================================================================================================
