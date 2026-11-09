// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026-09-01
// Description  : Parameterized dual-mode ring counter. Onehot mode recirculates
//                the least-significant bit and Johnson mode recirculates its
//                complement. The state is directly registered at q.
// =====================================================================================================================

`ifndef CBB_CNT_RING_V
`define CBB_CNT_RING_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
// Module       : CBB_CNT_RING
// Assumptions  : WIDTH is at least 2. rst_n is asynchronously asserted low and
//                should be synchronously released by the clock/reset owner.
//                mode is configured while rst_n is low and remains stable while
//                rst_n is high.
// ---------------------------------------------------------------------------------------------------------------------
module CBB_CNT_RING
  #(
   parameter WIDTH                               = 8
   )
   (
   input wire                                    clk,                          // State clock
   input wire                                    rst_n,                        // Async active-low reset
   input wire                                    mode,                         // 0: Onehot, 1: Johnson
   output reg      [WIDTH-1:0]                   q                             // Registered state
   );

// ---------------------------------------------------------------------------------------------------------------------
// Internal signals
// ---------------------------------------------------------------------------------------------------------------------
localparam         [WIDTH-1:0]                   RESET_VAL = {{(WIDTH-1){1'b0}}, 1'b1};

wire                                             feedback;
wire               [WIDTH-1:0]                   q_next;

// ---------------------------------------------------------------------------------------------------------------------
// Feedback selection and direct ring shift
// ---------------------------------------------------------------------------------------------------------------------
assign feedback         = (mode == 1'b0) ? q[0] : ~q[0];
assign q_next           = {feedback, q[WIDTH-1:1]};

// ---------------------------------------------------------------------------------------------------------------------
// State register
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : Q_REG_PROC
  if (rst_n == 1'b0)
  begin
    q                                                <= RESET_VAL;
  end
  else
  begin
    q                                                <= q_next;
  end
end

endmodule
`endif

// =====================================================================================================================