// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CNT_GRAY
// Create Date  : 2026/07/20
// Description  : N-bit Parameterized Gray Code Counter for CDC applications.
//                Registered binary core + combinational gray conversion on adder output.
//                - Adjacent count values flip exactly 1 bit (Hamming distance = 1)
//                - Suitable for async FIFO pointers and CDC synchronization
//                - Gray conversion input = adder output (next_val), not bin_cnt register
//                - Both bin_cnt and gray_reg registered on same edge (zero cycle skew)
// =====================================================================================================================

`ifndef CBB_CNT_GRAY_V
`define CBB_CNT_GRAY_V
module CBB_CNT_GRAY
   #(
   parameter WIDTH                               = 8                           // Bit width (>=2)
    )
    (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset, low
   input                                         en,                           // Count enable
   output          [WIDTH-1:0]                   q_bin,                        // Binary output
   output          [WIDTH-1:0]                   q_gray                        // Gray output
    );

// ---------------------------------------------------------------------------------------------------------------------
// Constant Parameter
// ---------------------------------------------------------------------------------------------------------------------
localparam         [WIDTH-1:0]                   CNT_MAX   = {WIDTH{1'b1}};    // Max value (all 1s)
localparam         [WIDTH-1:0]                   CNT_MIN   = {WIDTH{1'b0}};    // Min value (all 0s)

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
reg                [WIDTH-1:0]                   bin_cnt;                      // Binary counter reg
reg                [WIDTH-1:0]                   gray_reg;                     // Gray counter reg
wire                                             at_max;                       // At max flag
wire               [WIDTH-1:0]                   next_val;                     // Next value (comb)
wire               [WIDTH-1:0]                   gray_next;                    // Gray of adder out

// ---------------------------------------------------------------------------------------------------------------------
// Boundary Detection (combination)
//   at_max : bin_cnt reached all-1s -> next cycle wraps to 0
// ---------------------------------------------------------------------------------------------------------------------
assign at_max           = (bin_cnt == CNT_MAX) ? 1'b1 : 1'b0;

// ---------------------------------------------------------------------------------------------------------------------
// Next Value Logic (RCA-based +1, wrap to 0 on overflow)
//   At MAX: wrap to 0; otherwise: bin_cnt + 1
//   Synthesized as RCA by default; carry chain LSB -> MSB.
//   next_val is the adder output (combinational).
// ---------------------------------------------------------------------------------------------------------------------
assign next_val         = (at_max == 1'b1) ? CNT_MIN :
                          (bin_cnt + {{(WIDTH-1){1'b0}}, 1'b1});

// ---------------------------------------------------------------------------------------------------------------------
// Gray Code Conversion (combinational, on ADDER OUTPUT next_val)
//   gray[i] = bin[i] ^ bin[i+1], gray[MSB] = bin[MSB]
//   Per spec: conversion input must be adder output (next_val), not bin_cnt register.
//   This avoids 1-cycle latency between q_bin and q_gray.
//   gray_next is registered into gray_reg on the same clock edge as bin_cnt,
//   so q_bin and q_gray are perfectly aligned (zero cycle skew).
// ---------------------------------------------------------------------------------------------------------------------
assign gray_next        = next_val ^ (next_val >> 1);

// ---------------------------------------------------------------------------------------------------------------------
// Counter Registers (priority: rst_n > en > hold)
//   bin_cnt  <= next_val   (registered adder output)
//   gray_reg <= gray_next  (registered gray of adder output)
//   Both update on same clock edge -> q_bin and q_gray in sync.
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : CNT_SEQ_PROC
  if (rst_n == 1'b0)
  begin
    bin_cnt             <= {WIDTH{1'b0}};
    gray_reg            <= {WIDTH{1'b0}};
  end
  else if (en == 1'b1)
  begin
    bin_cnt             <= next_val;                                         // Update binary
    gray_reg            <= gray_next;                                        // Update gray
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Assign
//   q_bin : registered binary output
//   q_gray: registered gray output (aligned with q_bin, zero cycle skew)
// ---------------------------------------------------------------------------------------------------------------------
assign q_bin            = bin_cnt;
assign q_gray           = gray_reg;

endmodule
`endif
// =====================================================================================================================
// Modified history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-07-20 | CBB Team        | Initial version
// =====================================================================================================================
