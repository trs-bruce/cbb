// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// Project      : CBB
// Create Date  : 2026/07/23
// Description  : Universal Sequential CRC Generator/Checker (DW_crc_s compatible)
//                Supports parameterized CRC polynomial up to 64-bit, configurable data width (1~POLY_SIZE),
//                CRC initialization & insertion inversion (CRC_CFG 0~7), bit & byte ordering (BIT_ORDER 0~3),
//                context switching (crc_out + crc_in/ld_crc_n), and stall (enable=0).
// =====================================================================================================================

`ifndef CBB_CRC_S_V
`define CBB_CRC_S_V
module CBB_CRC_S
   #(
    parameter DATA_WIDTH                          = 16,                         // Data width per cycle (1 ~ POLY_SIZE)
    parameter POLY_SIZE                           = 16,                         // CRC polynomial width (2 ~ 64)
    parameter CRC_CFG                             = 7,                          // Init[0] & Invert[2:1] config (0 ~ 7)
    parameter BIT_ORDER                           = 3,                          // Bit & byte order config (0 ~ 3)
    parameter POLY_COEF0                          = 4129,                       // Polynomial coefficient bits [15:0]
    parameter POLY_COEF1                          = 0,                          // Polynomial coefficient bits [31:16]
    parameter POLY_COEF2                          = 0,                          // Polynomial coefficient bits [47:32]
    parameter POLY_COEF3                          = 0                           // Polynomial coefficient bits [63:48]
    )
    (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset (active low)
   input                                         init_n,                       // Sync init (active low)
   input                                         enable,                       // Module enable (active high)
   input                                         drain,                        // CRC drain control (active high)
   input                                         ld_crc_n,                     // CRC register load (active low)
   input           [DATA_WIDTH-1:0]              data_in,                      // Input data
   input           [POLY_SIZE-1:0]               crc_in,                       // External CRC input for load
   output reg                                    draining,                     // Drain active indicator (reg out)
   output reg                                    drain_done,                   // Drain complete pulse (reg out)
   output reg                                    crc_ok,                       // CRC check result (reg out)
   output reg      [DATA_WIDTH-1:0]              data_out,                     // Output data (reg out)
   output reg      [POLY_SIZE-1:0]               crc_out                       // CRC register monitor (reg out)
    );

// ---------------------------------------------------------------------------------------------------------------------
// Constant Parameter
// ---------------------------------------------------------------------------------------------------------------------
localparam S_IDLE                                = 2'b00;                      // Idle / after init
localparam S_CALC                                = 2'b01;                      // CRC calculation active
localparam S_DRAIN                               = 2'b10;                      // CRC drain active

localparam DRAIN_CYCLES                          = POLY_SIZE / DATA_WIDTH;
localparam DRAIN_CNT_WIDTH                       = clog2(DRAIN_CYCLES + 1);

localparam         [63:0]                        POLY_FULL = {POLY_COEF3[15:0],
                                                             POLY_COEF2[15:0],
                                                             POLY_COEF1[15:0],
                                                             POLY_COEF0[15:0]};

localparam                                       POLY_INIT_ZERO = CRC_CFG[0] == 1'b0;
localparam         [1:0]                         INV_MODE       = CRC_CFG[2:1];

// Check constant: CRC of POLY_SIZE zero bits starting from init value
localparam         [POLY_SIZE-1:0]               CHK_CONST = POLY_INIT_ZERO
                                                             ? {POLY_SIZE{1'b0}}
                                                             : calc_chk_const(POLY_FULL);

// Initial CRC register value
localparam         [POLY_SIZE-1:0]               INIT_VAL  = POLY_INIT_ZERO
                                                             ? {POLY_SIZE{1'b0}}
                                                             : {POLY_SIZE{1'b1}};

// ---------------------------------------------------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------------------------------------------------
function integer clog2;
  input integer                                 val;
  integer i;
  begin
    clog2 = 1;
    for (i = 0; i < 32; i = i + 1)
    begin
      if (2**i >= val)
      begin
        clog2 = (i == 0) ? 1 : i;
        i = 32;
      end
    end
  end
endfunction

function [POLY_SIZE-1:0] calc_chk_const;
  input           [63:0]                        poly_full;
  reg              [POLY_SIZE-1:0]               crc_val;
  reg              [POLY_SIZE-1:0]               crc_temp;
  reg                                            feedback;
  integer                b;
  integer                s;
  begin
    crc_val = {POLY_SIZE{1'b1}};
    for (b = 0; b < POLY_SIZE; b = b + 1)
    begin
      feedback   = crc_val[POLY_SIZE-1];
      crc_temp   = crc_val;
      crc_temp[0] = feedback;
      for (s = 1; s < POLY_SIZE; s = s + 1)
      begin
        if (poly_full[s] == 1'b1)
          crc_temp[s] = crc_val[s-1] ^ feedback;
        else
          crc_temp[s] = crc_val[s-1];
      end
      crc_val = crc_temp;
    end
    calc_chk_const = crc_val;
  end
endfunction

function [DATA_WIDTH-1:0] reorder_data;
  input           [DATA_WIDTH-1:0]              din;
  integer                i;
  integer                j;
  begin
    case (BIT_ORDER)
      0:    reorder_data = din;
      1:
      begin
        for (i = 0; i < DATA_WIDTH; i = i + 1)
        reorder_data[i] = din[DATA_WIDTH-1-i];
      end
      2:
      begin
        for (i = 0; i < DATA_WIDTH/8; i = i + 1)
        reorder_data[i*8+:8] = din[(DATA_WIDTH/8-1-i)*8+:8];
      end
      3:
      begin
        for (i = 0; i < DATA_WIDTH/8; i = i + 1)
        begin
          for (j = 0; j < 8; j = j + 1)
          reorder_data[i*8+j] = din[i*8+7-j];
        end
      end
      default: reorder_data = din;
    endcase
  end
endfunction

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
// FSM
reg                [1:0]                         curr_st;
reg                [1:0]                         next_st;

// Drain counter
reg                [DRAIN_CNT_WIDTH-1:0]         drain_cnt;

// Drain-used flag: set when drain asserted, cleared on init_n
reg                                              drain_used;

// Bit-reordered input data
wire               [DATA_WIDTH-1:0]              data_in_reordered;

// CRC feedback array: intermediate CRC values for each parallel step
wire               [POLY_SIZE-1:0]               crc_step [0:DATA_WIDTH];

// Next CRC value from feedback array
wire               [POLY_SIZE-1:0]               crc_next;

// Invert mask: applied to full CRC value during drain
wire               [POLY_SIZE-1:0]               invert_mask;

// Inverted CRC for drain output
wire               [POLY_SIZE-1:0]               crc_inverted;

// Raw drain word selected from inverted CRC
wire               [DATA_WIDTH-1:0]              drain_word_raw;

// Final drain word after bit/byte reordering
wire               [DATA_WIDTH-1:0]              drain_word_final;

// CRC feedback signals for each parallel step
wire               [0:DATA_WIDTH-1]              crc_feedback;

// Drain done condition (combinational)
wire                                             drain_last;

// ---------------------------------------------------------------------------------------------------------------------
// Invert Mask Generation
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (INV_MODE == 2'b00)
  begin : INV_NONE
    assign invert_mask  = {POLY_SIZE{1'b0}};
  end
  else if (INV_MODE == 2'b01)
  begin : INV_ODD
    assign invert_mask  = {{(POLY_SIZE+1)/2{2'b01}}};
  end
  else if (INV_MODE == 2'b10)
  begin : INV_EVEN
    assign invert_mask  = {{(POLY_SIZE+1)/2{2'b10}}};
  end
  else
  begin : INV_ALL
    assign invert_mask  = {POLY_SIZE{1'b1}};
  end
endgenerate

// Inverted CRC register value
assign crc_inverted          = crc_out ^ invert_mask;

// ---------------------------------------------------------------------------------------------------------------------
// Bit Reorder for data_in
// ---------------------------------------------------------------------------------------------------------------------
assign data_in_reordered     = reorder_data(data_in);

// ---------------------------------------------------------------------------------------------------------------------
// CRC Feedback Array: Parallel LFSR for DATA_WIDTH bits per cycle
// ---------------------------------------------------------------------------------------------------------------------
assign crc_step[0]           = crc_out;
assign crc_next              = crc_step[DATA_WIDTH];

genvar sd;
generate
  for (sd = 0; sd < DATA_WIDTH; sd = sd + 1)
  begin : CRC_STEP_LOOP
    assign crc_feedback[sd]       = data_in_reordered[sd] ^ crc_step[sd][POLY_SIZE-1];

    // Bit 0: feedback always goes to LSB (x^0 = 1 is always present)
    assign crc_step[sd+1][0]      = crc_feedback[sd];

    genvar bi;
    for (bi = 1; bi < POLY_SIZE; bi = bi + 1)
    begin : CRC_BIT_LOOP
      assign crc_step[sd+1][bi]   = crc_step[sd][bi-1] ^ (POLY_FULL[bi] & crc_feedback[sd]);
    end
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Drain Word Selection and Reordering
// ---------------------------------------------------------------------------------------------------------------------
// Word-level selection: MSB-first or LSB-first based on BIT_ORDER[0]
assign drain_word_raw   = (BIT_ORDER[0] == 1'b0)
                          ? crc_inverted[POLY_SIZE-1 - drain_cnt*DATA_WIDTH -: DATA_WIDTH]
                          : crc_inverted[drain_cnt*DATA_WIDTH +: DATA_WIDTH];

// Apply bit/byte reordering to drain word
assign drain_word_final = reorder_data(drain_word_raw);

// Drain last word condition (drain_cnt tracks words already output; 1 after transition)
assign drain_last       = (curr_st == S_DRAIN) && (drain_cnt >= DRAIN_CYCLES) && (enable == 1'b1);

// ---------------------------------------------------------------------------------------------------------------------
// FSM: Sequential State Register
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : FSM_SEQ_PROC
  if (rst_n == 1'b0)
    curr_st             <= S_IDLE;
  else if (init_n == 1'b0)
    curr_st             <= S_IDLE;
  else
    curr_st             <= next_st;
end

// ---------------------------------------------------------------------------------------------------------------------
// FSM: Combinational Next State Logic
// ---------------------------------------------------------------------------------------------------------------------
always @*
begin : FSM_COMB_PROC
  next_st               = curr_st;
  case (curr_st)
    S_IDLE:
    begin
      if (enable == 1'b1 && ld_crc_n == 1'b1)
      begin
        if (drain == 1'b1)
          next_st       = S_DRAIN;
        else
          next_st       = S_CALC;
      end
    end
    S_CALC:
    begin
      if (enable == 1'b1 && drain == 1'b1)
        next_st         = S_DRAIN;
    end
    S_DRAIN:
    begin
      if (drain_last == 1'b1)
        next_st         = S_IDLE;
    end
    default:
    begin
      next_st           = S_IDLE;
    end
  endcase
end

// ---------------------------------------------------------------------------------------------------------------------
// CRC Register (also drives crc_out)
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : CRC_REG_PROC
  if (rst_n == 1'b0)
    crc_out             <= INIT_VAL;
  else if (init_n == 1'b0)
    crc_out             <= INIT_VAL;
  else if (enable == 1'b0)
    crc_out             <= crc_out;
  else if (ld_crc_n == 1'b0)
    crc_out             <= crc_in;
  else if (next_st == S_DRAIN || curr_st == S_DRAIN)
    crc_out             <= crc_out;
  else
    crc_out             <= crc_next;
end

// ---------------------------------------------------------------------------------------------------------------------
// Drain Counter
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : DRAIN_CNT_PROC
  if (rst_n == 1'b0)
    drain_cnt           <= {DRAIN_CNT_WIDTH{1'b0}};
  else if (init_n == 1'b0)
    drain_cnt           <= {DRAIN_CNT_WIDTH{1'b0}};
  else if (enable == 1'b0)
    drain_cnt           <= drain_cnt;
  else if (curr_st == S_CALC && drain == 1'b1)
    drain_cnt           <= {{DRAIN_CNT_WIDTH-1{1'b0}}, 1'b1};
  else if (curr_st == S_IDLE && drain == 1'b1 && ld_crc_n == 1'b1)
    drain_cnt           <= {DRAIN_CNT_WIDTH{1'b0}};
  else if (curr_st == S_DRAIN)
  begin
    if (drain_last == 1'b1)
      drain_cnt         <= {DRAIN_CNT_WIDTH{1'b0}};
    else
      drain_cnt         <= drain_cnt + 1'b1;
  end
  else
    drain_cnt           <= {DRAIN_CNT_WIDTH{1'b0}};
end

// ---------------------------------------------------------------------------------------------------------------------
// Drain-Used Flag: Set when drain is asserted, cleared on init_n
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : DRAIN_USED_PROC
  if (rst_n == 1'b0)
    drain_used          <= 1'b0;
  else if (init_n == 1'b0)
    drain_used          <= 1'b0;
  else if (enable == 1'b1 && drain == 1'b1)
    drain_used          <= 1'b1;
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Register: data_out
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : DATA_OUT_PROC
  if (rst_n == 1'b0)
    data_out            <= {DATA_WIDTH{1'b0}};
  else if (init_n == 1'b0)
    data_out            <= {DATA_WIDTH{1'b0}};
  else if (enable == 1'b0)
    data_out            <= data_out;
  else if (curr_st == S_CALC && drain == 1'b1)
    data_out            <= drain_word_final;
  else if (curr_st == S_DRAIN && drain_last == 1'b0)
    data_out            <= drain_word_final;
  else
    data_out            <= data_in;
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Register: draining
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : DRAINING_PROC
  if (rst_n == 1'b0)
    draining            <= 1'b0;
  else if (init_n == 1'b0)
    draining            <= 1'b0;
  else if (enable == 1'b0)
    draining            <= draining;
  else if (next_st == S_DRAIN)
    draining            <= 1'b1;
  else if (next_st == S_IDLE && curr_st == S_DRAIN)
    draining            <= 1'b0;
  else
    draining            <= draining;
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Register: drain_done (single-cycle pulse)
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : DRAIN_DONE_PROC
  if (rst_n == 1'b0)
    drain_done          <= 1'b0;
  else if (init_n == 1'b0)
    drain_done          <= 1'b0;
  else if (curr_st == S_DRAIN && drain_last == 1'b1 && enable == 1'b1)
    drain_done          <= 1'b1;
  else
    drain_done          <= 1'b0;
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Register: crc_ok
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : CRC_OK_PROC
  if (rst_n == 1'b0)
    crc_ok              <= 1'b0;
  else if (init_n == 1'b0)
    crc_ok              <= 1'b0;
  else if (enable == 1'b0)
    crc_ok              <= crc_ok;
  else if (drain_used == 1'b1)
    crc_ok              <= 1'b0;
  else
    crc_ok              <= (crc_next == CHK_CONST);
end

endmodule
`endif
// =====================================================================================================================
// Modified history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-07-23 | // Project      : CBB | Initial version
// =====================================================================================================================
