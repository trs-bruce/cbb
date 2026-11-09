// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026-07-17
// Description  : Parameterized Dynamic Priority Arbiter
//                Supports up to 32 masters with dynamic priority, lock, mask and park functions
// =====================================================================================================================

`ifndef CBB_ARB_DP_V
`define CBB_ARB_DP_V
module CBB_ARB_DP
   #(
    parameter NUM_MASTERS                         = 4,                          // Number of request clients (2~32)
    parameter BW                                  = (NUM_MASTERS <= 2)  ? 1 :
                                                   (NUM_MASTERS <= 4)  ? 2 :
                                                   (NUM_MASTERS <= 8)  ? 3 :
                                                   (NUM_MASTERS <= 16) ? 4 : 5,     // Priority bit width per client
    parameter PARK_MODE                           = 1,                          // 1=enable park, 0=disable park
    parameter PARK_INDEX                          = 0,                          // Park target client index
    parameter OUTPUT_MODE                         = 1                           // 1=registered output, 0=combinational output
    )
    (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset, active low
   input           [NUM_MASTERS-1:0]             req,                          // Request vector
   input           [NUM_MASTERS*BW-1:0]          prior,                        // Dynamic priority vector
   input           [NUM_MASTERS-1:0]             lock,                         // Lock request vector
   input           [NUM_MASTERS-1:0]             mask,                         // Mask vector
   output          [NUM_MASTERS-1:0]             gnt,                          // Grant output (one-hot)
   output                                        parked,                       // Park status flag
   output                                        granted,                      // Grant valid flag
   output                                        locked                        // Lock status flag
    );

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
wire               [NUM_MASTERS-1:0]             valid_req;                         // Request after mask filtering
wire               [NUM_MASTERS-1:0]             next_gnt;                          // Combinational next grant
wire                                             next_granted;                      // Combinational next granted flag
wire                                             next_parked;                       // Combinational next parked flag
wire                                             next_locked;                       // Combinational next locked flag
wire               [BW-1:0]                      next_gnt_idx;                      // Index of next granted client

wire                                             lock_hold;                         // Current lock is held
wire                                             has_req;                           // Has valid request after mask
wire               [NUM_MASTERS-1:0]             one_hot_best;                      // One-hot vector for best client
wire               [NUM_MASTERS-1:0]             one_hot_park;                      // One-hot vector for park client


reg                [NUM_MASTERS-1:0]             curr_gnt;                          // Current grant register
reg                                              curr_granted;                      // Current granted flag register
reg                                              curr_parked;                       // Current parked flag register
reg                                              curr_locked;                       // Current locked flag register
reg                [BW-1:0]                      curr_gnt_idx;                      // Index of current granted client

reg                                              best_valid;                        // Valid best candidate found flag
reg                [BW-1:0]                      best_idx;                          // Index of highest priority client
reg                [BW-1:0]                      best_prior;                        // Priority value of highest priority client
reg                [BW-1:0]                      client_prior;                      // Priority of current client in traversal

// ---------------------------------------------------------------------------------------------------------------------
// Request Filter with Mask
// ---------------------------------------------------------------------------------------------------------------------
assign valid_req        = req & ~mask;

// ---------------------------------------------------------------------------------------------------------------------
// Best Client Selection : Linear Traversal Minimum Selection
// ---------------------------------------------------------------------------------------------------------------------
integer                                          arb_idx;               // Loop index for arbitration traversal
always @(*)
begin : BEST_PROC
  best_valid            = 1'b0;
  best_idx              = {BW{1'b0}};
  best_prior            = {BW{1'b1}};

  for (arb_idx = 0; arb_idx < NUM_MASTERS; arb_idx = arb_idx + 1)
  begin : BEST_LOOP
    if (valid_req[arb_idx] == 1'b1)
    begin
      client_prior      = prior[arb_idx*BW +: BW];
      if ((best_valid == 1'b0) || (client_prior < best_prior))
      begin
        best_prior      = client_prior;
        best_idx        = arb_idx[BW-1:0];
        best_valid      = 1'b1;
      end
    end
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Arbitration Decision : Lock -> Mask -> Normal Arbitration -> Park
// ---------------------------------------------------------------------------------------------------------------------
assign lock_hold        = curr_locked & lock[curr_gnt_idx];
assign has_req          = |valid_req;

assign one_hot_best     = {{NUM_MASTERS-1{1'b0}}, 1'b1} << best_idx;
assign one_hot_park     = {{NUM_MASTERS-1{1'b0}}, 1'b1} << PARK_INDEX;

assign next_gnt_idx     = lock_hold ? curr_gnt_idx :
                          (has_req  ? best_idx      : PARK_INDEX[BW-1:0]);

assign next_gnt         = lock_hold ? curr_gnt :
                          (has_req  ? one_hot_best  :
                          (PARK_MODE == 1'b1 ? one_hot_park : {NUM_MASTERS{1'b0}}));

assign next_locked      = lock_hold ? 1'b1 :
                          (has_req  ? lock[best_idx] : 1'b0);

assign next_granted     = lock_hold ? curr_granted : has_req;
assign next_parked      = (~lock_hold) & (~has_req) & (PARK_MODE == 1'b1);

// ---------------------------------------------------------------------------------------------------------------------
// Current State Registers
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : STATE_SEQ_PROC
  if (rst_n == 1'b0)
  begin
    curr_gnt            <= {NUM_MASTERS{1'b0}};
    curr_granted        <= 1'b0;
    curr_parked         <= 1'b0;
    curr_locked         <= 1'b0;
    curr_gnt_idx        <= {BW{1'b0}};
  end
  else
  begin
    curr_gnt            <= next_gnt;
    curr_granted        <= next_granted;
    curr_parked         <= next_parked;
    curr_locked         <= next_locked;
    curr_gnt_idx        <= next_gnt_idx;
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Stage : Registered or Combinational
// ---------------------------------------------------------------------------------------------------------------------
assign gnt              = (OUTPUT_MODE == 1'b1) ? curr_gnt     : next_gnt;
assign granted          = (OUTPUT_MODE == 1'b1) ? curr_granted : next_granted;
assign parked           = (OUTPUT_MODE == 1'b1) ? curr_parked  : next_parked;
assign locked           = (OUTPUT_MODE == 1'b1) ? curr_locked  : next_locked;

endmodule
`endif
// =====================================================================================================================