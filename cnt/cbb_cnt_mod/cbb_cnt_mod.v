// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Module       : CBB_CNT_MOD
// Create Date  : 2026-09-01
// Description  : Parameterized synchronous modulo counter with static and
//                runtime-configurable modulus selection. The counter advances
//                from zero through N-1 and wraps to zero at the threshold.
// Assumptions  : WIDTH is at least 2. MOD_VAL=0 selects the runtime mod_val
//                input; otherwise MOD_VAL is a legal positive modulus.
//                Runtime mod_val must be non-zero and meet clk-domain timing.
// =====================================================================================================================

`ifndef CBB_CNT_MOD_V
`define CBB_CNT_MOD_V
module CBB_CNT_MOD
  #(
   parameter WIDTH                               = 8,
   parameter MOD_VAL                             = 0
   )
   (
   input wire                                    clk,                          // Counter clock
   input wire                                    rst_n,                        // Sync active-low reset
   input wire      [WIDTH-1:0]                   mod_val,                      // Runtime modulus
   output reg      [WIDTH-1:0]                   q                             // Current count
   );

// ---------------------------------------------------------------------------------------------------------------------
// Internal signals
// ---------------------------------------------------------------------------------------------------------------------
localparam         [WIDTH-1:0]                   ZERO_VAL       = {WIDTH{1'b0}};
localparam         [WIDTH-1:0]                   STATIC_MOD     = MOD_VAL;

wire               [WIDTH-1:0]                   effective_mod;
wire               [WIDTH-1:0]                   threshold;
wire                                             at_top;
wire               [WIDTH-1:0]                   incremented_q;
wire               [WIDTH-1:0]                   q_next;

// ---------------------------------------------------------------------------------------------------------------------
// Modulus selection, threshold compare, and wrap mux
// ---------------------------------------------------------------------------------------------------------------------
assign effective_mod                                  = (MOD_VAL == 0) ?
                                                        mod_val : STATIC_MOD;
assign threshold                                      = (effective_mod == ZERO_VAL) ?
                                                        ZERO_VAL : (effective_mod - 1'b1);
assign at_top                                         = (q >= threshold);
assign incremented_q                                  = q + {{(WIDTH-1){1'b0}}, 1'b1};
assign q_next                                         = (at_top == 1'b1) ? ZERO_VAL : incremented_q;

// ---------------------------------------------------------------------------------------------------------------------
// Synchronous state update
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk)
begin : Q_REG_PROC
  if (rst_n == 1'b0)
  begin
    q                                                <= ZERO_VAL;
  end
  else
  begin
    q                                                <= q_next;
  end
end

endmodule
`endif

// =====================================================================================================================
// Modification history:
// 2026-09-01 CBB Team Initial version.
// =====================================================================================================================
