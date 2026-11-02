// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB_CNT_FAST
// Create Date  : 2026/07/20
// Description  : N-bit Parameterized Prescaled High-Speed Binary Counter
//                Splits N-bit counter into:
//                - Low PRE_WIDTH prescaler (every cycle, short path)
//                - High (WIDTH-PRE_WIDTH) counter (every 2^PRE_WIDTH cyc, loose timing)
//                Both counters use explicit Ripple Carry Adder (carry chain
//                LSB->MSB) for increment. Features:
//                - Carry pulse output on full-wrap (every 2^WIDTH cycles)
//                - Critical path = max(PRE_WIDTH-bit RCA, high-counter MUX) << N-bit RCA
// =====================================================================================================================

`ifndef CBB_CNT_FAST_V
`define CBB_CNT_FAST_V
module CBB_CNT_FAST
   #(
   parameter WIDTH                               = 16,                         // Bit width (>=2)
    // Prescaler lower bit width (1<=PRE_WIDTH<WIDTH)
   parameter PRE_WIDTH                           = 4                           // Prescaler width
    )
    (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset, low
   input                                         en,                           // Count enable
   output          [WIDTH-1:0]                   q,                            // Counter output
   output                                        cout                          // Carry pulse
    );

// ---------------------------------------------------------------------------------------------------------------------
// Constant Parameter
// ---------------------------------------------------------------------------------------------------------------------
localparam                                       HIGH_WIDTH     = WIDTH - PRE_WIDTH;     // High bit width
localparam         [PRE_WIDTH-1:0]               PRE_MAX        = {PRE_WIDTH{1'b1}};     // Prescaler max
localparam         [HIGH_WIDTH-1:0]              HIGH_MAX       = {HIGH_WIDTH{1'b1}};    // High max
localparam         [WIDTH-1:0]                   CNT_MAX        = {WIDTH{1'b1}};         // Full max
localparam         [WIDTH-1:0]                   CNT_MIN        = {WIDTH{1'b0}};         // Full min

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
reg                [PRE_WIDTH-1:0]               pre_cnt;                                                  // Prescaler counter
reg                [HIGH_WIDTH-1:0]              high_cnt;                                                 // High counter
wire                                             pre_at_max;                                                // Prescaler at max
wire                                             pre_wrap;                                                  // Prescaler wrap
wire                                             high_at_max;                                               // High at max
wire                                             q_at_max;                                                  // Full at max

// ---------------------------------------------------------------------------------------------------------------------
// Prescaler Boundary Detection (combination)
//   pre_at_max = 1 when low PRE_WIDTH bits are all 1s
//   pre_wrap   = 1 when prescaler will wrap this cycle (at max AND counting)
// ---------------------------------------------------------------------------------------------------------------------
assign pre_at_max       = (pre_cnt == PRE_MAX) ? 1'b1 : 1'b0;
assign pre_wrap         = (en == 1'b1 && pre_at_max == 1'b1) ? 1'b1 : 1'b0;

// ---------------------------------------------------------------------------------------------------------------------
// High Counter Boundary Detection (combination)
// ---------------------------------------------------------------------------------------------------------------------
assign high_at_max      = (high_cnt == HIGH_MAX) ? 1'b1 : 1'b0;
assign q_at_max         = (pre_at_max == 1'b1 && high_at_max == 1'b1) ? 1'b1 : 1'b0;

// ---------------------------------------------------------------------------------------------------------------------
// Explicit RCA: Prescaler Increment (carry chain LSB->MSB)
//   carry[0]=1, sum[i]=q[i]^carry[i], carry[i+1]=q[i]&carry[i]
//   At MAX (all 1s): carry propagates through, sum=all 0s (natural wrap)
// ---------------------------------------------------------------------------------------------------------------------
wire               [PRE_WIDTH:0]                 pre_carry;                                                  // Carry chain
wire               [PRE_WIDTH-1:0]               pre_next;                                                   // RCA result

genvar k;
generate
  for (k = 0; k < PRE_WIDTH; k = k + 1) begin : PRE_RCA_GEN_LOOP
    assign pre_next[k]       = pre_cnt[k] ^ pre_carry[k];
    assign pre_carry[k+1]    = pre_cnt[k] & pre_carry[k];
  end
endgenerate
assign pre_carry[0]     = 1'b1;

// ---------------------------------------------------------------------------------------------------------------------
// Explicit RCA: High Counter Increment (carry chain LSB->MSB)
// ---------------------------------------------------------------------------------------------------------------------
wire               [HIGH_WIDTH:0]                high_carry;                                                 // Carry chain
wire               [HIGH_WIDTH-1:0]              high_next;                                                  // RCA result

generate
  for (k = 0; k < HIGH_WIDTH; k = k + 1) begin : HIGH_RCA_GEN_LOOP
    assign high_next[k]      = high_cnt[k] ^ high_carry[k];
    assign high_carry[k+1]   = high_cnt[k] & high_carry[k];
  end
endgenerate
assign high_carry[0]    = 1'b1;

// ---------------------------------------------------------------------------------------------------------------------
// Prescaler Counter Register (priority: rst_n > en > hold)
//   Updates every cycle when en=1; RCA naturally wraps at MAX -> 0
//   Critical path = PRE_WIDTH-bit RCA (short, supports high frequency)
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : PRE_SEQ_PROC
  if (rst_n == 1'b0)
  begin
    pre_cnt             <= {PRE_WIDTH{1'b0}};
  end
  else if (en == 1'b1)
  begin
    pre_cnt             <= pre_next;                                              // RCA increment
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// High Counter Register (priority: rst_n > pre_wrap > hold)
//   Updates only when pre_wrap=1 (every 2^PRE_WIDTH cycles)
//   RCA naturally wraps at HIGH_MAX -> 0
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : HIGH_SEQ_PROC
  if (rst_n == 1'b0)
  begin
    high_cnt            <= {HIGH_WIDTH{1'b0}};
  end
  else if (pre_wrap == 1'b1)
  begin
    high_cnt            <= high_next;                                             // RCA increment
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Assign
//   q    : concatenation of high counter and prescaler
//   cout : 1-cycle pulse when full counter is at max AND counting (about to wrap)
//          Fires once every 2^WIDTH cycles when en=1 continuously
// ---------------------------------------------------------------------------------------------------------------------
assign q                = {high_cnt, pre_cnt};
assign cout             = (en == 1'b1 && q_at_max == 1'b1) ? 1'b1 : 1'b0;

endmodule
`endif
// =====================================================================================================================
// Modified history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-07-20 | CBB Team        | Initial version
// =====================================================================================================================
