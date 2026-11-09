// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team Team
// Project      : cbb
// Create Date  : 2026-07-20
// Description  : Weighted Round-Robin (WRR) Arbiter with Lock and Park support
//                Each port owns a runtime weight (1~31) from the weight input and is
//                granted weight[i] times per scheduling round. Fixed polling order:
//                0 -> 1 -> ... -> N-1. The priority pointer stays on the served port
//                until its remaining-weight counter runs out, then moves forward.
//                When all requesting ports exhaust their remaining weight, the
//                round is done — all counters reload from the current weight input
//                and a new round starts without any idle cycle (work-conserving).
// =====================================================================================================================

`ifndef CBB_ARB_WRR_V
`define CBB_ARB_WRR_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
//                Parameters:
//                  NUM_MASTERS  : number of request masters (2~32)
//                  WEIGHT_WIDTH : weight counter width (fixed 5, weight range 1~31)
//                  OUTPUT_MODE  : 0=combinational output, 1=registered output
//                  PARK_MODE    : 0=disable park, 1=enable park
//                  PARK_INDEX   : default grant index when park enabled
//                Assumption:
//                  weight value 0 is an illegal input, behavior is undefined
// ---------------------------------------------------------------------------------------------------------------------
module CBB_ARB_WRR
   #(
    parameter NUM_MASTERS                         = 4,                          // Number of masters (2~32)
    parameter WEIGHT_WIDTH                        = 5,                          // Weight width (fixed 5, range 1~31)
    parameter OUTPUT_MODE                         = 1,                          // 0: combinational, 1: registered
    parameter PARK_MODE                           = 1,                          // 0: disable park, 1: enable park
    parameter PARK_INDEX                          = 0                           // Park target index (0~NUM_MASTERS-1)
    )
    (
   input                                              clk,                     // System clock
   input                                              rst_n,                   // Async reset (active low)
   input           [NUM_MASTERS-1:0]                  req,                     // Request from masters
   input           [NUM_MASTERS-1:0]                  mask,                    // Mask for masters
   input           [NUM_MASTERS-1:0]                  lock,                    // Lock from masters
   input           [NUM_MASTERS*WEIGHT_WIDTH-1:0]     weight,                  // Weight per master (1~31)
   output          [NUM_MASTERS-1:0]                  gnt,                     // One-hot grant
   output                                             granted,                 // Grant valid flag
   output                                             locked,                  // Lock state flag
   output                                             parked                   // Park state flag
    );

// ---------------------------------------------------------------------------------------------------------------------
// Constant Parameter
// ---------------------------------------------------------------------------------------------------------------------
localparam PTR_WIDTH                             = (NUM_MASTERS <= 2)  ? 1 :
                                                   (NUM_MASTERS <= 4)  ? 2 :
                                                   (NUM_MASTERS <= 8)  ? 3 :
                                                   (NUM_MASTERS <= 16) ? 4 : 5;

localparam STATE_NORMAL                          = 1'b0;                       // Normal arbitration state
localparam STATE_LOCKED                          = 1'b1;                       // Locked state

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
// Mask logic
wire               [NUM_MASTERS-1:0]             req_masked;                   // Request after mask

// Remaining-weight counters
reg                [NUM_MASTERS*WEIGHT_WIDTH-1:0]     cnt;                          // Remaining grant count per port
wire               [NUM_MASTERS*WEIGHT_WIDTH-1:0]     cnt_eff;                      // Effective cnt (weight on reload)
wire               [NUM_MASTERS-1:0]                  cnt_nz;                       // Per-port counter non-zero flag
wire                                                  round_done;                   // All requesting ports exhausted

// WRR eligibility and priority scan
wire               [NUM_MASTERS-1:0]             elig;                         // Eligible request (req & ~mask & cnt>0)
wire               [NUM_MASTERS-1:0]             unused_elig_rotate_hi;        // Discarded upper eligibility rotation bits
wire               [NUM_MASTERS-1:0]             unused_gnt_rotate_hi;         // Discarded upper grant rotation bits
wire               [NUM_MASTERS-1:0]             elig_shifted;                 // Rotated eligibility (bit 0 = priority_ptr)
reg                [NUM_MASTERS-1:0]             gnt_shifted;                  // Priority encoded grant (rotated)
wire               [NUM_MASTERS-1:0]             gnt_wrr;                      // WRR one-hot grant
wire                                             wrr_vld;                      // WRR grant valid

// Granted client
reg                [PTR_WIDTH-1:0]               granted_client_idx;           // Index of granted client
reg                [WEIGHT_WIDTH-1:0]            cnt_eff_g;                    // Effective cnt of granted client
wire                                             cnt_g_exhaust;                // Granted client cnt runs out

// Park logic
wire               [NUM_MASTERS-1:0]             gnt_park;                     // Park default grant
wire                                             no_valid_req;                 // No request after mask
wire                                             parked_normal;                // Park flag in normal state

// Lock FSM
reg                                              lock_state;                   // Current lock state
reg                [PTR_WIDTH-1:0]               locked_client;                // Currently locked client
reg                                              next_lock_state;              // Next lock state
reg                [PTR_WIDTH-1:0]               next_locked_client;           // Next locked client

// Priority pointer
reg                [PTR_WIDTH-1:0]               priority_ptr;                 // Current serving port
wire               [PTR_WIDTH-1:0]               next_priority_ptr;            // Next priority pointer
reg                [PTR_WIDTH-1:0]               ptr_inc_base;                 // Increment base port
reg                                              ptr_inc_en;                   // Increment enable (0: hold base)

// Raw outputs
wire               [NUM_MASTERS-1:0]             gnt_raw;                      // Combinational grant
wire                                             granted_raw;                  // Combinational granted flag
wire                                             locked_raw;                   // Combinational locked flag
wire                                             parked_raw;                   // Combinational parked flag

// Output registers
reg                [NUM_MASTERS-1:0]             gnt_reg;                      // Registered grant
reg                                              granted_reg;                  // Registered granted flag
reg                                              locked_reg;                   // Registered locked flag
reg                                              parked_reg;                   // Registered parked flag

// Helper flags and loop variables
reg                                              pe_found;                     // Priority encode found flag
integer                                          pe_idx;                       // WRR scan loop index
integer                                          gc_idx;                       // Grant client index loop index
integer                                          cg_idx;                       // Granted cnt mux loop index
integer                                          cu_idx;                       // Cnt update loop index

// ---------------------------------------------------------------------------------------------------------------------
// Mask Logic
// ---------------------------------------------------------------------------------------------------------------------
assign req_masked       = req & (~mask);

// ---------------------------------------------------------------------------------------------------------------------
// Round Completion Detection and Counter Effective Value
// ---------------------------------------------------------------------------------------------------------------------
// A scheduling round completes when no unmasked requesting port has remaining
// weight. Silent or masked ports do not block round progress (work-conserving).
// When the round is done, the effective counter value is taken from the weight
// input directly, so the first grant of a new round happens in the same cycle
// as the reload without any idle cycle.
assign round_done       = ~|(req_masked & cnt_nz);
assign cnt_eff          = (round_done == 1'b1) ? weight : cnt;

// ---------------------------------------------------------------------------------------------------------------------
// WRR Eligibility
// ---------------------------------------------------------------------------------------------------------------------
genvar                                           gi;
generate
  for (gi = 0; gi < NUM_MASTERS; gi = gi + 1)
  begin : ELIG_LOOP
    assign cnt_nz[gi]   = |cnt[gi*WEIGHT_WIDTH +: WEIGHT_WIDTH];
    assign elig[gi]     = req_masked[gi] & (|cnt_eff[gi*WEIGHT_WIDTH +: WEIGHT_WIDTH]);
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// WRR Priority Scan (Two-Level Priority Encode)
// ---------------------------------------------------------------------------------------------------------------------
// Bit 0 of elig_shifted corresponds to priority_ptr. The scan visits ports in
// fixed polling order: priority_ptr, priority_ptr+1, ..., N-1, 0, ..., priority_ptr-1.
assign {unused_elig_rotate_hi, elig_shifted}     = ({elig, elig} >> priority_ptr);

always @(*)
begin : WRR_SCAN_PROC
  gnt_shifted                = {NUM_MASTERS{1'b0}};
  pe_found                   = 1'b0;
  for (pe_idx = 0; pe_idx < NUM_MASTERS; pe_idx = pe_idx + 1)
  begin : WRR_SCAN_LOOP
    if ((pe_found == 1'b0) && (elig_shifted[pe_idx] == 1'b1))
    begin
      gnt_shifted[pe_idx]    = 1'b1;
      pe_found               = 1'b1;
    end
  end
end

assign {unused_gnt_rotate_hi, gnt_wrr} = ({gnt_shifted, gnt_shifted} >> (NUM_MASTERS - {{(32-PTR_WIDTH){1'b0}}, priority_ptr}));

assign wrr_vld          = |elig;

// ---------------------------------------------------------------------------------------------------------------------
// Granted Client Index and Counter Exhaustion
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : GRANTED_IDX_PROC
  granted_client_idx         = {PTR_WIDTH{1'b0}};
  for (gc_idx = 0; gc_idx < NUM_MASTERS; gc_idx = gc_idx + 1)
  begin : GNT_INDEX_LOOP
    if (gnt_wrr[gc_idx] == 1'b1)
      granted_client_idx     = gc_idx[PTR_WIDTH-1:0];
  end
end

always @(*)
begin : CNT_G_PROC
  cnt_eff_g                  = {WEIGHT_WIDTH{1'b0}};
  for (cg_idx = 0; cg_idx < NUM_MASTERS; cg_idx = cg_idx + 1)
  begin : GNT_COUNT_LOOP
    if (gnt_wrr[cg_idx] == 1'b1)
      cnt_eff_g              = cnt_eff[cg_idx*WEIGHT_WIDTH +: WEIGHT_WIDTH];
  end
end

assign cnt_g_exhaust    = (cnt_eff_g == {{(WEIGHT_WIDTH-1){1'b0}}, 1'b1});

// ---------------------------------------------------------------------------------------------------------------------
// Priority Pointer Wrap-Around Increment Function
// ---------------------------------------------------------------------------------------------------------------------
// Return (ptr + 1) % NUM_MASTERS
function [PTR_WIDTH-1:0] ptr_inc;
  input           [PTR_WIDTH-1:0]               ptr;
  reg              [PTR_WIDTH:0]                 ptr_plus1;
  reg              [PTR_WIDTH:0]                 tmp_diff;
  begin
    ptr_plus1             = {1'b0, ptr} + 1'b1;
    if (ptr_plus1 >= NUM_MASTERS[PTR_WIDTH:0])
    begin
      tmp_diff            = ptr_plus1 - NUM_MASTERS[PTR_WIDTH:0];
      ptr_inc             = tmp_diff[PTR_WIDTH-1:0];
    end
    else
      ptr_inc             = ptr_plus1[PTR_WIDTH-1:0];
  end
endfunction

// ---------------------------------------------------------------------------------------------------------------------
// Priority Pointer Next State
// ---------------------------------------------------------------------------------------------------------------------
// Select the increment base by scenario, ptr_inc_en controls +1 or hold:
//   Lock release           : base = locked_client,      increment
//   Grant & cnt exhausted  : base = granted_client_idx, increment (move to next port)
//   Grant & cnt remaining  : base = granted_client_idx, hold (consecutive grants)
//   No valid request       : base = priority_ptr,       increment (roll forward)
//   Locked                 : base = priority_ptr,       hold
always @(*)
begin : PTR_COMB_PROC
  ptr_inc_base          = priority_ptr;
  ptr_inc_en            = 1'b0;
  if ((lock_state == STATE_LOCKED) && (lock[locked_client] == 1'b0))
  begin
    ptr_inc_base        = locked_client;
    ptr_inc_en          = 1'b1;
  end
  else if (lock_state == STATE_NORMAL)
  begin
    if (wrr_vld == 1'b1)
    begin
      ptr_inc_base      = granted_client_idx;
      ptr_inc_en        = cnt_g_exhaust;
    end
    else
    begin
      ptr_inc_en        = 1'b1;
    end
  end
end

assign next_priority_ptr     = (ptr_inc_en == 1'b1) ? ptr_inc(ptr_inc_base) : ptr_inc_base;

always @(posedge clk or negedge rst_n)
begin : PTR_SEQ_PROC
  if (rst_n == 1'b0)
    priority_ptr        <= {PTR_WIDTH{1'b0}};
  else
    priority_ptr        <= next_priority_ptr;
end

// ---------------------------------------------------------------------------------------------------------------------
// Remaining-Weight Counter Update
// ---------------------------------------------------------------------------------------------------------------------
// On a valid grant the granted port counter decrements. When the round is done
// (round_done), cnt_eff carries the weight input, so every counter reloads from
// weight in the same cycle and the granted port stores weight-1.
always @(posedge clk or negedge rst_n)
begin : CNT_SEQ_PROC
  if (rst_n == 1'b0)
  begin
    cnt                 <= {(NUM_MASTERS*WEIGHT_WIDTH){1'b0}};
  end
  else if ((lock_state == STATE_NORMAL) && (wrr_vld == 1'b1))
  begin
    for (cu_idx = 0; cu_idx < NUM_MASTERS; cu_idx = cu_idx + 1)
    begin : COUNT_UPDATE_LOOP
      if (gnt_wrr[cu_idx] == 1'b1)
        cnt[cu_idx*WEIGHT_WIDTH +: WEIGHT_WIDTH] <= cnt_eff[cu_idx*WEIGHT_WIDTH +: WEIGHT_WIDTH] - 1'b1;
      else
        cnt[cu_idx*WEIGHT_WIDTH +: WEIGHT_WIDTH] <= cnt_eff[cu_idx*WEIGHT_WIDTH +: WEIGHT_WIDTH];
    end
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Park Logic
// ---------------------------------------------------------------------------------------------------------------------
assign gnt_park         = {{NUM_MASTERS-1{1'b0}}, 1'b1} << PARK_INDEX;
assign no_valid_req     = (req_masked == {NUM_MASTERS{1'b0}});
assign parked_normal    = ((no_valid_req == 1'b1) && (PARK_MODE == 1'b1));

// ---------------------------------------------------------------------------------------------------------------------
// Lock FSM Combinational Logic
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : LOCK_FSM_COMB_PROC
  next_lock_state            = lock_state;
  next_locked_client         = locked_client;
  case (lock_state)
    STATE_NORMAL:
    begin
      if ((wrr_vld == 1'b1) && (lock[granted_client_idx] == 1'b1))
      begin
        next_lock_state      = STATE_LOCKED;
        next_locked_client   = granted_client_idx;
      end
    end
    STATE_LOCKED:
    begin
      if (lock[locked_client] == 1'b0)
      begin
        next_lock_state      = STATE_NORMAL;
      end
    end
    default:
    begin
      next_lock_state        = STATE_NORMAL;
    end
  endcase
end

// ---------------------------------------------------------------------------------------------------------------------
// Lock FSM Sequential Logic
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : LOCK_FSM_SEQ_PROC
  if (rst_n == 1'b0)
  begin
    lock_state          <= STATE_NORMAL;
    locked_client       <= {PTR_WIDTH{1'b0}};
  end
  else
  begin
    lock_state          <= next_lock_state;
    locked_client       <= next_locked_client;
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Combinational Logic
// ---------------------------------------------------------------------------------------------------------------------
assign gnt_raw          = (lock_state == STATE_LOCKED) ? ({{NUM_MASTERS-1{1'b0}}, 1'b1} << locked_client) :
                          ((wrr_vld == 1'b1) ? gnt_wrr :
                          ((parked_normal == 1'b1) ? gnt_park : {NUM_MASTERS{1'b0}}));

assign granted_raw      = (lock_state == STATE_LOCKED) ? 1'b1 :
                          ((wrr_vld == 1'b1) ? 1'b1 :
                          ((parked_normal == 1'b1) ? 1'b1 : 1'b0));

assign locked_raw       = (lock_state == STATE_LOCKED);

assign parked_raw       = ((lock_state == STATE_NORMAL) && (parked_normal == 1'b1));

// ---------------------------------------------------------------------------------------------------------------------
// Output Stage
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : OUT_REG_PROC
  if (rst_n == 1'b0)
  begin
    gnt_reg             <= {NUM_MASTERS{1'b0}};
    granted_reg         <= 1'b0;
    locked_reg          <= 1'b0;
    parked_reg          <= 1'b0;
  end
  else
  begin
    gnt_reg             <= gnt_raw;
    granted_reg         <= granted_raw;
    locked_reg          <= locked_raw;
    parked_reg          <= parked_raw;
  end
end

assign gnt              = (OUTPUT_MODE == 1'b1) ? gnt_reg     : gnt_raw;
assign granted          = (OUTPUT_MODE == 1'b1) ? granted_reg : granted_raw;
assign locked           = (OUTPUT_MODE == 1'b1) ? locked_reg  : locked_raw;
assign parked           = (OUTPUT_MODE == 1'b1) ? parked_reg  : parked_raw;

endmodule
`endif
// =====================================================================================================================