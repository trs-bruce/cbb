// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026/07/20
// Description  : Parameterized Async Event Counter with CDC + Freq/Interval Metrics
//                Dedicated counter for asynchronous pulse acquisition. Features:
//                - Toggle-handshake anti-loss front-end (event_in clocks a toggle FF,
// =====================================================================================================================

`ifndef CBB_CNT_EVENT_V
`define CBB_CNT_EVENT_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
//                Applications: interrupt stats, PMU, peripheral pulse acquisition.
// Limitation: toggle handshake requires event spacing >= synchronizer settling time
//             (2-3 dst clk cycles). Faster bursts will alias.
//                  dest-side XOR edge detect — captures any pulse >= 1 src cycle,
//                  no dead zone vs. naive edge-detect on async signal)
//                - 2/3-stage synchronizer chain for metastability-free CDC
//                - Event accumulation counter (q) with wrap-around
//                - Fixed-window frequency stat (freq): events per 2^WINDOW_WIDTH cycles
//                - Last-interval measure (interval): clk cycles between events
//                - Priority: rst_n > event_pulse
// ---------------------------------------------------------------------------------------------------------------------
module CBB_CNT_EVENT
   #(
   parameter WIDTH                               = 8,                          // Event cnt width (>=2)
   parameter SYNC_STAGES                         = 2,                          // Sync stages (2/3)
   parameter WINDOW_WIDTH                        = 16,                         // Freq window width (>=2)
   parameter INTERVAL_WIDTH                      = 16                          // Interval width (>=2)
    )
    (
   input                                         clk,                          // System clock
   input                                         rst_n,                        // Async reset, low
   input                                         event_in,                     // Async event input
   output          [WIDTH-1:0]                   q,                            // Event counter
   output          [WINDOW_WIDTH-1:0]            freq,                         // Events per window
   output          [INTERVAL_WIDTH-1:0]          interval                      // Last event interval
    );

// ---------------------------------------------------------------------------------------------------------------------
// Constant Parameter
// ---------------------------------------------------------------------------------------------------------------------
localparam         [WIDTH-1:0]                   CNT_MAX   = {WIDTH{1'b1}};              // Event cnt max
localparam         [WINDOW_WIDTH-1:0]            WIN_MAX   = {WINDOW_WIDTH{1'b1}};       // Window cnt max
localparam         [INTERVAL_WIDTH-1:0]          INT_MAX   = {INTERVAL_WIDTH{1'b1}};     // Interval cnt max

// ---------------------------------------------------------------------------------------------------------------------
// Anti-loss Toggle Handshake (source side)
//   event_in directly clocks a toggle FF. Each event_in rising edge flips toggle_src.
//   This eliminates dead-zone of edge-detect on async signal — any pulse wider than
//   the dst synchronizer settling time (2-3 clk) is captured.
//   Note: event_in must be clean (no glitches); if from external pad, debounce first.
// ---------------------------------------------------------------------------------------------------------------------
reg                                              toggle_src;                                              // Source toggle flag

always @(posedge event_in or negedge rst_n)
begin : TOGGLE_SRC_PROC
  if (rst_n == 1'b0)
    toggle_src          <= 1'b0;
  else
    toggle_src          <= ~toggle_src;
end

// ---------------------------------------------------------------------------------------------------------------------
// Synchronizer Stage 1 (first CDC flop, captures toggle_src)
//   MTBF-critical: dedicated always block, no combinational logic on reset path.
// ---------------------------------------------------------------------------------------------------------------------
reg                                              sync_meta1;                                              // Sync stage 1
reg                                              sync_meta2;                                              // Sync stage 2
wire                                             sync_final;                                              // Final sync signal

always @(posedge clk or negedge rst_n)
begin : SYNC1_SEQ_PROC
  if (rst_n == 1'b0)
    sync_meta1          <= 1'b0;
  else
    sync_meta1          <= toggle_src;
end

// ---------------------------------------------------------------------------------------------------------------------
// Synchronizer Stage 2 (second CDC flop, resolves metastability)
//   Independent always block to keep each synchronizer reg clean.
// ---------------------------------------------------------------------------------------------------------------------
always @(posedge clk or negedge rst_n)
begin : SYNC2_SEQ_PROC
  if (rst_n == 1'b0)
    sync_meta2          <= 1'b0;
  else
    sync_meta2          <= sync_meta1;
end

// ---------------------------------------------------------------------------------------------------------------------
// Optional Synchronizer Stage 3 (extra MTBF for very high fmax designs)
//   Selected via SYNC_STAGES parameter. Each stage is an independent always block
//   so that reset does not get overridden by combinational logic.
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (SYNC_STAGES == 3) begin : GEN_SYNC_3STG
    reg                                          sync_meta3;                                          // Sync stage 3
    always @(posedge clk or negedge rst_n)
    begin : SYNC3_SEQ_PROC
      if (rst_n == 1'b0)
        sync_meta3       <= 1'b0;
      else
        sync_meta3       <= sync_meta2;
    end
    assign sync_final   = sync_meta3;
  end
  else begin : GEN_SYNC_2STG
    assign sync_final   = sync_meta2;
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Edge Detection (XOR-based for toggle handshake)
//   event_pulse fires for 1 clk cycle each time sync_final changes (either edge),
//   corresponding to one event_in rising edge at the source.
//   sync_q holds the previous synced toggle for XOR comparison.
//   Note: XOR (not AND-NOT) is required because toggle_src flips polarity each event.
// ---------------------------------------------------------------------------------------------------------------------
reg                                              sync_q;                                                  // Edge detect delay
wire                                             event_pulse;                                             // Event pulse

assign event_pulse      = sync_final ^ sync_q;

always @(posedge clk or negedge rst_n)
begin : EDGE_SEQ_PROC
  if (rst_n == 1'b0)
    sync_q               <= 1'b0;
  else
    sync_q               <= sync_final;
end

// ---------------------------------------------------------------------------------------------------------------------
// Event Accumulation Counter (priority: rst_n > event_pulse)
//   On event_pulse, q_reg increments by 1 and wraps around at CNT_MAX.
// ---------------------------------------------------------------------------------------------------------------------
reg                [WIDTH-1:0]                   q_reg;                                                   // Counter register

always @(posedge clk or negedge rst_n)
begin : CNT_SEQ_PROC
  if (rst_n == 1'b0)
  begin
    q_reg                <= {WIDTH{1'b0}};
  end
  else if (event_pulse == 1'b1)
  begin
    q_reg                <= q_reg + {{(WIDTH-1){1'b0}}, 1'b1};
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Frequency Statistics: Fixed Window
//   window_cnt free-runs 0..2^WINDOW_WIDTH-1, wraps to 0.
//   At wrap (window_cnt==WIN_MAX): latch event_cnt into freq_reg, reset event_cnt
//     to 0 (or 1 if an event fires on this same cycle).
//   Between wraps: increment event_cnt on each event_pulse.
//   freq holds the event count of the most recently completed window.
// ---------------------------------------------------------------------------------------------------------------------
reg                [WINDOW_WIDTH-1:0]            window_cnt;                                          // Window cycle cnt
reg                [WINDOW_WIDTH-1:0]            event_cnt;                                           // Events in window
reg                [WINDOW_WIDTH-1:0]            freq_reg;                                            // Latched freq

always @(posedge clk or negedge rst_n)
begin : FREQ_SEQ_PROC
  if (rst_n == 1'b0)
  begin
    window_cnt           <= {WINDOW_WIDTH{1'b0}};
    event_cnt            <= {WINDOW_WIDTH{1'b0}};
    freq_reg             <= {WINDOW_WIDTH{1'b0}};
  end
  else if (window_cnt == WIN_MAX)
  begin
    // Window boundary: latch current event_cnt, start new window
    freq_reg             <= event_cnt;
    event_cnt            <= (event_pulse == 1'b1)
    ? {{(WINDOW_WIDTH-1){1'b0}}, 1'b1}
    : {WINDOW_WIDTH{1'b0}};
    window_cnt           <= {WINDOW_WIDTH{1'b0}};
  end
  else
  begin
    window_cnt           <= window_cnt + {{(WINDOW_WIDTH-1){1'b0}}, 1'b1};
    if (event_pulse == 1'b1)
      event_cnt          <= event_cnt + {{(WINDOW_WIDTH-1){1'b0}}, 1'b1};
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Interval Measurement: Last Interval
//   cycle_cnt counts clk cycles since last event_pulse.
//   On event_pulse: latch cycle_cnt into interval_reg, reset cycle_cnt to 0.
//   Saturates at INT_MAX if no event for 2^INTERVAL_WIDTH cycles (prevents wrap
//   to 0 which would be misread as a real 0-cycle interval).
// ---------------------------------------------------------------------------------------------------------------------
reg                [INTERVAL_WIDTH-1:0]          cycle_cnt;                                           // Cycles since event
reg                [INTERVAL_WIDTH-1:0]          interval_reg;                                        // Last interval

always @(posedge clk or negedge rst_n)
begin : INT_SEQ_PROC
  if (rst_n == 1'b0)
  begin
    cycle_cnt            <= {INTERVAL_WIDTH{1'b0}};
    interval_reg         <= {INTERVAL_WIDTH{1'b0}};
  end
  else if (event_pulse == 1'b1)
  begin
    interval_reg         <= cycle_cnt;                                        // Capture interval
    cycle_cnt            <= {INTERVAL_WIDTH{1'b0}};                           // Reset
  end
  else if (cycle_cnt != INT_MAX)
  begin
    cycle_cnt            <= cycle_cnt + {{(INTERVAL_WIDTH-1){1'b0}}, 1'b1};
  end
end

// ---------------------------------------------------------------------------------------------------------------------
// Output Assign
// ---------------------------------------------------------------------------------------------------------------------
assign q                = q_reg;
assign freq             = freq_reg;
assign interval         = interval_reg;

endmodule
`endif
// =====================================================================================================================