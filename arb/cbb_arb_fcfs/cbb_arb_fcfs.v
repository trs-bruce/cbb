// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026/07/20
// Description  : Parameterized synchronous FCFS (First-Come-First-Served) arbiter
//                - Each client owns a priority counter; smaller value = waited longer = higher priority
//                - Waiting-but-not-granted clients decrement by 1 per cycle
//                - Granted / non-requesting clients are set to MAX_PRIORITY (lowest priority)
//                - Mechanism priority: Lock > Mask > Normal arbitration > Park
//                - Parameterizable client number, park mode and output mode
// =====================================================================================================================

`ifndef CBB_ARB_FCFS_V
`define CBB_ARB_FCFS_V
module CBB_ARB_FCFS
   #(
    parameter NUM_MASTERS                         = 4,                          // Client number (2~32)
    parameter PARK_MODE                           = 1,                          // Park mode: 0=disable, 1=enable
    parameter PARK_INDEX                          = 0,                          // Park client index (0~NUM_MASTERS-1), valid when PARK_MODE=1
    parameter OUTPUT_MODE                         = 1                           // Output mode: 0=combinational, 1=registered
    )
    (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset (active low)
   input           [NUM_MASTERS-1:0]             req,                          // Client request (active high)
   input           [NUM_MASTERS-1:0]             lock,                         // Lock request (active high)
   input           [NUM_MASTERS-1:0]             mask,                         // Mask request (active high)
   output          [NUM_MASTERS-1:0]             gnt,                          // One-hot grant output
   output                                        granted,                      // Grant flag (active high)
   output                                        locked,                       // Lock flag (active high)
   output                                        parked                        // Park flag (active high)
    );

// ---------------------------------------------------------------------------------------------------------------------
// Constant Parameter
// ---------------------------------------------------------------------------------------------------------------------
localparam PRIORITY_WIDTH                        = (NUM_MASTERS <= 2)  ? 1 :   // Priority counter width
                                                   (NUM_MASTERS <= 4)  ? 2 :
                                                   (NUM_MASTERS <= 8)  ? 3 :
                                                   (NUM_MASTERS <= 16) ? 4 : 5;
localparam MAX_PRIORITY                          = NUM_MASTERS - 1;            // Lowest priority (max value)

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
wire               [NUM_MASTERS-1:0]             req_masked;                        // Effective request after mask
wire               [NUM_MASTERS-1:0]             park_oh;                           // One-hot park grant
wire               [NUM_MASTERS-1:0]             gnt_hold;                          // Grant value for lock detect and hold
wire                                             req_any;                           // Any effective request
wire                                             lock_det;                          // Lock detected on granted client
wire                                             update_priorities;                 // Priority update enable (0 in lock)
wire                                             granted_c;                         // Grant flag (combinational)
wire                                             locked_c;                          // Lock flag (combinational)
wire                                             parked_c;                          // Park flag (combinational)
reg                                              gnt_vld_v;                         // Arbitration winner valid
reg                [PRIORITY_WIDTH-1:0]          gnt_idx_v;                         // Arbitration winner index
reg                [NUM_MASTERS-1:0]             gnt_pre;                           // One-hot pre-lock grant
reg                [NUM_MASTERS-1:0]             gnt_next;                          // Next grant value
reg                [NUM_MASTERS-1:0]             gnt_r;                             // Grant register
reg                                              granted_r;                         // Grant flag register
reg                                              locked_r;                          // Lock flag register
reg                                              parked_r;                          // Park flag register
reg                [PRIORITY_WIDTH-1:0]          pri_cnt [0:NUM_MASTERS-1];         // Priority counters
reg                [PRIORITY_WIDTH-1:0]          pri_cnt_nxt [0:NUM_MASTERS-1];     // Next priority counters
integer                                          sel_i;                             // Arbitration select loop index
integer                                          dec_i;                             // Grant decode loop index
integer                                          upd_i;                             // Priority next-state loop index
integer                                          seq_i;                             // Priority register loop index

// ---------------------------------------------------------------------------------------------------------------------
// Mask Gate: effective request = request & ~mask
// ---------------------------------------------------------------------------------------------------------------------
assign req_masked            = req & ~mask;
assign req_any               = |req_masked;

// ---------------------------------------------------------------------------------------------------------------------
// Park One-hot Decode
// ---------------------------------------------------------------------------------------------------------------------
assign park_oh               = {{(NUM_MASTERS-1){1'b0}}, 1'b1} << PARK_INDEX;

// ---------------------------------------------------------------------------------------------------------------------
// Arbitration Select: traverse clients from index 0, winner = effective requester with minimum priority value
// Equal priority values: lower index wins naturally (later clients fail the '<' comparison)
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : ARB_SELECT_PROC
  gnt_idx_v                  = {PRIORITY_WIDTH{1'b0}};
  gnt_vld_v                  = 1'b0;
  for (sel_i = 0; sel_i < NUM_MASTERS; sel_i = sel_i + 1)
  begin : ARB_SELECT_LOOP
    if (req_masked[sel_i] == 1'b1)
    begin
      if ((gnt_vld_v == 1'b0) || (pri_cnt[sel_i] < pri_cnt[gnt_idx_v]))
      begin
        gnt_idx_v            = sel_i[PRIORITY_WIDTH-1:0];
        gnt_vld_v            = 1'b1;
      end
    end
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Grant One-hot Decode
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : GNT_DECODE_PROC
  gnt_pre                    = {NUM_MASTERS{1'b0}};
  for (dec_i = 0; dec_i < NUM_MASTERS; dec_i = dec_i + 1)
  begin : GNT_DECODE_LOOP
    if ((gnt_vld_v == 1'b1) && (gnt_idx_v == dec_i[PRIORITY_WIDTH-1:0]))
      gnt_pre[dec_i]         = 1'b1;
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Lock Detect and Status Flags
// Lock: current granted client asserts lock -> grant holds, priorities freeze
// ---------------------------------------------------------------------------------------------------------------------
assign lock_det              = |(gnt_hold & lock);
assign update_priorities     = (lock_det == 1'b0);
assign granted_c             = req_any;
assign locked_c              = lock_det;
assign parked_c              = (req_any == 1'b0) && (lock_det == 1'b0) && (PARK_MODE == 1);

// ---------------------------------------------------------------------------------------------------------------------
// Next Grant Decision: Lock > Mask > Normal arbitration > Park
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : GNT_NEXT_PROC
  if (lock_det == 1'b1)
    gnt_next                 = gnt_hold;                                       // Lock: hold current grant
  else if (gnt_vld_v == 1'b1)
    gnt_next                 = gnt_pre;                                        // Normal arbitration
  else if (PARK_MODE == 1)
    gnt_next                 = park_oh;                                        // Park: no effective request
  else
    gnt_next                 = {NUM_MASTERS{1'b0}};
end

// ---------------------------------------------------------------------------------------------------------------------
// Priority Next-state: granted -> MAX_PRIORITY, waiting -> decrement, no request -> MAX_PRIORITY
// In lock state (update_priorities=0): waiting clients hold, dropped clients fall to MAX_PRIORITY
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : PRIORITY_NEXT_PROC
  for (upd_i = 0; upd_i < NUM_MASTERS; upd_i = upd_i + 1)
  begin : PRIORITY_NEXT_LOOP
    if ((update_priorities == 1'b1) && (gnt_vld_v == 1'b1) && (gnt_idx_v == upd_i[PRIORITY_WIDTH-1:0]))
      pri_cnt_nxt[upd_i]     = MAX_PRIORITY[PRIORITY_WIDTH-1:0];               // Granted: back to lowest priority
    else if (req_masked[upd_i] == 1'b1)
    begin
      if (update_priorities == 1'b1)
        pri_cnt_nxt[upd_i]   = pri_cnt[upd_i] - 1'b1;                          // Waiting: priority rises
      else
        pri_cnt_nxt[upd_i]   = pri_cnt[upd_i];                                 // Locked: priority frozen
    end
    else
      pri_cnt_nxt[upd_i]     = MAX_PRIORITY[PRIORITY_WIDTH-1:0];               // No request: lowest priority
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Priority Counter Registers
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : PRIORITY_PROC
  if (rst_n == 1'b0)
  begin
    for (seq_i = 0; seq_i < NUM_MASTERS; seq_i = seq_i + 1)
    begin : PRIORITY_RESET_LOOP
      pri_cnt[seq_i]         <= MAX_PRIORITY[PRIORITY_WIDTH-1:0];
    end
  end
  else
  begin
    for (seq_i = 0; seq_i < NUM_MASTERS; seq_i = seq_i + 1)
    begin : PRIORITY_UPDATE_LOOP
      pri_cnt[seq_i]         <= pri_cnt_nxt[seq_i];
    end
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Registers
// OUTPUT_MODE=1: gnt_r is the current grant; OUTPUT_MODE=0: gnt_r is the previous-cycle grant (lock reference)
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : GNT_REG_PROC
  if (rst_n == 1'b0)
    gnt_r                    <= {NUM_MASTERS{1'b0}};
  else
    gnt_r                    <= gnt_next;
end

always @(posedge clk or negedge rst_n)
begin : GRANTED_REG_PROC
  if (rst_n == 1'b0)
    granted_r                <= 1'b0;
  else
    granted_r                <= granted_c;
end

always @(posedge clk or negedge rst_n)
begin : LOCKED_REG_PROC
  if (rst_n == 1'b0)
    locked_r                 <= 1'b0;
  else
    locked_r                 <= locked_c;
end

always @(posedge clk or negedge rst_n)
begin : PARKED_REG_PROC
  if (rst_n == 1'b0)
    parked_r                 <= 1'b0;
  else
    parked_r                 <= parked_c;
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Mux: OUTPUT_MODE=1 registered output, OUTPUT_MODE=0 combinational output
// ---------------------------------------------------------------------------------------------------------------------
assign gnt_hold              = gnt_r;
assign gnt                   = (OUTPUT_MODE == 1) ? gnt_r     : gnt_next;
assign granted               = (OUTPUT_MODE == 1) ? granted_r : granted_c;
assign locked                = (OUTPUT_MODE == 1) ? locked_r  : locked_c;
assign parked                = (OUTPUT_MODE == 1) ? parked_r  : parked_c;

endmodule
`endif
// =====================================================================================================================