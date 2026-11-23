// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : CBB Team
// Project      : cbb
// Create Date  : 2026/08/19
// Description  : Active-low reset input synchronizer with two-sided glitch filtering and debounce.
// =====================================================================================================================

`ifndef CBB_CRG_RSTDB_V
`define CBB_CRG_RSTDB_V

// ---------------------------------------------------------------------------------------------------------------------
// Functional overview
// ---------------------------------------------------------------------------------------------------------------------
// Module       : CBB_CRG_RSTDB
// Assumptions  : INPUT_MODE is 0 or 1, SYNC_STAGES >= 2, DEBOUNCE_CYCLES >= 1
// ---------------------------------------------------------------------------------------------------------------------
module CBB_CRG_RSTDB
  #(
   parameter integer INPUT_MODE                  = 1,                          // Input mode: 0 = synchronous, 1 = asynchronous
   parameter integer SYNC_STAGES                 = 2,                          // Synchronizer stages for asynchronous input
   parameter integer DEBOUNCE_CYCLES             = 16                          // Consecutive stable samples required for two-sided debounce
   )
   (
   input wire                                    clk,                          // Free-running sampling clock
   input wire                                    rst_n,                        // Module-local active-low reset
   input wire                                    rst_in_n,                     // Unsynchronized active-low reset input to be filtered
   output reg                                    rst_out_n                     // Filtered active-low reset request
   );

// ---------------------------------------------------------------------------------------------------------------------
// Constant parameters
// ---------------------------------------------------------------------------------------------------------------------
localparam integer                               CNT_WIDTH      = (DEBOUNCE_CYCLES > 1) ? $clog2(DEBOUNCE_CYCLES) : 1;
localparam         [CNT_WIDTH-1:0]               DEBOUNCE_LAST  = DEBOUNCE_CYCLES[CNT_WIDTH-1:0] - 1'b1;

// ---------------------------------------------------------------------------------------------------------------------
// Internal signal declarations
// ---------------------------------------------------------------------------------------------------------------------
wire                                             sampled_rst_n;


// ---------------------------------------------------------------------------------------------------------------------
// Input mode selection
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (INPUT_MODE == 0)
  begin : SYNC_INPUT_BRANCH
    assign sampled_rst_n     = rst_in_n;
  end
  else if (INPUT_MODE == 1)
  begin : ASYNC_INPUT_BRANCH
    CBB_CDC_LVL
    #(
    .STAGES                            ( SYNC_STAGES                           )
    )
    U_CBB_CDC_LVL
    (
    .clk_d                             ( clk                                   ),
    .rst_d_n                           ( rst_n                                 ),
    .init_d_n                          ( 1'b1                                  ),
    .data_s                            ( rst_in_n                              ),
    .test                              ( 1'b0                                  ),
    .data_d                            ( sampled_rst_n                         )
    );
  end
  else
  begin : INVALID_INPUT_BRANCH
    assign sampled_rst_n     = 1'b0;
  end
endgenerate

// ---------------------------------------------------------------------------------------------------------------------
// Debounce structure
// ---------------------------------------------------------------------------------------------------------------------
generate
  if (DEBOUNCE_CYCLES == 1)
  begin : SINGLE_SAMPLE_BRANCH
    always @(posedge clk or negedge rst_n)
    begin : RST_OUT_PROC
      if (rst_n == 1'b0)
      begin
        rst_out_n       <= 1'b0;
      end
      else
      begin
        rst_out_n       <= sampled_rst_n;
      end
    end
  end
  else
  begin : MULTI_SAMPLE_BRANCH
    wire                                         debounce_done;
    reg            [CNT_WIDTH-1:0]               stable_cnt;

    assign debounce_done     = (stable_cnt == DEBOUNCE_LAST);

    always @(posedge clk or negedge rst_n)
    begin : STABLE_CNT_PROC
      if (rst_n == 1'b0)
      begin
        stable_cnt      <= {CNT_WIDTH{1'b0}};
      end
      else if (sampled_rst_n == rst_out_n)
      begin
        stable_cnt      <= {CNT_WIDTH{1'b0}};
      end
      else if (debounce_done == 1'b1)
      begin
        stable_cnt      <= {CNT_WIDTH{1'b0}};
      end
      else
      begin
        stable_cnt      <= stable_cnt + 1'b1;
      end
    end

    always @(posedge clk or negedge rst_n)
    begin : RST_OUT_PROC
      if (rst_n == 1'b0)
      begin
        rst_out_n       <= 1'b0;
      end
      else if ((sampled_rst_n != rst_out_n) && (debounce_done == 1'b1))
      begin
        rst_out_n       <= sampled_rst_n;
      end
    end
  end
endgenerate

endmodule
`endif

// =====================================================================================================================
// Modified history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-09-18 | CBB Team     | Column alignment and comment/internal signal naming cleanup (no functional change)
// V1.1         | 2026-09-22 | CBB Team     | Alignment cleanup: always-block assignments to col 25, instantiation and bracket columns, header parameter/port indentation, begin on its own line (no functional change)
// V1.2         | 2026-11-03 | CBB Team     | Header template alignment: copyright, designer, project tag and non-template fields
// =====================================================================================================================
// End of file
// =====================================================================================================================
