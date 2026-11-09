// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026/07/20
// Description  : Two-Tier Arbiter
// =====================================================================================================================

`ifndef CBB_ARB_2T_V
`define CBB_ARB_2T_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
//                Tier 1: fixed priority, linear greedy scan (smaller prior value wins)
//                Tier 2: round-robin among masters with equal tier-1 priority
//                Control: Mask / Lock / Park, priority Lock > Mask > Normal > Park
//                Output : registered (OUTPUT_MODE=1) or combinational (OUTPUT_MODE=0)
// ---------------------------------------------------------------------------------------------------------------------
module CBB_ARB_2T
   #(
    parameter NUM_MASTERS                         = 4,                          // Master number (2~32)
    parameter P_WIDTH                             = 2,                          // Priority width per master (1~5)
    parameter PARK_MODE                           = 1,                          // Park mode: 1=enable, 0=disable
    parameter PARK_INDEX                          = 0,                          // Park target master index (0~NUM_MASTERS-1)
    parameter OUTPUT_MODE                         = 1                           // Output mode: 1=registered, 0=combinational
    )
    (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset (active low)
   input           [NUM_MASTERS-1:0]             req,                          // Master request vector
   input           [NUM_MASTERS*P_WIDTH-1:0]     prior,                        // Priority bus, client[NUM_MASTERS-1]...client[0]
   input           [NUM_MASTERS-1:0]             lock,                         // Lock vector, tie to 0 when unused
   input           [NUM_MASTERS-1:0]             mask,                         // Mask vector, tie to 0 when unused
   output          [NUM_MASTERS-1:0]             gnt,                          // Grant one-hot vector
   output                                        parked,                       // Parked flag
   output                                        granted,                      // Granted flag
   output                                        locked                        // Locked flag
    );

// ---------------------------------------------------------------------------------------------------------------------
// Constant Parameter
// ---------------------------------------------------------------------------------------------------------------------
localparam RR_PTR_WIDTH                          = (NUM_MASTERS <= 2)  ? 1 :   // RR pointer width
                                                   (NUM_MASTERS <= 4)  ? 2 :
                                                   (NUM_MASTERS <= 8)  ? 3 :
                                                   (NUM_MASTERS <= 16) ? 4 : 5;
localparam MAX_PTR                               = NUM_MASTERS - 1;                 // Max pointer value
localparam RST_PARKED                            = (PARK_MODE == 1) ? 1'b1 : 1'b0;  // Reset value of parked flag
// Park one-hot grant
localparam         [NUM_MASTERS-1:0]             PARK_ONEHOT    = {{(NUM_MASTERS-1){1'b0}}, 1'b1} << PARK_INDEX;
// Grant value after reset
localparam         [NUM_MASTERS-1:0]             RST_GNT   = (PARK_MODE == 1) ? PARK_ONEHOT : {NUM_MASTERS{1'b0}};

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
wire               [NUM_MASTERS-1:0]             eff_req;                      // Effective request (req & ~mask)
wire                                             eff_req_vld;                  // Any effective request exists
wire               [P_WIDTH-1:0]                 prio_arr [0:NUM_MASTERS-1];   // Priority of each master
reg                [P_WIDTH-1:0]                 best_prio;                    // Best (minimum) priority among requests
wire               [NUM_MASTERS-1:0]             best_match;                   // Requesting masters with best priority
wire               [NUM_MASTERS-1:0]             ptr_mask;                     // Bit mask of index >= rr_ptr
wire               [NUM_MASTERS-1:0]             cand_high;                    // Candidates in [rr_ptr, NUM_MASTERS-1]
wire               [NUM_MASTERS-1:0]             rr_sel;                       // RR search vector
wire               [NUM_MASTERS-1:0]             winner_onehot;                // Tier-2 winner one-hot
reg                [NUM_MASTERS-1:0]             gnt_arb;                      // Combinational arbitration grant
reg                [NUM_MASTERS-1:0]             gnt_q;                        // Registered grant
reg                                              granted_q;                    // Registered granted flag
wire                                             lock_hold;                    // Lock active on granted master
reg                [RR_PTR_WIDTH-1:0]            gnt_idx;                      // Binary index of gnt_q
wire                                             winner_drop;                  // Granted master dropped its request
wire                                             granted_c;                    // Combinational granted flag
wire                                             parked_c;                     // Combinational parked flag
wire                                             locked_c;                     // Combinational locked flag
wire               [NUM_MASTERS-1:0]             gnt_comb;                     // Final combinational grant
reg                [RR_PTR_WIDTH-1:0]            rr_ptr;                       // Round-robin pointer
reg                [RR_PTR_WIDTH-1:0]            rr_ptr_next;                  // Round-robin pointer next value
reg                                              parked_q;                     // Registered parked flag
reg                                              locked_q;                     // Registered locked flag
integer                                          bi;                           // Best-priority scan loop variable
integer                                          ei;                           // Grant index encode loop variable

// ---------------------------------------------------------------------------------------------------------------------
// Effective Request: mask filtering before arbitration
// ---------------------------------------------------------------------------------------------------------------------
assign eff_req          = req & ~mask;
assign eff_req_vld      = |eff_req;

// ---------------------------------------------------------------------------------------------------------------------
// Priority Unpack: slice prior bus into per-master priority
// ---------------------------------------------------------------------------------------------------------------------
genvar gi;
generate
  for (gi = 0; gi < NUM_MASTERS; gi = gi + 1)
  begin : PRIO_UNPACK_LOOP
    assign prio_arr[gi] = prior[gi*P_WIDTH +: P_WIDTH];
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Tier-1: linear greedy scan for the best (minimum) priority
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : BEST_PRIO_PROC
  best_prio             = {P_WIDTH{1'b1}};
  for (bi = 0; bi < NUM_MASTERS; bi = bi + 1)
  begin : BEST_PRIO_SCAN_LOOP
    if (eff_req[bi] == 1'b1 && prio_arr[bi] < best_prio)
      best_prio         = prio_arr[bi];
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Best-priority match: masters joining tier-2 round-robin
// ---------------------------------------------------------------------------------------------------------------------
generate
  for (gi = 0; gi < NUM_MASTERS; gi = gi + 1)
  begin : BEST_MATCH_LOOP
    assign best_match[gi]    = eff_req[gi] & (prio_arr[gi] == best_prio);
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Tier-2: round-robin search from rr_ptr, two-segment priority encoding
//         search [rr_ptr, NUM_MASTERS-1] first, then [0, rr_ptr-1]
// ---------------------------------------------------------------------------------------------------------------------
assign ptr_mask         = {NUM_MASTERS{1'b1}} << rr_ptr;
assign cand_high        = best_match & ptr_mask;
assign rr_sel           = ((|cand_high) == 1'b1) ? cand_high : best_match;

generate
  for (gi = 0; gi < NUM_MASTERS; gi = gi + 1)
  begin : WINNER_ONEHOT_LOOP
    if (gi == 0)
    begin : LSB_BRANCH
      assign winner_onehot[gi]    = rr_sel[gi];
    end
    else
    begin : OTHER_BRANCH
      assign winner_onehot[gi]    = rr_sel[gi] & ~(|rr_sel[gi-1:0]);
    end
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Grant selection: normal arbitration or park
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : GNT_ARB_PROC
  if (eff_req_vld == 1'b1)
    gnt_arb             = winner_onehot;
  else if (PARK_MODE == 1)
    gnt_arb             = PARK_ONEHOT;
  else
    gnt_arb             = {NUM_MASTERS{1'b0}};
end

// ---------------------------------------------------------------------------------------------------------------------
// Lock hold and combinational status flags
// ---------------------------------------------------------------------------------------------------------------------
assign lock_hold        = |(lock & gnt_q);
assign gnt_comb         = (lock_hold == 1'b1) ? gnt_q : gnt_arb;
assign granted_c        = lock_hold | eff_req_vld;
assign parked_c         = (lock_hold == 1'b0) & (eff_req_vld == 1'b0) & (PARK_MODE == 1);
assign locked_c         = lock_hold;

// ---------------------------------------------------------------------------------------------------------------------
// Grant index encode and winner-drop detection
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : GNT_IDX_PROC
  gnt_idx               = {RR_PTR_WIDTH{1'b0}};
  for (ei = 0; ei < NUM_MASTERS; ei = ei + 1)
  begin : GNT_INDEX_LOOP
    if (gnt_q[ei] == 1'b1)
      gnt_idx           = ei[RR_PTR_WIDTH-1:0];
  end
end

assign winner_drop      = granted_q & (req[gnt_idx] == 1'b0);

// ---------------------------------------------------------------------------------------------------------------------
// RR pointer update:
//   Lock                -> freeze
//   No effective request-> auto-increment
//   Winner drops request-> advance to winner + 1
//   Winner keeps request-> hold
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : RR_PTR_NEXT_PROC
  rr_ptr_next           = rr_ptr;
  if (lock_hold == 1'b1)
    rr_ptr_next         = rr_ptr;
  else if (eff_req_vld == 1'b0)
  begin
    if (rr_ptr == MAX_PTR[RR_PTR_WIDTH-1:0])
      rr_ptr_next       = {RR_PTR_WIDTH{1'b0}};
    else
      rr_ptr_next       = rr_ptr + 1'b1;
  end
  else if (winner_drop == 1'b1)
  begin
    if (gnt_idx == MAX_PTR[RR_PTR_WIDTH-1:0])
      rr_ptr_next       = {RR_PTR_WIDTH{1'b0}};
    else
      rr_ptr_next       = gnt_idx + 1'b1;
  end
end

always @(posedge clk or negedge rst_n)
begin : RR_PTR_REG_PROC
  if (rst_n == 1'b0)
    rr_ptr              <= {RR_PTR_WIDTH{1'b0}};
  else
    rr_ptr              <= rr_ptr_next;
end

// ---------------------------------------------------------------------------------------------------------------------
// Grant and granted-flag registers: hold while locked
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : GNT_REG_PROC
  if (rst_n == 1'b0)
    gnt_q               <= RST_GNT;
  else if (lock_hold == 1'b0)
    gnt_q               <= gnt_arb;
end

always @(posedge clk or negedge rst_n)
begin : GRANTED_REG_PROC
  if (rst_n == 1'b0)
    granted_q           <= 1'b0;
  else
    granted_q           <= granted_c;
end

always @(posedge clk or negedge rst_n)
begin : PARKED_REG_PROC
  if (rst_n == 1'b0)
    parked_q            <= RST_PARKED;
  else
    parked_q            <= parked_c;
end

always @(posedge clk or negedge rst_n)
begin : LOCKED_REG_PROC
  if (rst_n == 1'b0)
    locked_q            <= 1'b0;
  else
    locked_q            <= locked_c;
end

// ---------------------------------------------------------------------------------------------------------------------
// Output stage: OUTPUT_MODE=1 registered, OUTPUT_MODE=0 combinational
// ---------------------------------------------------------------------------------------------------------------------
assign gnt              = (OUTPUT_MODE == 1) ? gnt_q     : gnt_comb;
assign granted          = (OUTPUT_MODE == 1) ? granted_q : granted_c;
assign parked           = (OUTPUT_MODE == 1) ? parked_q  : parked_c;
assign locked           = (OUTPUT_MODE == 1) ? locked_q  : locked_c;

endmodule
`endif
// =====================================================================================================================