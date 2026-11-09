// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026/07/17
// Description  : Fixed Priority Arbiter with Lock/Park/Mask support
// =====================================================================================================================

`ifndef CBB_ARB_FP_V
`define CBB_ARB_FP_V
module CBB_ARB_FP
    #(
    parameter NUM_MASTERS                         = 4,                          // Number of arbiter clients (2~32)
    parameter PARK_MODE                           = 1,                          // Park enable: 1=enable, 0=disable
    parameter PARK_INDEX                          = 0,                          // Park client index (0~NUM_MASTERS-1)
    parameter OUTPUT_MODE                         = 1                           // Output mode: 1=registered, 0=combinational
    )
    (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset, active low
   input           [NUM_MASTERS-1:0]             req,                          // Client request input
   input           [NUM_MASTERS-1:0]             lock,                         // Lock control input
   input           [NUM_MASTERS-1:0]             mask,                         // Mask control input
   output          [NUM_MASTERS-1:0]             gnt,                          // One-hot grant output
   output                                        parked,                       // Park status flag
   output                                        granted,                      // Grant status flag
   output                                        locked                        // Lock status flag
    );

// ---------------------------------------------------------------------------------------------------------------------
// Internal signals
// ---------------------------------------------------------------------------------------------------------------------
wire               [NUM_MASTERS-1:0]             eff_req;                      // Effective request after mask
wire               [NUM_MASTERS-1:0]             gnt_raw;                      // Raw priority encoder output
wire               [NUM_MASTERS-1:0]             park_gnt;                     // Park grant one-hot vector
wire               [NUM_MASTERS-1:0]             arb_gnt;                      // Arbitration result
wire               [NUM_MASTERS-1:0]             next_gnt;                     // Next grant value
reg                [NUM_MASTERS-1:0]             gnt_state;                    // Registered grant state
wire                                             any_eff_req;                  // Any effective request
wire                                             lock_hold;                    // Current lock held
wire                                             new_lock;                     // New lock request
wire                                             next_locked;                  // Next lock state
reg                                              locked_state;                 // Registered lock state
wire                                             next_parked;                  // Next parked flag
reg                                              parked_state;                 // Registered parked flag
wire                                             next_granted;                 // Next granted flag
reg                                              granted_state;                // Registered granted flag

// ---------------------------------------------------------------------------------------------------------------------
// Mask processing
// ---------------------------------------------------------------------------------------------------------------------
assign eff_req          = req & (~mask);

// ---------------------------------------------------------------------------------------------------------------------
// Priority encoder: req[0] has highest priority
// ---------------------------------------------------------------------------------------------------------------------
genvar i;
generate
  for (i = 0; i < NUM_MASTERS; i = i + 1)
  begin : PRIORITY_ENC_LOOP
    if (i == 0)
      assign gnt_raw[i] = eff_req[i];
    else
      assign gnt_raw[i] = eff_req[i] & (~(|eff_req[i-1:0]));
  end
endgenerate

assign any_eff_req      = |eff_req;

// ---------------------------------------------------------------------------------------------------------------------
// Park grant generation
// ---------------------------------------------------------------------------------------------------------------------
assign park_gnt         = {{(NUM_MASTERS-1){1'b0}}, 1'b1} << PARK_INDEX;

// ---------------------------------------------------------------------------------------------------------------------
// Arbitration engine
// ---------------------------------------------------------------------------------------------------------------------
assign arb_gnt          = (any_eff_req == 1'b1) ? gnt_raw :
                          (PARK_MODE   == 1'b1) ? park_gnt :
                          {NUM_MASTERS{1'b0}};

// ---------------------------------------------------------------------------------------------------------------------
// Lock control
// ---------------------------------------------------------------------------------------------------------------------
assign lock_hold        = (locked_state == 1'b1) ? (|(lock & gnt_state)) : 1'b0;
assign new_lock         = (locked_state == 1'b0) ? (|(arb_gnt & lock))   : 1'b0;
assign next_locked      = lock_hold | new_lock;

assign next_gnt         = (lock_hold == 1'b1) ? gnt_state : arb_gnt;

// ---------------------------------------------------------------------------------------------------------------------
// Status flag generation
// ---------------------------------------------------------------------------------------------------------------------
assign next_parked      = (PARK_MODE == 1'b1) & (any_eff_req == 1'b0) & (next_locked == 1'b0);
assign next_granted     = (|next_gnt) & (~next_parked);

// ---------------------------------------------------------------------------------------------------------------------
// State registers
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : STATE_REG_PROC
  if (rst_n == 1'b0)
  begin
    gnt_state           <= {NUM_MASTERS{1'b0}};
    locked_state        <= 1'b0;
    parked_state        <= 1'b0;
    granted_state       <= 1'b0;
  end
  else
  begin
    gnt_state           <= next_gnt;
    locked_state        <= next_locked;
    parked_state        <= next_parked;
    granted_state       <= next_granted;
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Output mode selection
// ---------------------------------------------------------------------------------------------------------------------
assign gnt              = (OUTPUT_MODE == 1'b1) ? gnt_state     : next_gnt;
assign parked           = (OUTPUT_MODE == 1'b1) ? parked_state  : next_parked;
assign granted          = (OUTPUT_MODE == 1'b1) ? granted_state : next_granted;
assign locked           = (OUTPUT_MODE == 1'b1) ? locked_state  : next_locked;

endmodule
`endif
// =====================================================================================================================