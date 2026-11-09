// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026/07/20
// Description  : Parameterized Cascade Counter (Sync/Async Cascade)
//                Built from NUM_STAGES stages of STAGE_WIDTH-bit binary up-counters.
//                Total counter width = STAGE_WIDTH * NUM_STAGES.
//                Modes (CASCADE_MODE parameter):
//                - 0 (SYNC) : All stages share clk; low-stage carry enables next stage
//                - 1 (ASYNC): Stage 0 clocked by clk; stage i clocked by falling
//                              edge of stage (i-1) carry (ripple-carry style)
//                Wrap-around at per-stage MAX (no saturate mode).
// =====================================================================================================================

`ifndef CBB_CNT_CASCADE_V
`define CBB_CNT_CASCADE_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
//                Strict inter-stage timing handling: async mode uses falling-edge
//                carry to avoid half-period hazards. Carry signal is pure
//                (q==MAX) without en gating, preventing spurious carry on
//                en deassertion while a stage sits at MAX.
// ---------------------------------------------------------------------------------------------------------------------
module CBB_CNT_CASCADE
   #(
   parameter STAGE_WIDTH                         = 8,                          // Bits per stage
   parameter NUM_STAGES                          = 4,                          // Num stages
   parameter CASCADE_MODE                        = 0                           // 0:sync 1:async
    )
    (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset, low
   input                                         en,                           // Count enable
   output          [STAGE_WIDTH*NUM_STAGES-1:0]  q                             // Counter output
    );

// ---------------------------------------------------------------------------------------------------------------------
// Constant Parameter
// ---------------------------------------------------------------------------------------------------------------------
localparam         [STAGE_WIDTH-1:0]             STAGE_MAX      = {STAGE_WIDTH{1'b1}};   // Per-stage max
localparam                                       MODE_SYNC      = 1'b0;                  // Sync cascade
localparam                                       MODE_ASYNC     = 1'b1;                  // Async cascade

// ---------------------------------------------------------------------------------------------------------------------
// Internal Signals Declarations
// ---------------------------------------------------------------------------------------------------------------------
reg                [STAGE_WIDTH-1:0]             q_stage [0:NUM_STAGES-1];                               // Per-stage reg
wire               [NUM_STAGES-1:0]              en_stage;                                                  // Per-stage en
wire               [NUM_STAGES-1:0]              cout_stage;                                                // Per-stage carry

// ---------------------------------------------------------------------------------------------------------------------
// Per-stage Carry Logic (combinational)
//   Stage 0 enable : en_stage[0]   = en
//   Stage i enable : en_stage[i]   = en && (&cout_stage[i-1:0])   (sync mode only)
//   Stage i cout   : cout_stage[i] = (q_stage[i] == STAGE_MAX)
//   NOTE: sync mode must look at ALL lower stages, not just stage i-1. A lower
//         stage holds its cout high for 2^STAGE_WIDTH cycles while it drains, so
//         "cout_stage[i-1] only" lets higher stages keep counting inside that
//         window and shortens the wrap period. The AND reduction is literally
//         the carry into bit (i*STAGE_WIDTH) of the binary adder.
//   NOTE: en is NOT in cout_stage. In async mode, cout falling edge is the
//         stage clock; gating with en would cause spurious carry on en drop.
//   In async mode, en_stage[i] for i>0 is unused (stage clocked by carry edge)
// ---------------------------------------------------------------------------------------------------------------------
genvar i;
generate
  for (i = 0; i < NUM_STAGES; i = i + 1) begin : STAGE_GEN_LOOP
    if (i == 0) begin : STAGE0_GEN
      assign en_stage[0]     = en;
      assign cout_stage[0]   = (q_stage[0] == STAGE_MAX) ? 1'b1 : 1'b0;
    end
    else begin : STAGE_N_GEN
      if (CASCADE_MODE == MODE_SYNC) begin : SYNC_EN_GEN
        assign en_stage[i]   = ((en == 1'b1) && ((&cout_stage[i-1:0]) == 1'b1)) ? 1'b1 : 1'b0;
      end
      else begin : ASYNC_EN_GEN
        assign en_stage[i]   = ((en == 1'b1) && (cout_stage[i-1] == 1'b1)) ? 1'b1 : 1'b0;
      end
      assign cout_stage[i]   = (q_stage[i] == STAGE_MAX) ? 1'b1 : 1'b0;
    end
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Per-stage Counter Register
//   SYNC mode (CASCADE_MODE=0):
//     All stages clocked by posedge clk.
//     Stage i updates when en_stage[i]=1, wraps at STAGE_MAX.
//   ASYNC mode (CASCADE_MODE=1):
//     Stage 0 clocked by posedge clk (enabled by en).
//     Stage i (i>0) clocked by negedge cout_stage[i-1] (falling carry = 1->0).
//     Falling-edge trigger avoids half-period hazard and matches ripple principle.
//     Carry = (q==MAX) without en: en drop while q==MAX does not trigger carry.
// ---------------------------------------------------------------------------------------------------------------------
generate
  for (i = 0; i < NUM_STAGES; i = i + 1) begin : STAGE_REG_GEN_LOOP
    if (CASCADE_MODE == MODE_SYNC) begin : SYNC_GEN
      always @(posedge clk or negedge rst_n)
      begin : SYNC_STAGE_PROC
        if (rst_n == 1'b0)
          q_stage[i]        <= {STAGE_WIDTH{1'b0}};
        else if (en_stage[i] == 1'b1)
          q_stage[i]        <= (q_stage[i] == STAGE_MAX) ? {STAGE_WIDTH{1'b0}} :
          (q_stage[i] + 1'b1);
      end
    end
    else begin : ASYNC_GEN
      if (i == 0) begin : ASYNC_STG0_GEN
        always @(posedge clk or negedge rst_n)
        begin : ASYNC_STG0_PROC
          if (rst_n == 1'b0)
            q_stage[0]      <= {STAGE_WIDTH{1'b0}};
          else if (en == 1'b1)
            q_stage[0]      <= (q_stage[0] == STAGE_MAX) ? {STAGE_WIDTH{1'b0}} :
            (q_stage[0] + 1'b1);
        end
      end
      else begin : ASYNC_STGN_GEN
        always @(negedge cout_stage[i-1] or negedge rst_n)
        begin : ASYNC_STGN_PROC
          if (rst_n == 1'b0)
            q_stage[i]      <= {STAGE_WIDTH{1'b0}};
          else
            q_stage[i]      <= (q_stage[i] == STAGE_MAX) ? {STAGE_WIDTH{1'b0}} :
            (q_stage[i] + 1'b1);
        end
      end
    end
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Output Aggregation
//   q : concatenated stages (stage 0 = LSB side)
// ---------------------------------------------------------------------------------------------------------------------
genvar j;
generate
  for (j = 0; j < NUM_STAGES; j = j + 1) begin : Q_GEN_LOOP
    assign q[j*STAGE_WIDTH +: STAGE_WIDTH]  = q_stage[j];
  end
endgenerate

endmodule
`endif
// =====================================================================================================================