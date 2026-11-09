// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team Team
// Project      : cbb
// Create Date  : 2026-07-23
// Description  : Single-clock synchronous FIFO with a combinational pass-through Show-Ahead read interface.
//                  A write into an empty FIFO bypasses combinationally to rd_data and deasserts empty.
//                  rd_data is valid when empty is low.
// =====================================================================================================================

`ifndef CBB_SFIFO_PT_V
`define CBB_SFIFO_PT_V
module CBB_SFIFO_PT
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
   output          [DATA_WIDTH-1:0]              rd_data,                      // Current head or bypassed data
   output                                        full,                         // Full flag, active high
   output                                        empty                         // Empty flag, active high
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

wire                                             mem_empty;
wire                                             bypass_en;
wire                                             wr_act;
wire                                             rd_act;

// ----------------------------------------------------------------------------------------------------------------------
// Storage-empty and FIFO status flags
// ----------------------------------------------------------------------------------------------------------------------
// mem_empty indicates zero storage occupancy and is used only for storage-access bypass decisions.
assign mem_empty        = (cnt == {CNT_W{1'b0}});
// empty indicates a logically empty FIFO. A write while storage is empty bypasses wr_data to rd_data and
// combinationally deasserts empty, so rd_data is valid when empty is low.
assign empty            = (mem_empty == 1'b1) && (wr_en == 1'b0);
// Full at DEPTH occupancy; storage writes are blocked
assign full             = (cnt == DEPTH);

// ----------------------------------------------------------------------------------------------------------------------
// Actual storage read and write operations
// ----------------------------------------------------------------------------------------------------------------------
// Write storage only when not full and not bypassing
assign wr_act           = (wr_en == 1'b1) && (full == 1'b0) && ((mem_empty == 1'b0) || (rd_en == 1'b0));
// Accept a storage read only when storage is nonempty; pass-through does not access storage.
assign rd_act           = (rd_en == 1'b1) && (mem_empty == 1'b0);

// ----------------------------------------------------------------------------------------------------------------------
// FIFO valid-data count
//
// Increment for storage write only, decrement for storage read only, and hold for simultaneous read/write,
// pass-through, or no operation.
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
// The storage array is not reset. Pass-through data from a simultaneous read/write while empty is not stored.
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
//
// When storage is empty and a write is requested, wr_data bypasses directly to rd_data; otherwise rd_data selects the
// current head at mem[rd_ptr].
// ----------------------------------------------------------------------------------------------------------------------
assign bypass_en        = (mem_empty == 1'b1) && (wr_en == 1'b1);
assign rd_data          = (bypass_en == 1'b1) ? wr_data : mem[rd_ptr];

// ----------------------------------------------------------------------------------------------------------------------
// Assertions
// ----------------------------------------------------------------------------------------------------------------------
`ifdef SOC_ASSERT_ON
  `ifdef CBB_SFIFO_PT_ASSERT_ON
    `include "cbb_sfifo_pt_assert.sv"
  `endif
`endif

endmodule
`endif
// ======================================================================================================================