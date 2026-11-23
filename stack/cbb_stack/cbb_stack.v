// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026/07/28
// Description  : Parameterized synchronous LIFO stack with DW_stack control semantics.
// =====================================================================================================================

`ifndef CBB_STACK_V
`define CBB_STACK_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
// Clock       : clk, active high
// Reset       : rst_n, asynchronous active-low; synchronous release must be guaranteed externally
// Assumptions : push/pop are active-high and push wins on simultaneous requests; after an accepted pop,
//               dout and dout_valid are returned one cycle later.
//               WIDTH is 1..256, DEPTH is 2..256, MEM_IMPL and ERR_MODE are 0 or 1.
// ---------------------------------------------------------------------------------------------------------------------
module CBB_STACK
#(
  parameter WIDTH                               = 8,
  parameter DEPTH                               = 16,
  parameter MEM_IMPL                            = 0,
  parameter MEM_CONFIG                          = 0,
  parameter ERR_MODE                            = 0
)
(
  // Clock and asynchronous reset
   input wire                                    clk,
   input wire                                    rst_n,

  // High-active synchronous requests and Push data
   input wire                                    push,
   input wire                                    pop,
   input wire      [WIDTH-1:0]                   din,

  // Registered Pop response; dout_valid is a CBB extension to DW_stack.
   output reg      [WIDTH-1:0]                   dout,
   output reg                                    dout_valid,

  // Registered occupancy status
   output wire                                   empty,
   output wire                                   full,
   output wire                                   half_full,
  // DW-compatible underflow/overflow indication
   output wire                                   error
);

localparam ADDR_W                                = (DEPTH >= 2) ?
                                                   $clog2(DEPTH) : 1;

wire                                             pop_fire;
wire                                             we_n;
wire                                             mem_wr_en;
wire               [WIDTH-1:0]                   mem_rd_data;
wire               [$clog2(DEPTH)-1:0]           wr_addr;
wire               [$clog2(DEPTH)-1:0]           rd_addr;
reg                                              pop_pending_q;

assign mem_wr_en        = ~we_n;

// The controller independently owns the pointer, boundary, status and error duties of DW_stackctl.
CBB_STACK_CTRL
#(
.DEPTH                                 ( DEPTH                                 ),
.ERR_MODE                              ( ERR_MODE                              )
)
U_CBB_STACK_CTRL
(
.clk                                   ( clk                                   ),
.rst_n                                 ( rst_n                                 ),
.push                                  ( push                                  ),
.pop                                   ( pop                                   ),
.pop_fire                              ( pop_fire                              ),
.we_n                                  ( we_n                                  ),
.wr_addr                               ( wr_addr                               ),
.rd_addr                               ( rd_addr                               ),
.empty                                 ( empty                                 ),
.full                                  ( full                                  ),
.half_full                             ( half_full                             ),
.error                                 ( error                                 )
);


CBB_STACK_MEM
#(
.WIDTH                                 ( WIDTH                                 ),
.DEPTH                                 ( DEPTH                                 ),
.ADDR_W                                ( ADDR_W                                ),
.MEM_IMPL                              ( MEM_IMPL                              ),
.MEM_CONFIG                            ( MEM_CONFIG                            )
)
U_CBB_STACK_MEM
(
.clk                                   ( clk                                   ),
.wr_en                                 ( mem_wr_en                             ),
.wr_addr                               ( wr_addr                               ),
.wr_data                               ( din                                   ),
.rd_en                                 ( pop_fire                              ),
.rd_addr                               ( rd_addr                               ),
.rd_data                               ( mem_rd_data                           )
);


// Delay accepted Pop qualification by one cycle to align with memory data.
always @(posedge clk or negedge rst_n)
begin : POP_PENDING_PROC
  if (rst_n == 1'b0)
  begin
    pop_pending_q <= 1'b0;
  end
  else
  begin
    pop_pending_q <= pop_fire;
  end
end

// dout holds the most recent response when dout_valid is low.
always @(posedge clk or negedge rst_n)
begin : POP_RESPONSE_PROC
  if (rst_n == 1'b0)
  begin
    dout <= {WIDTH{1'b0}};
  end
  else
  begin
    if (pop_pending_q == 1'b1)
    begin
      dout <= mem_rd_data;
    end
  end
end

always @(posedge clk or negedge rst_n)
begin : POP_VALID_PROC
  if (rst_n == 1'b0)
  begin
    dout_valid <= 1'b0;
  end
  else
  begin
    dout_valid <= pop_pending_q;
  end
end


endmodule
`endif

// =====================================================================================================================
// Modification history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-07-28 | CBB Team     | Rewritten for the V0.1 synchronous-read architecture.
// V1.1         | 2026-07-30 | CBB Team     | Precomputed memory addresses to improve setup margin.
// V1.2         | 2026-08-21 | CBB Team     | Unified the clock port as clk and moved checks to TB.
// V1.3         | 2026-08-31 | CBB Team     | Split CBB_STACK_CTRL to form a DW_stack-style controller/storage hierarchy.
// V1.4         | 2026-11-03 | CBB Team     | Header template alignment: copyright, designer, project tag and non-template fields
// V1.5         | 2026-11-03 | CBB Team     | Move non-template header fields into the functional overview block
// =====================================================================================================================
