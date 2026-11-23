// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026/08/31
// Description  : Dedicated synchronous dual-port RAM wrapper for CBB_STACK.
// NOTE         : Foundry hard-macro model names and library corner names are replaced by neutral
//               placeholders for public distribution. Bind the memory-compiler output of your own
//               process at the placeholder instance, and re-check the fixed tie-off values against
//               your macro databook.
// =====================================================================================================================

`ifndef CBB_STACK_MEM_V
`define CBB_STACK_MEM_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
// Clock       : clk, active high
// Reset       : none; memory contents and read data are undefined before a legal read
// Latency     : rd_data is valid one cycle after rd_en is sampled
// Assumptions : The stack controller never asserts wr_en and rd_en in the same cycle
//               TSMC_12 uses 64x4 dual-port hard macros sliced by width and banked by depth
//               DEPTH is 2..256 and WIDTH is 1..256
// ---------------------------------------------------------------------------------------------------------------------
module CBB_STACK_MEM
#(
  parameter WIDTH                               = 8,
  parameter DEPTH                               = 16,
  parameter ADDR_W                              = 4,
  parameter MEM_IMPL                            = 0,
  parameter MEM_CONFIG                          = 0
)
(
   input wire                                    clk,

  // Independent write port; shares the array with the read port but address and enable are fully separate.
   input wire                                    wr_en,
   input wire      [ADDR_W-1:0]                  wr_addr,
   input wire      [WIDTH-1:0]                   wr_data,

  // Independent synchronous read port; rd_data returns one cycle after an accepted read.
   input wire                                    rd_en,
   input wire      [ADDR_W-1:0]                  rd_addr,
   output wire     [WIDTH-1:0]                   rd_data
);

localparam         [ADDR_W:0]                    DEPTH_VALUE         = DEPTH;
localparam         [ADDR_W:0]                    ADDRESS_SPACE_SIZE  =
                                                                       {1'b1, {ADDR_W{1'b0}}};

wire                                             rd_addr_valid;
wire                                             wr_addr_valid;

// Address encodings beyond DEPTH (non-power-of-two depths) are blocked from accessing the array.
generate
  if (DEPTH_VALUE == ADDRESS_SPACE_SIZE)
  begin : FULL_ADDRESS_SPACE_BRANCH
    assign rd_addr_valid     = 1'b1;
    assign wr_addr_valid     = 1'b1;
  end
  else
  begin : PARTIAL_ADDRESS_SPACE_BRANCH
    wire           [ADDR_W:0]                    rd_addr_extend;
    wire           [ADDR_W:0]                    wr_addr_extend;

    assign rd_addr_extend    = {1'b0, rd_addr};
    assign wr_addr_extend    = {1'b0, wr_addr};
    assign rd_addr_valid     = (rd_addr_extend < DEPTH_VALUE);
    assign wr_addr_valid     = (wr_addr_extend < DEPTH_VALUE);
  end
endgenerate

`ifdef TSMC_12
localparam TSMC_MACRO_DEPTH                      = 64;
localparam TSMC_MACRO_WIDTH                      = 4;
localparam TSMC_ADDR_W                           = 6;
localparam TSMC_WIDTH_SLICE_COUNT                =
                                                   (WIDTH + TSMC_MACRO_WIDTH - 1) / TSMC_MACRO_WIDTH;
localparam TSMC_PAD_WIDTH                        =
                                                   TSMC_WIDTH_SLICE_COUNT * TSMC_MACRO_WIDTH;
localparam TSMC_DEPTH_BANK_COUNT                 =
                                                   (DEPTH + TSMC_MACRO_DEPTH - 1) / TSMC_MACRO_DEPTH;

wire                                             mem_rd_en;
wire                                             mem_wr_en;
wire               [7:0]                         rd_addr_extend;
wire               [7:0]                         wr_addr_extend;
wire               [1:0]                         rd_bank_select;
wire               [1:0]                         wr_bank_select;
wire               [TSMC_ADDR_W-1:0]             macro_rd_addr;
wire               [TSMC_ADDR_W-1:0]             macro_wr_addr;
wire               [TSMC_PAD_WIDTH-1:0]          macro_wr_data_padded;
wire [TSMC_PAD_WIDTH-1:0]                          macro_rd_data_by_bank
[0:TSMC_DEPTH_BANK_COUNT-1];
reg                [1:0]                         rd_bank_select_q;
wire               [TSMC_PAD_WIDTH-1:0]          macro_rd_data_selected;

assign mem_rd_en                  = (rd_en == 1'b1) &&
                                    (rd_addr_valid == 1'b1);
assign mem_wr_en                  = (wr_en == 1'b1) &&
                                    (wr_addr_valid == 1'b1);
assign rd_addr_extend             = {{(8-ADDR_W){1'b0}}, rd_addr};
assign wr_addr_extend             = {{(8-ADDR_W){1'b0}}, wr_addr};
assign rd_bank_select             = rd_addr_extend[7:6];
assign wr_bank_select             = wr_addr_extend[7:6];
assign macro_rd_addr              = rd_addr_extend[5:0];
assign macro_wr_addr              = wr_addr_extend[5:0];
assign macro_wr_data_padded       =
                                    {{(TSMC_PAD_WIDTH-WIDTH){1'b0}}, wr_data};

// Macro output is synchronous read data; the requested bank is registered to select the matching QB in the return cycle.
always @(posedge clk)
begin : READ_BANK_SELECT_PROC
  if (mem_rd_en == 1'b1)
  begin
    rd_bank_select_q <= rd_bank_select;
  end
end

generate
  if (TSMC_DEPTH_BANK_COUNT == 1)
  begin : ONE_READ_BANK_MUX_BRANCH
    assign macro_rd_data_selected = macro_rd_data_by_bank[0];
  end
  else if (TSMC_DEPTH_BANK_COUNT == 2)
  begin : TWO_READ_BANK_MUX_BRANCH
    assign macro_rd_data_selected = (rd_bank_select_q == 2'd0) ?
                                    macro_rd_data_by_bank[0] :
                                    macro_rd_data_by_bank[1];
  end
  else if (TSMC_DEPTH_BANK_COUNT == 3)
  begin : THREE_READ_BANK_MUX_BRANCH
    assign macro_rd_data_selected = (rd_bank_select_q == 2'd0) ?
                                    macro_rd_data_by_bank[0] :
                                    (rd_bank_select_q == 2'd1) ?
                                    macro_rd_data_by_bank[1] :
                                    macro_rd_data_by_bank[2];
  end
  else
  begin : FOUR_READ_BANK_MUX_BRANCH
    assign macro_rd_data_selected = (rd_bank_select_q == 2'd0) ?
                                    macro_rd_data_by_bank[0] :
                                    (rd_bank_select_q == 2'd1) ?
                                    macro_rd_data_by_bank[1] :
                                    (rd_bank_select_q == 2'd2) ?
                                    macro_rd_data_by_bank[2] :
                                    macro_rd_data_by_bank[3];
  end
endgenerate

genvar depth_bank_index;
genvar width_slice_index;
generate
  for (depth_bank_index = 0;
  depth_bank_index < TSMC_DEPTH_BANK_COUNT;
  depth_bank_index = depth_bank_index + 1)
  begin : TSMC_DEPTH_BANK_LOOP
    wire                                         bank_rd_en;
    wire                                         bank_wr_en;
    wire                                         macro_ceba_n;
    wire                                         macro_cebb_n;

    assign bank_rd_en   = mem_rd_en &&
                          (rd_bank_select == depth_bank_index);
    assign bank_wr_en   = mem_wr_en &&
                          (wr_bank_select == depth_bank_index);
    assign macro_ceba_n = ~bank_wr_en;
    assign macro_cebb_n = ~bank_rd_en;

    for (width_slice_index = 0;
    width_slice_index < TSMC_WIDTH_SLICE_COUNT;
    width_slice_index = width_slice_index + 1)
    begin : TSMC_WIDTH_SLICE_LOOP
      wire         [TSMC_MACRO_WIDTH-1:0]        macro_wr_data;
      wire         [TSMC_MACRO_WIDTH-1:0]        macro_rd_data;
      wire         [TSMC_MACRO_WIDTH-1:0]        unused_port_a_data;
      wire                                       unused_power_up_delay;

      assign macro_wr_data   =
                               macro_wr_data_padded[(width_slice_index*TSMC_MACRO_WIDTH) +:
                               TSMC_MACRO_WIDTH];
      assign macro_rd_data_by_bank[depth_bank_index]
      [(width_slice_index*TSMC_MACRO_WIDTH) +: TSMC_MACRO_WIDTH] =
      macro_rd_data;

      // Port A is fixed as the write port and Port B as the read port; controls are active-low.
      CBB_SRAM_64X4_DP U_TSMC12_STACK_MEM
      (
      .SLP                             ( 1'b0                                  ),
      .DSLP                            ( 1'b0                                  ),
      .SD                              ( 1'b0                                  ),
      .PUDELAY                         ( unused_power_up_delay                 ),
      .WTSEL                           ( 2'b01                                 ),
      .RTSEL                           ( 2'b01                                 ),
      .AA                              ( macro_wr_addr                         ),
      .DA                              ( macro_wr_data                         ),
      .BWEBA                           ( 4'b0000                               ),
      .WEBA                            ( 1'b0                                  ),
      .CEBA                            ( macro_ceba_n                          ),
      .CLKA                            ( clk                                   ),
      .AB                              ( macro_rd_addr                         ),
      .DB                              ( 4'b0000                               ),
      .BWEBB                           ( 4'b1111                               ),
      .WEBB                            ( 1'b1                                  ),
      .CEBB                            ( macro_cebb_n                          ),
      .CLKB                            ( clk                                   ),
      .AMA                             ( 6'b000000                             ),
      .DMA                             ( 4'b0000                               ),
      .BWEBMA                          ( 4'b1111                               ),
      .WEBMA                           ( 1'b1                                  ),
      .CEBMA                           ( 1'b1                                  ),
      .AMB                             ( 6'b000000                             ),
      .DMB                             ( 4'b0000                               ),
      .BWEBMB                          ( 4'b1111                               ),
      .WEBMB                           ( 1'b1                                  ),
      .CEBMB                           ( 1'b1                                  ),
      .BIST                            ( 1'b0                                  ),
      .CLKM                            ( clk                                   ),
      .QA                              ( unused_port_a_data                    ),
      .QB                              ( macro_rd_data                         )
      );
    end
  end
endgenerate

assign rd_data          = macro_rd_data_selected[WIDTH-1:0];

`else
`ifdef FPGA_XILINX
(* ram_style = "block" *)
`elsif FPGA_ALTERA
(* ramstyle = "M10K" *)
`endif
reg                [WIDTH-1:0]                   stack_mem [0:DEPTH-1];
reg                [WIDTH-1:0]                   rd_data_q;

// Portable branch uses independent read/write ports; same-address read returns the pre-write value.
always @(posedge clk)
begin : DUAL_PORT_MEMORY_ACCESS_PROC
  if ((rd_en == 1'b1) && (rd_addr_valid == 1'b1))
  begin
    rd_data_q <= stack_mem[rd_addr];
  end
end

always @(posedge clk)
begin : WRITE_MEMORY_PROC
  if ((wr_en == 1'b1) && (wr_addr_valid == 1'b1))
  begin
    stack_mem[wr_addr] <= wr_data;
  end
end

assign rd_data          = rd_data_q;
`endif

endmodule
`endif

// =====================================================================================================================
// Modification history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-08-31 | CBB Team     | Replaced the single-port address-multiplexed adapter with an independent read/write dual-port RAM.
// V1.1         | 2026-09-01 | CBB Team     | Integrated TSMC 64x4 dual-port hard macros with width/depth banking.
// V1.2         | 2026-11-03 | CBB Team     | Header template alignment: copyright, designer, project tag and non-template fields
// V1.3         | 2026-11-03 | CBB Team     | Move non-template header fields into the functional overview block
// =====================================================================================================================
