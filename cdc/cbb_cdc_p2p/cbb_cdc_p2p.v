// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer     : -
// Project      : CBB
// Create Date  : 2026/07/28
// Description  : Point-to-Point Pulse Synchronizer (CBB_CDC_P2P)
//                Pulse in src -> toggle -> sync -> pulse in dst.
//                Technology selection via macros (see cbb_cdc_define.v).
//                Port naming follows Synopsys DWBB convention:
//                clk_s/rst_s_n/init_s_n/event_s, clk_d/rst_d_n/init_d_n/event_d, test.
// =====================================================================================================================
`ifndef CBB_CDC_P2P_V
`define CBB_CDC_P2P_V
`include "cbb_cdc_define.v"

module CBB_CDC_P2P
    #(
    parameter integer STAGES                      = 2,                          // Number of sync stages (>= 2)
    parameter integer SLOW2FAST                   = 1,                          // 1: slow-to-fast (default); 0: fast-to-slow
    parameter integer PULSE_EXT                   = 4                           // fast-to-slow: min stretched pulse width in clk_s cycles
    )
    (
   input wire                                    clk_s,                        // Source clock
   input wire                                    rst_s_n,                      // Async reset, source domain (active low)
   input wire                                    init_s_n,                     // Sync reset, source domain (active low)
   input wire                                    event_s,                      // Source domain pulse
   input wire                                    clk_d,                        // Destination clock
   input wire                                    rst_d_n,                      // Async reset, destination domain (active low)
   input wire                                    init_d_n,                     // Sync reset, destination domain (active low)
   output wire                                   event_d,                      // Destination domain pulse
   input wire                                    test                          // Test mode enable
    );

// synopsys translate_off
initial begin : PARAM_CHECK_PROC
  if (STAGES < 2)
    $error("STAGES must be >= 2 (actual: %0d)", STAGES);
  if ((SLOW2FAST != 0) && (SLOW2FAST != 1))
    $error("SLOW2FAST must be 0 or 1 (actual: %0d)", SLOW2FAST);
  if ((PULSE_EXT < 1) || (PULSE_EXT > 255))
    $error("PULSE_EXT must be in [1, 255] (actual: %0d)", PULSE_EXT);
end
// synopsys translate_on

// ---------------------------------------------------------------------------------------------------------------------
// Source Domain: Toggle Generation
//   SLOW2FAST=1 (slow-to-fast, default): toggle directly on each event_s.
//   SLOW2FAST=0 (fast-to-slow): retriggerable pulse stretcher widens narrow
//     source pulses to >= PULSE_EXT clk_s cycles, then toggles on the rising
//     edge of the stretched pulse so the slower clk_d reliably samples it.
// ---------------------------------------------------------------------------------------------------------------------
wire                                             toggle_en;

generate
  if (SLOW2FAST == 1)
  begin : g_slow2fast
    assign toggle_en         = event_s;
  end
  else
  begin : g_fast2slow
    reg                                          ext_pulse;
    reg                                          ext_pulse_dly;
    reg            [7:0]                         ext_cnt;

    always @(posedge clk_s or negedge rst_s_n)
    begin : PULSE_EXT_PROC
      if (rst_s_n == 1'b0)
      begin
        ext_pulse     <= 1'b0;
        ext_pulse_dly <= 1'b0;
        ext_cnt       <= {8{1'b0}};
      end
      else if (init_s_n == 1'b0)
      begin
        ext_pulse     <= 1'b0;
        ext_pulse_dly <= 1'b0;
        ext_cnt       <= {8{1'b0}};
      end
      else
      begin
        ext_pulse_dly <= ext_pulse;
        if (event_s == 1'b1)
        begin
          ext_pulse <= 1'b1;
          ext_cnt   <= PULSE_EXT;
        end
        else if (ext_pulse == 1'b1)
        begin
          if (ext_cnt != {8{1'b0}})
            ext_cnt <= ext_cnt - 1'b1;
          else
            ext_pulse <= 1'b0;
        end
      end
    end

    assign toggle_en         = ext_pulse & ~ext_pulse_dly;
  end
endgenerate

reg                                              toggle_src;

always @(posedge clk_s or negedge rst_s_n)
begin : TOGGLE_SRC_PROC
  if (rst_s_n == 1'b0)
    toggle_src            <= 1'b0;
  else if (init_s_n == 1'b0)
    toggle_src            <= 1'b0;
  else if (toggle_en == 1'b1)
    toggle_src            <= ~toggle_src;
end

// ---------------------------------------------------------------------------------------------------------------------
// Forward Sync Chain: Toggle
// Technology selection: TSMC_12 / FPGA_XILINX / FPGA_ALTERA / default RTL
// ---------------------------------------------------------------------------------------------------------------------
`ifdef TSMC_12
wire               [STAGES-1:0]                  sync_reg;
genvar sg;
generate
  for (sg = 0; sg < STAGES; sg = sg + 1)
  begin : SYNC_CHAIN_LOOP
    if (sg == 0)
    begin : STAGE0_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[0] : toggle_src);
      SDFSYNCNQD1BWP7D5T16P96CPD U_SYNC (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( sync_reg_din                          ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( sync_reg[0]                           )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[sg] : sync_reg[sg-1]);
      SDFSYNCNQD1BWP7D5T16P96CPD U_SYNC (
      .CDN                             ( rst_d_n                               ),
      .CP                              ( clk_d                                 ),
      .D                               ( sync_reg_din                          ),
      .SE                              ( 1'b0                                  ),
      .SI                              ( 1'b0                                  ),
      .Q                               ( sync_reg[sg]                          )
      );
    end
  end
endgenerate
wire toggle_dst = sync_reg[STAGES-1];
`elsif FPGA_XILINX
wire               [STAGES-1:0]                  sync_reg;
genvar sx;
generate
  for (sx = 0; sx < STAGES; sx = sx + 1)
  begin : SYNC_CHAIN_LOOP
    if (sx == 0)
    begin : STAGE0_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[0] : toggle_src);
      FDCE U_SYNC (
      .Q                               ( sync_reg[0]                           ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( sync_reg_din                          )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[sx] : sync_reg[sx-1]);
      FDCE U_SYNC (
      .Q                               ( sync_reg[sx]                          ),
      .C                               ( clk_d                                 ),
      .CE                              ( 1'b1                                  ),
      .CLR                             ( rst_d_n                               ),
      .D                               ( sync_reg_din                          )
      );
    end
  end
endgenerate
wire toggle_dst = sync_reg[STAGES-1];
`elsif FPGA_ALTERA
wire               [STAGES-1:0]                  sync_reg;
genvar sa;
generate
  for (sa = 0; sa < STAGES; sa = sa + 1)
  begin : SYNC_CHAIN_LOOP
    if (sa == 0)
    begin : STAGE0_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[0] : toggle_src);
      dffeas U_SYNC (
      .q                               ( sync_reg[0]                           ),
      .d                               ( sync_reg_din                          ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( sync_reg_din                          )
      );
    end
    else
    begin : STAGE_N_BRANCH
      wire                                       sync_reg_din;
      assign sync_reg_din              = init_d_n & (test ? sync_reg[sa] : sync_reg[sa-1]);
      dffeas U_SYNC (
      .q                               ( sync_reg[sa]                          ),
      .d                               ( sync_reg_din                          ),
      .clk                             ( clk_d                                 ),
      .clrn                            ( rst_d_n                               ),
      .ena                             ( 1'b1                                  ),
      .asyncload                       ( 1'b0                                  ),
      .sload                           ( 1'b0                                  ),
      .sclr                            ( 1'b0                                  ),
      .aload                           ( 1'b0                                  ),
      .data                            ( sync_reg_din                          )
      );
    end
  end
endgenerate
wire toggle_dst = sync_reg[STAGES-1];
`else
reg                [STAGES-1:0]                  sync_reg;
integer s;
always @(posedge clk_d or negedge rst_d_n)
begin : SYNC_CHAIN_PROC
  if (rst_d_n == 1'b0)
    sync_reg           <= {STAGES{1'b0}};
  else if (init_d_n == 1'b0)
    sync_reg           <= {STAGES{1'b0}};
  else if (test == 1'b1)
    sync_reg           <= sync_reg;
  else
  begin
    sync_reg[0]        <= toggle_src;
    for (s = 1; s < STAGES; s = s + 1)
    sync_reg[s]    <= sync_reg[s-1];
  end
end
wire toggle_dst = sync_reg[STAGES-1];
`endif

// ---------------------------------------------------------------------------------------------------------------------
// Destination Domain: Toggle -> Pulse
// ---------------------------------------------------------------------------------------------------------------------
reg                                              toggle_dly;

always @(posedge clk_d or negedge rst_d_n)
begin : TGL2PULSE_PROC
  if (rst_d_n == 1'b0)
    toggle_dly            <= 1'b0;
  else if (init_d_n == 1'b0)
    toggle_dly            <= 1'b0;
  else
    toggle_dly            <= toggle_dst;
end

assign event_d               = toggle_dst ^ toggle_dly;

endmodule
// =====================================================================================================================
// v1.3  2026-08-20  DWBB-aligned ports: clk_s/rst_s_n/init_s_n/event_s, clk_d/rst_d_n/init_d_n/event_d, test
// =====================================================================================================================

`endif
