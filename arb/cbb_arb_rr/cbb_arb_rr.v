// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team Team
// Project      : cbb
// Create Date  : 2026-07-17
// Description  : Round-Robin Arbiter with Lock and Park support (Token-based scan)
// =====================================================================================================================

`ifndef CBB_ARB_RR_V
`define CBB_ARB_RR_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
//                Parameters:
//                  NUM_MASTERS  : number of request masters (2~32)
//                  OUTPUT_MODE  : 0=combinational output, 1=registered output
//                  PARK_MODE    : 0=disable park, 1=enable park
//                  PARK_INDEX   : default grant index when park enabled
// ---------------------------------------------------------------------------------------------------------------------
module CBB_ARB_RR
   #(
    parameter NUM_MASTERS                         = 4,                          // Number of masters (2~32)
    parameter OUTPUT_MODE                         = 1,                          // 0: combinational, 1: registered
    parameter PARK_MODE                           = 1,                          // 0: disable park, 1: enable park
    parameter PARK_INDEX                          = 0                           // Park target index (0~NUM_MASTERS-1)
    )
    (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset (active low)
   input           [NUM_MASTERS-1:0]             req,                          // Request from masters
   input           [NUM_MASTERS-1:0]             mask,                         // Mask for masters
   input           [NUM_MASTERS-1:0]             lock,                         // Lock from masters
   output          [NUM_MASTERS-1:0]             gnt,                          // One-hot grant
   output                                        granted,                      // Grant valid flag
   output                                        locked,                       // Lock state flag
   output                                        parked                        // Park state flag
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

// Round-robin token scan
wire               [NUM_MASTERS-1:0]             unused_req_rotate_hi;         // Discarded upper request rotation bits
wire               [NUM_MASTERS-1:0]             unused_gnt_rotate_hi;         // Discarded upper grant rotation bits
wire               [NUM_MASTERS-1:0]             req_shifted;                  // Rotated request vector (bit 0 = token)
reg                [NUM_MASTERS-1:0]             gnt_shifted;                  // Priority encoded grant (rotated)
wire               [NUM_MASTERS-1:0]             gnt_normal;                   // Normal RR grant

// Park logic
wire               [NUM_MASTERS-1:0]             gnt_park;                     // Park default grant

// Lock FSM
reg                                              lock_state;                   // Current lock state
reg                [PTR_WIDTH-1:0]               locked_client;                // Currently locked client
reg                [PTR_WIDTH-1:0]               token;                        // Round-robin token pointer

reg                                              next_lock_state;              // Next lock state
reg                [PTR_WIDTH-1:0]               next_locked_client;           // Next locked client
reg                [PTR_WIDTH-1:0]               next_token;                   // Next token pointer

// Grant index
reg                [PTR_WIDTH-1:0]               granted_client_idx;           // Index of granted client

// Raw outputs
wire               [NUM_MASTERS-1:0]             gnt_raw;                      // Combinational grant
wire                                             granted_raw;                  // Combinational granted flag
wire                                             locked_raw;                   // Combinational locked flag
wire                                             parked_raw;                   // Combinational parked flag
wire                                             parked_normal;                // Park flag in normal state

// Loop variables and helper signals
reg                                              pe_found;                     // Priority encode found flag
reg                [PTR_WIDTH:0]                 ptr_plus1;                    // Pointer+1 temp for modulo wrap

// Output registers
reg                [NUM_MASTERS-1:0]             gnt_reg;                      // Registered grant
reg                                              granted_reg;                  // Registered granted flag
reg                                              locked_reg;                   // Registered locked flag
reg                                              parked_reg;                   // Registered parked flag

// ---------------------------------------------------------------------------------------------------------------------
// Mask Logic
// ---------------------------------------------------------------------------------------------------------------------
assign req_masked       = req & (~mask);

// ---------------------------------------------------------------------------------------------------------------------
// Round-Robin Token Scan
// ---------------------------------------------------------------------------------------------------------------------
// Bit 0 of req_shifted corresponds to the current token holder. If it has a
// valid request, grant it and hold the token; otherwise scan from token+1.
assign {unused_req_rotate_hi, req_shifted}  = ({req_masked, req_masked} >> token);

integer                                          pe_idx;                       // RR scan loop index
always @(*)
begin : RR_SCAN_PROC
  gnt_shifted                = {NUM_MASTERS{1'b0}};
  pe_found                   = 1'b0;
  for (pe_idx = 0; pe_idx < NUM_MASTERS; pe_idx = pe_idx + 1)
  begin : RR_SCAN_LOOP
    if ((pe_found == 1'b0) && (req_shifted[pe_idx] == 1'b1))
    begin
      gnt_shifted[pe_idx]    = 1'b1;
      pe_found               = 1'b1;
    end
  end
end

assign {unused_gnt_rotate_hi, gnt_normal}   = ({gnt_shifted, gnt_shifted} >> (NUM_MASTERS - {{(32-PTR_WIDTH){1'b0}}, token}));

// ---------------------------------------------------------------------------------------------------------------------
// Park Logic
// ---------------------------------------------------------------------------------------------------------------------
assign gnt_park         = (PARK_MODE == 1'b1) ? ({{NUM_MASTERS-1{1'b0}}, 1'b1} << PARK_INDEX) : {NUM_MASTERS{1'b0}};

// ---------------------------------------------------------------------------------------------------------------------
// Granted Client Index
// ---------------------------------------------------------------------------------------------------------------------
integer                                          gc_idx;                 // Grant client index loop index
always @(*)
begin : GRANTED_IDX_PROC
  granted_client_idx         = {PTR_WIDTH{1'b0}};
  for (gc_idx = 0; gc_idx < NUM_MASTERS; gc_idx = gc_idx + 1)
  begin : GNT_INDEX_LOOP
    if (gnt_normal[gc_idx] == 1'b1)
      granted_client_idx     = gc_idx[PTR_WIDTH-1:0];
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Lock FSM Combinational Logic
// ---------------------------------------------------------------------------------------------------------------------
always @(*)
begin : LOCK_FSM_COMB_PROC
  next_lock_state            = lock_state;
  next_locked_client         = locked_client;
  next_token                 = token;
  case (lock_state)
    STATE_NORMAL:
    begin
      if (gnt_normal != {NUM_MASTERS{1'b0}})
      begin
        if (lock[granted_client_idx] == 1'b1)
        begin
          // Locked: freeze the token on the granted client, it resumes on release
          next_token           = granted_client_idx;
          next_lock_state      = STATE_LOCKED;
          next_locked_client   = granted_client_idx;
        end
        else
        begin
          // Advance the token past the granted client so the next arbitration cycle
          // scans from the following port. Holding the token on the winner would let a
          // continuously requesting port win forever, turning RR back into fixed priority.
          ptr_plus1            = {1'b0, granted_client_idx} + 1'b1;
          if (ptr_plus1 >= NUM_MASTERS[PTR_WIDTH:0])
            next_token         = ptr_plus1[PTR_WIDTH-1:0] - NUM_MASTERS[PTR_WIDTH-1:0];
          else
            next_token         = ptr_plus1[PTR_WIDTH-1:0];
        end
      end
      else
      begin
        // No valid request: roll token forward to avoid pointer deadlock
        ptr_plus1            = {1'b0, token} + 1'b1;
        if (ptr_plus1 >= NUM_MASTERS[PTR_WIDTH:0])
          next_token         = ptr_plus1[PTR_WIDTH-1:0] - NUM_MASTERS[PTR_WIDTH-1:0];
        else
          next_token         = ptr_plus1[PTR_WIDTH-1:0];
      end
    end
    STATE_LOCKED:
    begin
      if (lock[locked_client] == 1'b0)
      begin
        next_lock_state      = STATE_NORMAL;
        // Resume arbitration from the client after the locked one
        ptr_plus1            = {1'b0, locked_client} + 1'b1;
        if (ptr_plus1 >= NUM_MASTERS[PTR_WIDTH:0])
          next_token         = ptr_plus1[PTR_WIDTH-1:0] - NUM_MASTERS[PTR_WIDTH-1:0];
        else
          next_token         = ptr_plus1[PTR_WIDTH-1:0];
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
    token               <= {PTR_WIDTH{1'b0}};
  end
  else
  begin
    lock_state          <= next_lock_state;
    locked_client       <= next_locked_client;
    token               <= next_token;
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Combinational Logic
// ---------------------------------------------------------------------------------------------------------------------
assign parked_normal    = ((gnt_normal == {NUM_MASTERS{1'b0}}) && (PARK_MODE == 1'b1));

assign gnt_raw          = (lock_state == STATE_LOCKED) ? ({{NUM_MASTERS-1{1'b0}}, 1'b1} << locked_client) :
                          ((gnt_normal != {NUM_MASTERS{1'b0}}) ? gnt_normal : gnt_park);

assign granted_raw      = (lock_state == STATE_LOCKED) ? 1'b1 :
                          ((gnt_normal != {NUM_MASTERS{1'b0}}) ? 1'b1 : (PARK_MODE == 1'b1));

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