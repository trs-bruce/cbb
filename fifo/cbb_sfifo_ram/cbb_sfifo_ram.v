// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026-07-28
// Description  : Parameterized single-clock FIFO based on dual-port synchronous-read SRAM. Older data resides in a
//                  local prefetch buffer while later data remains in SRAM. The registered buffer head directly drives
//                  the Show-Ahead output and absorbs the one-cycle SRAM read latency internally.
// NOTE         : Foundry hard-macro model names and library corner names are replaced by neutral
//               placeholders for public distribution. Bind the memory-compiler output of your own
//               process at the placeholder instance, and re-check the fixed tie-off values against
//               your macro databook.
// =====================================================================================================================

`ifndef CBB_SFIFO_RAM_V
`define CBB_SFIFO_RAM_V
module CBB_SFIFO_RAM
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
   output          [DATA_WIDTH-1:0]              rd_data,                      // Current head data, valid when nonempty
   output                                        full,                         // Full flag, active high
   output                                        empty                         // Empty flag, active high
   );

// ----------------------------------------------------------------------------------------------------------------------
// ADDR_W addresses 0..DEPTH-1; CNT_W represents 0..DEPTH (DEPTH+1 values).
// ----------------------------------------------------------------------------------------------------------------------
localparam ADDR_W                                = $clog2(DEPTH);
localparam CNT_W                                 = $clog2(DEPTH + 1);
// BUF_DEPTH fixes the local prefetch buffer at three entries. DEPTH is at least 4, so the buffer always fits;
// user-visible capacity remains DEPTH.
localparam                                       BUF_DEPTH = 3;
localparam                                       BUF_CNT_W = 2;
localparam         [DATA_WIDTH-1:0]              RAM_BWE   = {DATA_WIDTH{1'b1}};

// ----------------------------------------------------------------------------------------------------------------------
// Internal state
// ----------------------------------------------------------------------------------------------------------------------
reg                [DATA_WIDTH-1:0]              buf_mem [0:BUF_DEPTH-1];
reg                [BUF_CNT_W-1:0]               buf_cnt;
reg                [CNT_W-1:0]                   cnt;
reg                [CNT_W-1:0]                   ram_cnt;
reg                [ADDR_W-1:0]                  wr_ptr;
reg                [ADDR_W-1:0]                  rd_ptr;
reg                                              ram_rd_pending;

wire                                             wr_act;
wire                                             rd_act;
wire                                             wr_to_buf;
wire                                             wr_with_rsp_to_buf;
wire                                             wr_to_ram;
wire                                             ram_rd_en;
wire                                             buf_enq;
wire               [DATA_WIDTH-1:0]              buf_enq_data;
wire               [BUF_CNT_W-1:0]               buf_tail_index;
wire               [DATA_WIDTH-1:0]              ram_rd_data;

integer                                          idx;

// ----------------------------------------------------------------------------------------------------------------------
// Total FIFO occupancy
// ----------------------------------------------------------------------------------------------------------------------
// CNT_PROC manages user-visible occupancy; simultaneous write and read leave occupancy unchanged.
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
// SRAM occupancy and response tracking
// ----------------------------------------------------------------------------------------------------------------------
// RAM_CNT_PROC tracks SRAM entries for which no read request has yet been issued.
always @(posedge clk or negedge rst_n)
begin : RAM_CNT_PROC
  if (rst_n == 1'b0)
    ram_cnt             <= {CNT_W{1'b0}};
  else
  begin
    case ({wr_to_ram, ram_rd_en})
      2'b10:   ram_cnt  <= ram_cnt + 1'b1;
      2'b01:   ram_cnt  <= ram_cnt - 1'b1;
      default: ram_cnt  <= ram_cnt;
    endcase
  end
end

// An SRAM read issued in the previous cycle returns in the current cycle.
always @(posedge clk or negedge rst_n)
begin : RAM_RD_PENDING_PROC
  if (rst_n == 1'b0)
    ram_rd_pending      <= 1'b0;
  else
    ram_rd_pending      <= ram_rd_en;
end

// ----------------------------------------------------------------------------------------------------------------------
// SRAM write pointer
// ----------------------------------------------------------------------------------------------------------------------
// WR_PTR_PROC advances on each committed SRAM write and explicitly wraps at DEPTH-1 to support non-power-of-two DEPTH.
always @(posedge clk or negedge rst_n)
begin : WR_PTR_PROC
  if (rst_n == 1'b0)
    wr_ptr              <= {ADDR_W{1'b0}};
  else if (wr_to_ram == 1'b1)
  begin
    if (wr_ptr == (DEPTH - 1'b1))
      wr_ptr            <= {ADDR_W{1'b0}};
    else
      wr_ptr            <= wr_ptr + 1'b1;
  end
end

// ----------------------------------------------------------------------------------------------------------------------
// SRAM read pointer
// ----------------------------------------------------------------------------------------------------------------------
// RD_PTR_PROC advances on each issued SRAM read and explicitly wraps at DEPTH-1 to support non-power-of-two DEPTH.
always @(posedge clk or negedge rst_n)
begin : RD_PTR_PROC
  if (rst_n == 1'b0)
    rd_ptr              <= {ADDR_W{1'b0}};
  else if (ram_rd_en == 1'b1)
  begin
    if (rd_ptr == (DEPTH - 1'b1))
      rd_ptr            <= {ADDR_W{1'b0}};
    else
      rd_ptr            <= rd_ptr + 1'b1;
  end
end

// ----------------------------------------------------------------------------------------------------------------------
// Local prefetch buffer and registered Show-Ahead output
// ----------------------------------------------------------------------------------------------------------------------
// BUF_CNT_PROC maintains prefetch-buffer occupancy. When an SRAM return, write, and consume occur together, remove the
// old head first, then append returned and newly written data in time order. This keeps the head continuous while
// nonempty and prevents bubbles from SRAM read latency.
always @(posedge clk or negedge rst_n)
begin : BUF_CNT_PROC
  if (rst_n == 1'b0)
    buf_cnt                  <= {BUF_CNT_W{1'b0}};
  else
  begin
    // A return and concurrent write enqueue two entries while the read frees one slot, so occupancy increases by one.
    // Otherwise use normal enqueue/dequeue accounting.
    if (wr_with_rsp_to_buf == 1'b1)
      buf_cnt                <= buf_cnt + 1'b1;
    else
    begin
      case ({buf_enq, rd_act})
        2'b10:   buf_cnt     <= buf_cnt + 1'b1;
        2'b01:   buf_cnt     <= buf_cnt - 1'b1;
        default: buf_cnt     <= buf_cnt;
      endcase
    end
  end
end

// BUF_MEM_PROC maintains prefetched data; buf_mem[0] is always the registered head. Data registers are not reset.
always @(posedge clk)
begin : BUF_MEM_PROC
  if (rd_act == 1'b1)
  begin
    for (idx = 0; idx < (BUF_DEPTH - 1); idx = idx + 1)
    begin : BUF_SHIFT_LOOP
      buf_mem[idx]                     <= buf_mem[idx + 1];
    end
  end

  case ({wr_with_rsp_to_buf, buf_enq})
    2'b01: buf_mem[buf_tail_index]     <= buf_enq_data;
    2'b11:
    begin
      buf_mem[buf_tail_index]          <= buf_enq_data;
      buf_mem[buf_tail_index + 1'b1]   <= wr_data;
    end
    default: ;                                                                 // No enqueue; preceding shift still applies.
  endcase
end

// ----------------------------------------------------------------------------------------------------------------------
// Transaction acceptance and status
// cnt is user-visible total occupancy. Data is ordered across the local prefetch buffer, pending response, and SRAM.
// The local buffer always holds the oldest valid data; SRAM holds only later tail data.
// ----------------------------------------------------------------------------------------------------------------------
assign full             = (cnt == DEPTH);                                       // Capacity reached; writes are blocked
assign empty            = (cnt == {CNT_W{1'b0}});                                // Zero occupancy; no valid head exists
assign wr_act           = (wr_en == 1'b1) && (full == 1'b0);                       // Accept a write only when not full
assign rd_act           = (rd_en == 1'b1) && (empty == 1'b0);                      // Accept a read only when not empty
// New data may enter the local buffer directly only when SRAM has no older data and no read response is pending.
assign wr_to_buf        = (wr_act == 1'b1) && (ram_cnt == {CNT_W{1'b0}}) && (ram_rd_pending == 1'b0)
                          && ((buf_cnt < BUF_DEPTH) || (rd_act == 1'b1));
// SRAM return data precedes a same-cycle write. If buffer space is available and the head is consumed this cycle,
// enqueue both in the order: SRAM return, then new write.
assign wr_with_rsp_to_buf    = (wr_act == 1'b1) && (ram_cnt == {CNT_W{1'b0}}) && (ram_rd_pending == 1'b1)
                               && (rd_act == 1'b1) && (buf_cnt < BUF_DEPTH);
// Writes not buffered go to the SRAM tail
assign wr_to_ram             = (wr_act == 1'b1) && (wr_to_buf == 1'b0) && (wr_with_rsp_to_buf == 1'b0);

assign ram_rd_en        = (rd_act == 1'b1) && (ram_cnt != {CNT_W{1'b0}});          // Enable read only while SRAM holds data

// ----------------------------------------------------------------------------------------------------------------------
// Dual-port synchronous-read SRAM
// CBB_RAM_TP provides the behavioral model and instantiates a TSMC 2PRF macro when TSMC_12 is defined. The read port
// updates ram_rd_data on the clock edge after a request, and ram_rd_pending marks that return cycle. Control invariants
// prevent simultaneous reads and writes from accessing the same valid queue entry, so behavior does not depend on the
// SRAM same-address mode. The SRAM uses independent active-high chip selects for its write/read ports and active-high
// write enables.
// ----------------------------------------------------------------------------------------------------------------------
CBB_RAM_TP
#(
.MEM_DATA_WIDTH                        ( DATA_WIDTH                            ),
.MEM_ADDR_WIDTH                        ( ADDR_W                                )
)
U_CBB_RAM_TP
(
.mem_a_clk                             ( clk                                   ),
.mem_b_clk                             ( clk                                   ),
.mem_a_cs                              ( wr_to_ram                             ),
.mem_b_cs                              ( ram_rd_en                             ),
.mem_a_we                              ( wr_to_ram                             ),
.mem_a_bwe                             ( RAM_BWE                               ),
.mem_a_addr                            ( wr_ptr                                ),
.mem_a_wdata                           ( wr_data                               ),
.mem_b_addr                            ( rd_ptr                                ),
.mem_b_rdata                           ( ram_rd_data                           )
);

// A normal enqueue comes from a direct write or SRAM return. For a double enqueue, buf_enq_data is the older return and
// BUF_MEM_PROC appends the new write in the following slot.
assign buf_enq          = (wr_to_buf == 1'b1) || (ram_rd_pending == 1'b1);
assign buf_enq_data     = (wr_to_buf == 1'b1) ? wr_data : ram_rd_data;
// Consume the head first, then append returned or written data starting at buf_tail_index. Space for a pending response
// was reserved by the consume that issued the SRAM read in the previous cycle; a double enqueue also requires another
// head consume in the current cycle.
assign buf_tail_index   = buf_cnt - rd_act;
// Registered prefetch head; valid only when empty is low
assign rd_data          = buf_mem[0];

// ----------------------------------------------------------------------------------------------------------------------
// Assertions
// ----------------------------------------------------------------------------------------------------------------------
`ifdef SOC_ASSERT_ON
  `ifdef CBB_SFIFO_RAM_ASSERT_ON
    `include "cbb_sfifo_ram_assert.sv"
  `endif
`endif

endmodule
`endif
// ======================================================================================================================
// Modified history
// ----------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-07-28 | CBB Team     | Initial version
// V1.1         | 2026-09-21 | CBB Team     | Updated CBB_RAM_TP interface mapping and RTL formatting
// V1.2         | 2026-09-22 | CBB Team     | Normalize formatting only; preserve FIFO behavior
// V1.3         | 2026-11-03 | CBB Team     | Header template alignment: copyright, designer, project tag and non-template fields
// ======================================================================================================================
