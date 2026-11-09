// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team Team
// Project      : cbb
// Create Date  : 2026-07-27
// Description  : Single-clock synchronous FIFO with a registered Show-Ahead read interface.
//                  rd_data holds the current head while empty is low. An accepted read consumes that head on the clock
//                  edge and synchronously prefetches the next head into rd_data. rd_data is valid while empty is low.
// =====================================================================================================================

`ifndef CBB_SFIFO_OR_V
`define CBB_SFIFO_OR_V
module CBB_SFIFO_OR
  #(
   parameter DATA_WIDTH                          = 32,
   parameter DEPTH                               = 16
   )
   (
   input                                         clk,                          // Operating clock, rising-edge active
   input                                         rst_n,                        // Asynchronous reset, active low
   input                                         wr_en,                        // Write request, active high
   input           [DATA_WIDTH-1:0]              wr_data,                      // Write data
   input                                         rd_en,                        // Read request, active high
   output reg      [DATA_WIDTH-1:0]              rd_data,                      // Current head data, valid when nonempty
   output                                        full,                         // Full flag, active high
   output                                        empty                         // Empty flag, active high
   );

// ----------------------------------------------------------------------------------------------------------------------
// ADDR_W addresses 0..DEPTH-1; CNT_W represents 0..DEPTH (DEPTH+1 values).
// ----------------------------------------------------------------------------------------------------------------------
localparam ADDR_W                                = $clog2(DEPTH);
localparam CNT_W                                 = $clog2(DEPTH + 1);

reg                [DATA_WIDTH-1:0]              mem [0:DEPTH-1];
reg                [ADDR_W-1:0]                  wr_ptr;
reg                [ADDR_W-1:0]                  rd_ptr;
reg                [CNT_W-1:0]                   cnt;

wire                                             wr_act;
wire                                             rd_act;
wire               [ADDR_W-1:0]                  rd_ptr_next;

// ----------------------------------------------------------------------------------------------------------------------
// Empty and full status flags
// ----------------------------------------------------------------------------------------------------------------------
// Zero occupancy; rd_data has no valid head
assign empty            = (cnt == {CNT_W{1'b0}});
// Occupancy has reached DEPTH; no more writes are accepted
assign full             = (cnt == DEPTH);

// ----------------------------------------------------------------------------------------------------------------------
// Accepted read and write operations
// For simultaneous requests, accept only the write when empty and only the read when full.
// ----------------------------------------------------------------------------------------------------------------------
assign wr_act           = (wr_en == 1'b1) && (full == 1'b0);                   // Accept a write only when not full
assign rd_act           = (rd_en == 1'b1) && (empty == 1'b0);                  // Accept a read only when not empty

// ----------------------------------------------------------------------------------------------------------------------
// FIFO valid-data count
// Increment for write only, decrement for read only, and hold for simultaneous read/write or no operation.
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : CNT_PROC
  if (rst_n == 1'b0)
    cnt                 <= {CNT_W{1'b0}};
  else
  begin
    case ({wr_act, rd_act})
      2'b10:   cnt      <= cnt + 1'b1;
      2'b01:   cnt      <= cnt - 1'b1;
      default: cnt      <= cnt;
    endcase
  end
end

// ----------------------------------------------------------------------------------------------------------------------
// Write pointer
// Advance on an accepted write. Explicitly wrap from DEPTH-1 to zero to support non-power-of-two DEPTH.
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : WR_PTR_PROC
  if (rst_n == 1'b0)
    wr_ptr              <= {ADDR_W{1'b0}};
  else if (wr_act == 1'b1)
  begin
    if (wr_ptr == (DEPTH - 1'b1))
      wr_ptr            <= {ADDR_W{1'b0}};
    else
      wr_ptr            <= wr_ptr + 1'b1;
  end
end

// ----------------------------------------------------------------------------------------------------------------------
// Storage-array write
// The array is not reset. Reads are accepted only when nonempty, so stale data is never exposed as a valid head.
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge clk)
begin : MEM_WRITE_PROC
  if (wr_act == 1'b1)
    mem[wr_ptr]         <= wr_data;
end

// ----------------------------------------------------------------------------------------------------------------------
// Next read pointer
// ----------------------------------------------------------------------------------------------------------------------
// This is the next read address after consuming the current head and indexes the next head prefetched into rd_data.
assign rd_ptr_next      = (rd_ptr == (DEPTH - 1'b1)) ? {ADDR_W{1'b0}} : rd_ptr + 1'b1;

// ----------------------------------------------------------------------------------------------------------------------
// Read pointer
// Advance on an accepted read and explicitly wrap from DEPTH-1 to zero.
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : RD_PTR_PROC
  if (rst_n == 1'b0)
    rd_ptr              <= {ADDR_W{1'b0}};
  else if (rd_act == 1'b1)
    rd_ptr              <= rd_ptr_next;
end

// ----------------------------------------------------------------------------------------------------------------------
// Registered Show-Ahead output
// rd_data holds the valid current head while empty is low. An accepted read consumes it on the clock edge and
// prefetches the next head into rd_data.
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge clk)
begin : RD_DATA_PROC
  // First write into empty FIFO becomes registered head
  if ((empty == 1'b1) && (wr_act == 1'b1))
    rd_data             <= wr_data;
  // For simultaneous read/write with one entry, consume the old head and make the new write the next head.
  // The new data enters storage on this edge, so mem[rd_ptr_next] cannot provide it yet.
  else if ((rd_act == 1'b1) && (cnt == {{(CNT_W-1){1'b0}}, 1'b1}) && (wr_act == 1'b1))
    rd_data             <= wr_data;
  // Consume current head and prefetch next head from storage
  else if (rd_act == 1'b1)
    rd_data             <= mem[rd_ptr_next];
end

// ----------------------------------------------------------------------------------------------------------------------
// Assertions
// ----------------------------------------------------------------------------------------------------------------------
`ifdef SOC_ASSERT_ON
  `ifdef CBB_SFIFO_OR_ASSERT_ON
    `include "cbb_sfifo_or_assert.sv"
  `endif
`endif

endmodule
`endif
// ======================================================================================================================