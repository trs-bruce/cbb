// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026-09-02
// Description  : Parameterized asynchronous ripple up-counter. The least
//                significant T flip-flop is clocked by clk; each higher stage
//                toggles on the falling edge of the preceding stage output.
// =====================================================================================================================

`ifndef CBB_CNT_RIPPLE_V
`define CBB_CNT_RIPPLE_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
// Module       : CBB_CNT_RIPPLE
// Assumptions  : WIDTH is at least 2. q is an asynchronous multi-bit ripple
//                bus and must only be sampled after the worst-case ripple time.
// ---------------------------------------------------------------------------------------------------------------------
module CBB_CNT_RIPPLE
  #(
   parameter WIDTH                               = 8
   )
   (
   input wire                                    clk,                          // External count clock
   input wire                                    rst_n,                        // Async active-low reset
   output wire     [WIDTH-1:0]                   q                             // Ripple count bus
   );

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
reg                [WIDTH-1:0]                   q_int;

assign q                = q_int;

// ---------------------------------------------------------------------------------------------------------------------
// Least-significant ripple stage
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : RIPPLE_LSB_PROC
  if (rst_n == 1'b0)
  begin
    q_int[0]                                         <= 1'b0;
  end
  else
  begin
    q_int[0]                                         <= ~q_int[0];
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Higher ripple stages. Each stage is an independent T flip-flop whose local
// clock is the falling edge of the preceding ripple output.
// ---------------------------------------------------------------------------------------------------------------------
genvar bit_idx;
generate
  for (bit_idx = 1; bit_idx < WIDTH; bit_idx = bit_idx + 1)
  begin : RIPPLE_STAGE_LOOP
    wire                                         stage_clk;
    assign stage_clk    = q_int[bit_idx-1];
    always @(negedge stage_clk or negedge rst_n)
    begin : RIPPLE_STAGE_PROC
      if (rst_n == 1'b0)
      begin
        q_int[bit_idx]                                  <= 1'b0;
      end
      else
      begin
        q_int[bit_idx]                                  <= ~q_int[bit_idx];
      end
    end
  end
endgenerate

endmodule
`endif

// =====================================================================================================================