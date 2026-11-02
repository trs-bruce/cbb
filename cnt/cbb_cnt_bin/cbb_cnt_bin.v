// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Module       : CBB_CNT_BIN
// Create Date  : 2026-08-31
// Description  : Parameterized synchronous bidirectional binary counter using
//                an explicit ripple-carry adder/subtractor structure.
// Assumptions  : rst_n is synchronous active-low. WIDTH is at least 2.
//                OVERFLOW_WRAP=1 wraps at the boundaries; OVERFLOW_WRAP=0
//                saturates at the selected boundary.
// =====================================================================================================================

`ifndef CBB_CNT_BIN_V
`define CBB_CNT_BIN_V
module CBB_CNT_BIN
  #(
   parameter WIDTH                               = 8,
   parameter OVERFLOW_WRAP                       = 1
   )
   (
   input wire                                    clk,                          // Counter clock
   input wire                                    rst_n,                        // Sync reset, active low
   input wire                                    en,                           // Count enable
   input wire                                    dir,                          // 0: up, 1: down
   input wire                                    load,                         // Load enable
   input wire      [WIDTH-1:0]                   init_val,                     // Load value
   input wire                                    sync_clr,                     // Synchronous clear
   output reg      [WIDTH-1:0]                   q,                            // Current count
   output wire                                   cout                          // Boundary indicator
   );

// ---------------------------------------------------------------------------------------------------------------------
// Internal signals
// ---------------------------------------------------------------------------------------------------------------------
localparam         [WIDTH-1:0]                   MAX_VAL   = {WIDTH{1'b1}};
localparam         [WIDTH-1:0]                   ZERO_VAL  = {WIDTH{1'b0}};

wire               [WIDTH:0]                     rca_chain;
wire               [WIDTH-1:0]                   rca_val;
wire                                             at_max;
wire                                             at_min;

// ---------------------------------------------------------------------------------------------------------------------
// Ripple-carry increment/decrement datapath
// ---------------------------------------------------------------------------------------------------------------------
assign rca_chain[0]     = 1'b1;
assign at_max           = (q == MAX_VAL);
assign at_min           = (q == ZERO_VAL);

genvar bit_idx;
generate
  for (bit_idx = 0; bit_idx < WIDTH; bit_idx = bit_idx + 1)
  begin : RCA_BIT_LOOP
    assign rca_val[bit_idx]       = q[bit_idx] ^ rca_chain[bit_idx];
    assign rca_chain[bit_idx+1]   = (dir == 1'b0) ?
                                    (q[bit_idx] & rca_chain[bit_idx]) :
                                    ((~q[bit_idx]) & rca_chain[bit_idx]);
  end
endgenerate

// cout indicates an enabled attempt to step beyond the current boundary.
assign cout             = (rst_n == 1'b1) &&
                          (en == 1'b1) &&
                          (((dir == 1'b0) && (at_max == 1'b1)) ||
                          ((dir == 1'b1) && (at_min == 1'b1)));

// ---------------------------------------------------------------------------------------------------------------------
// Counter state update and control priority
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk)
begin : Q_REG_PROC
  if (rst_n == 1'b0)
  begin
    q                                               <= ZERO_VAL;
  end
  else
  if (load == 1'b1)
  begin
    q                                               <= init_val;
  end
  else
  if (sync_clr == 1'b1)
  begin
    q                                               <= ZERO_VAL;
  end
  else
  if (en == 1'b1)
  begin
    if (dir == 1'b0)
    begin
      if (at_max == 1'b1)
      begin
        if (OVERFLOW_WRAP == 1'b1)
        begin
          q                                           <= ZERO_VAL;
        end
        else
        begin
          q                                           <= MAX_VAL;
        end
      end
      else
      begin
        q                                             <= rca_val;
      end
    end
    else
    begin
      if (at_min == 1'b1)
      begin
        if (OVERFLOW_WRAP == 1'b1)
        begin
          q                                           <= MAX_VAL;
        end
        else
        begin
          q                                           <= ZERO_VAL;
        end
      end
      else
      begin
        q                                             <= rca_val;
      end
    end
  end
end

endmodule
`endif

// =====================================================================================================================
// Modification history:
// 2026-08-31 CBB Team Initial version.
// =====================================================================================================================
