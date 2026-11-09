// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team Team
// Project      : cbb
// Create Date  : 2026-07-17
// Description  : Single-clock synchronous FIFO with a combinational Show-Ahead read interface.
//                  The current head is presented on rd_data when nonempty. Configurable almost-empty and almost-full
//                  threshold flags support exact DEPTH capacity, including non-power-of-two depths.
// =====================================================================================================================

`ifndef CBB_SFIFO_V
`define CBB_SFIFO_V
module CBB_SFIFO
  #(
   parameter DATA_WIDTH                          = 32,
   parameter DEPTH                               = 16,
   parameter ALMOST_EMPTY_THRESH                 = 1,
   parameter ALMOST_FULL_THRESH                  = DEPTH - 1
   )
   (
   input                                         clk,                          // Operating clock, rising-edge active
   input                                         rst_n,                        // Asynchronous reset, active low
   input                                         wr_en,                        // Write request, active high
   input           [DATA_WIDTH-1:0]              wr_data,                      // Write data
   output                                        full,                         // Full flag, active high
   output                                        almost_full,                  // Almost-full flag, active high
   input                                         rd_en,                        // Read request, active high
   output          [DATA_WIDTH-1:0]              rd_data,                      // Current head data, valid when nonempty
   output                                        empty,                        // Empty flag, active high
   output                                        almost_empty                  // Almost-empty flag, active high
   );

// ----------------------------------------------------------------------------------------------------------------------
// ADDR_W addresses 0..DEPTH-1; CNT_W represents 0..DEPTH (DEPTH+1 values).
// ----------------------------------------------------------------------------------------------------------------------
localparam ADDR_W                                = $clog2(DEPTH);
localparam CNT_W                                 = $clog2(DEPTH + 1);

// ----------------------------------------------------------------------------------------------------------------------
// Storage array, read/write pointers, and valid-data count
// ----------------------------------------------------------------------------------------------------------------------
reg                [DATA_WIDTH-1:0]              mem [0:DEPTH-1];
reg                [ADDR_W-1:0]                  wr_ptr;
reg                [ADDR_W-1:0]                  rd_ptr;
reg                [CNT_W-1:0]                   cnt;

wire                                             wr_act;
wire                                             rd_act;

// ----------------------------------------------------------------------------------------------------------------------
// Occupancy, status, and transaction acceptance
// ----------------------------------------------------------------------------------------------------------------------
// Zero occupancy; rd_data is valid when empty is low
assign empty            = (cnt == {CNT_W{1'b0}});
assign full             = (cnt == DEPTH);                                      // Occupancy has reached DEPTH
// Occupancy has reached the almost-full threshold
assign almost_full      = (cnt >= ALMOST_FULL_THRESH);
// Occupancy is at or below the almost-empty threshold
assign almost_empty     = (cnt <= ALMOST_EMPTY_THRESH);
assign wr_act           = (wr_en == 1'b1) && (full == 1'b0);                   // Accept a write only when not full
assign rd_act           = (rd_en == 1'b1) && (empty == 1'b0);                  // Accept a read only when not empty

// ----------------------------------------------------------------------------------------------------------------------
// FIFO valid-data count
//
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
//
// Advance on an actual storage write. Explicitly wrap from DEPTH-1 to zero to support non-power-of-two DEPTH.
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
//
// The storage array is not reset.
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge clk)
begin : MEM_WRITE_PROC
  if (wr_act == 1'b1)
    mem[wr_ptr]         <= wr_data;
end

// ----------------------------------------------------------------------------------------------------------------------
// Read pointer
//
// Advance on an actual storage read. Explicitly wrap from DEPTH-1 to zero.
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : RD_PTR_PROC
  if (rst_n == 1'b0)
    rd_ptr              <= {ADDR_W{1'b0}};
  else if (rd_act == 1'b1)
  begin
    if (rd_ptr == (DEPTH - 1'b1))
      rd_ptr            <= {ADDR_W{1'b0}};
    else
      rd_ptr            <= rd_ptr + 1'b1;
  end
end

// ----------------------------------------------------------------------------------------------------------------------
// Combinational Show-Ahead output
// ----------------------------------------------------------------------------------------------------------------------
assign rd_data          = mem[rd_ptr];                                         // Output is invalid when empty is high

// ----------------------------------------------------------------------------------------------------------------------
// Assertions
// ----------------------------------------------------------------------------------------------------------------------
`ifdef SOC_ASSERT_ON
  `ifdef CBB_SFIFO_ASSERT_ON
    `include "cbb_sfifo_assert.sv"
  `endif
`endif

endmodule
`endif
// ======================================================================================================================