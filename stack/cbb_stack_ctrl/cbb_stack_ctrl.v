// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026/08/31
// Description  : Reusable synchronous LIFO stack controller aligned with DW_stackctl duties.
// =====================================================================================================================

`ifndef CBB_STACK_CTRL_V
`define CBB_STACK_CTRL_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
// Clock       : clk, active high
// Reset       : rst_n, asynchronous active-low; external RAM is not reset
// Latency     : Addresses and status update with occupancy at the clock edge; pop acceptance is combinational via pop_fire
// Modes       : ERR_MODE=0 latches error until reset; ERR_MODE=1 holds error for one cycle
// Assumptions : push/pop are active-high and push wins on simultaneous requests; DEPTH is 2..256
// ---------------------------------------------------------------------------------------------------------------------
module CBB_STACK_CTRL
#(
  parameter DEPTH                               = 16,
  parameter ERR_MODE                            = 0
)
(
   input wire                                    clk,
   input wire                                    rst_n,
   input wire                                    push,
   input wire                                    pop,
   output wire                                   pop_fire,
   output wire                                   we_n,
   output reg      [$clog2(DEPTH)-1:0]           wr_addr,
   output reg      [$clog2(DEPTH)-1:0]           rd_addr,
   output reg                                    empty,
   output reg                                    full,
   output reg                                    half_full,
   output reg                                    error
);

localparam                                       COUNT_W                       = $clog2(DEPTH + 1);
localparam                                       ADDR_W                        = $clog2(DEPTH);
localparam         [COUNT_W-1:0]                 COUNT_ZERO                    = {COUNT_W{1'b0}};
localparam         [COUNT_W-1:0]                 COUNT_ONE                     = 1;
localparam         [COUNT_W-1:0]                 DEPTH_COUNT                   = DEPTH;
localparam         [COUNT_W-1:0]                 DEPTH_MINUS_ONE_COUNT         = DEPTH - 1;
localparam         [COUNT_W-1:0]                 HALF_FULL_COUNT               = (DEPTH + 1) / 2;
localparam         [COUNT_W-1:0]                 HALF_FULL_MINUS_ONE_COUNT     =
                                                                                 ((DEPTH + 1) / 2) - 1;

reg                [COUNT_W-1:0]                 count_q;
reg                [COUNT_W-1:0]                 next_count;
wire                                             overflow_request;
wire                                             underflow_request;
wire                                             push_fire;

assign overflow_request      = (push == 1'b1) &&
                               (count_q == DEPTH_COUNT);
assign underflow_request     = (pop == 1'b1) &&
                               (push == 1'b0) &&
                               (count_q == COUNT_ZERO);
assign push_fire             = (push == 1'b1) &&
                               (count_q < DEPTH_COUNT);
assign pop_fire              = (pop == 1'b1) &&
                               (push == 1'b0) &&
                               (count_q > COUNT_ZERO);
assign we_n                  = ~push_fire;

// Next occupancy from the current count; Push wins over Pop on simultaneous requests.
always @(*)
begin : NEXT_COUNT_PROC
  next_count = count_q;
  if (push_fire == 1'b1)
  begin
    next_count = count_q + 1'b1;
  end
  else if (pop_fire == 1'b1)
  begin
    next_count = count_q - 1'b1;
  end
end

// DW-style address relation: wr_addr points to the next write location.
always @(*)
begin : WRITE_ADDRESS_PROC
  wr_addr = {ADDR_W{1'b0}};
  if (count_q < DEPTH_COUNT)
  begin
    wr_addr = count_q[ADDR_W-1:0];
  end
  else
  begin
    wr_addr = DEPTH_MINUS_ONE_COUNT[ADDR_W-1:0];
  end
end

// rd_addr points to the current top of stack; it holds 0 when empty to avoid address underflow.
always @(*)
begin : READ_ADDRESS_PROC
  rd_addr = {ADDR_W{1'b0}};
  if (count_q > COUNT_ZERO)
  begin
    rd_addr = count_q[ADDR_W-1:0] - 1'b1;
  end
end

// Holds the valid occupancy; external RAM does not participate in reset clearing.
always @(posedge clk or negedge rst_n)
begin : COUNT_PROC
  if (rst_n == 1'b0)
  begin
    count_q <= COUNT_ZERO;
  end
  else
  begin
    count_q <= next_count;
  end
end

// DW-compatible empty, full and half-full status, updated after the accepting edge.
always @(posedge clk or negedge rst_n)
begin : STATUS_PROC
  if (rst_n == 1'b0)
  begin
    empty     <= 1'b1;
  end
  else if (push_fire == 1'b1)
  begin
    empty     <= 1'b0;
  end
  else if (pop_fire == 1'b1)
  begin
    empty     <= (count_q == COUNT_ONE);
  end
end

always @(posedge clk or negedge rst_n)
begin : FULL_STATUS_PROC
  if (rst_n == 1'b0)
  begin
    full <= 1'b0;
  end
  else if (push_fire == 1'b1)
  begin
    full <= (count_q == DEPTH_MINUS_ONE_COUNT);
  end
  else if (pop_fire == 1'b1)
  begin
    full <= 1'b0;
  end
end

always @(posedge clk or negedge rst_n)
begin : HALF_FULL_STATUS_PROC
  if (rst_n == 1'b0)
  begin
    half_full <= 1'b0;
  end
  else if (push_fire == 1'b1)
  begin
    half_full <= (count_q >= HALF_FULL_MINUS_ONE_COUNT);
  end
  else if (pop_fire == 1'b1)
  begin
    half_full <= (count_q > HALF_FULL_COUNT);
  end
end

// DW err_mode=0 latches errors; err_mode=1 holds them for a single cycle.
always @(posedge clk or negedge rst_n)
begin : ERROR_PROC
  if (rst_n == 1'b0)
  begin
    error <= 1'b0;
  end
  else if (ERR_MODE == 0)
  begin
    if ((overflow_request == 1'b1) ||
    (underflow_request == 1'b1))
    begin
      error <= 1'b1;
    end
  end
  else
  begin
    error <= (overflow_request == 1'b1) ||
    (underflow_request == 1'b1);
  end
end

endmodule
`endif

// =====================================================================================================================
// Modification history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-08-31 | CBB Team     | Extracted the reusable stack controller from CBB_STACK, aligned with DW_stackctl.
// V1.1         | 2026-09-03 | CBB Team     | Split read/write address combinational logic to satisfy CODE-GEN05.
// V1.2         | 2026-11-03 | CBB Team     | Header template alignment: copyright, designer, project tag and non-template fields
// V1.3         | 2026-11-03 | CBB Team     | Move non-template header fields into the functional overview block
// =====================================================================================================================
