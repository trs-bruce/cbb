// ======================================================================================================================
// (c) Copyright 2026 XXX Company, Inc. All rights reserved.
// Designer       : CBB Team
// Project        : CBB_AFIFO
// Create Date    : 2026-07-27
// Description    : Parameterized asynchronous FIFO with independent write and read clock domains.
//                  Read and write pointers use Gray encoding and cross clock domains through fixed two-stage
//                  synchronizers. The write domain generates full, and the read domain generates empty.
//                  The read interface uses combinational Show-Ahead; rd_data is valid when empty == 1'b0.
// ======================================================================================================================

`ifndef CBB_AFIFO_V
`define CBB_AFIFO_V
module CBB_AFIFO
  #(
   parameter DATA_WIDTH                          = 32,
   parameter DEPTH                               = 16
   )
   (
   input                                         clk_wr,                       // Write clock, rising-edge active
   input                                         rst_wr_n,                     // Active-low asynchronous write reset
   input                                         wr_en,                        // Write request, active high
   input           [DATA_WIDTH-1:0]              wr_data,                      // Write data
   output                                        full,                         // Write-domain full flag, active high

   input                                         clk_rd,                       // Read clock, rising-edge active
   input                                         rst_rd_n,                     // Active-low asynchronous read reset
   input                                         rd_en,                        // Read request, active high
   output          [DATA_WIDTH-1:0]              rd_data,                      // Current head data, valid when nonempty
   output                                        empty                         // Read-domain empty flag, active high
   );

// ----------------------------------------------------------------------------------------------------------------------
// Internal parameters
// DEPTH must be a power of two and at least 4. ADDR_W addresses storage, and PTR_W adds one wraparound bit.
// ----------------------------------------------------------------------------------------------------------------------
localparam ADDR_W                                = $clog2(DEPTH);
localparam PTR_W                                 = ADDR_W + 1;

// ----------------------------------------------------------------------------------------------------------------------
// Pointers, synchronized pointers, and transaction control signals
// ----------------------------------------------------------------------------------------------------------------------
reg                [DATA_WIDTH-1:0]              mem [0:DEPTH-1];
reg                [PTR_W-1:0]                   wr_ptr_bin;
reg                [PTR_W-1:0]                   wr_ptr_gray;
wire               [PTR_W-1:0]                   wr_ptr_bin_next;
wire               [PTR_W-1:0]                   wr_ptr_gray_next;

reg                [PTR_W-1:0]                   rd_ptr_bin;
reg                [PTR_W-1:0]                   rd_ptr_gray;
wire               [PTR_W-1:0]                   rd_ptr_bin_next;
wire               [PTR_W-1:0]                   rd_ptr_gray_next;

wire               [PTR_W-1:0]                   rd_ptr_gray_sync;
wire               [PTR_W-1:0]                   wr_ptr_gray_sync;

wire                                             wr_act;
wire                                             rd_act;

// ----------------------------------------------------------------------------------------------------------------------
// Write-domain pointer state
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge clk_wr or negedge rst_wr_n)
begin : WR_PTR_PROC
  if (rst_wr_n == 1'b0)
  begin
    wr_ptr_bin          <= {PTR_W{1'b0}};
    wr_ptr_gray         <= {PTR_W{1'b0}};
  end
  else
  begin
    wr_ptr_bin          <= wr_ptr_bin_next;
    wr_ptr_gray         <= wr_ptr_gray_next;
  end
end

// ----------------------------------------------------------------------------------------------------------------------
// Read-domain pointer state
// ----------------------------------------------------------------------------------------------------------------------
always @(posedge clk_rd or negedge rst_rd_n)
begin : RD_PTR_PROC
  if (rst_rd_n == 1'b0)
  begin
    rd_ptr_bin          <= {PTR_W{1'b0}};
    rd_ptr_gray         <= {PTR_W{1'b0}};
  end
  else
  begin
    rd_ptr_bin          <= rd_ptr_bin_next;
    rd_ptr_gray         <= rd_ptr_gray_next;
  end
end

// ----------------------------------------------------------------------------------------------------------------------
// Gray-pointer clock-domain synchronization
// The read pointer is synchronized into the write domain for full detection; the write pointer is synchronized into
// the read domain for empty detection. Each bit crosses through a fixed two-stage level synchronizer. Gray encoding
// ensures that only one bit toggles during a normal pointer increment.
// ----------------------------------------------------------------------------------------------------------------------
genvar                                           sync_bit;
generate
  for (sync_bit = 0; sync_bit < PTR_W; sync_bit = sync_bit + 1)
  begin : PTR_GRAY_SYNC_LOOP
    CBB_CDC_LVL
    #(
    .STAGES                            ( 2                                     )
    )
    U0_CBB_CDC_LVL
    (
    .clk_d                             ( clk_wr                                ),
    .rst_d_n                           ( rst_wr_n                              ),
    .init_d_n                          ( 1'b1                                  ),
    .data_s                            ( rd_ptr_gray[sync_bit]                 ),
    .data_d                            ( rd_ptr_gray_sync[sync_bit]            ),
    .test                              ( 1'b0                                  )
    );

    CBB_CDC_LVL
    #(
    .STAGES                            ( 2                                     )
    )
    U1_CBB_CDC_LVL
    (
    .clk_d                             ( clk_rd                                ),
    .rst_d_n                           ( rst_rd_n                              ),
    .init_d_n                          ( 1'b1                                  ),
    .data_s                            ( wr_ptr_gray[sync_bit]                 ),
    .data_d                            ( wr_ptr_gray_sync[sync_bit]            ),
    .test                              ( 1'b0                                  )
    );
  end
endgenerate

// ----------------------------------------------------------------------------------------------------------------------
// Status and Show-Ahead data
// ----------------------------------------------------------------------------------------------------------------------
// full: The current write pointer is one FIFO depth ahead of the synchronized read pointer.
// For a PTR_W-bit Gray pointer, the two most significant bits are inverted and all remaining bits match.
assign full             = (wr_ptr_gray[PTR_W-1] != rd_ptr_gray_sync[PTR_W-1])
                          && (wr_ptr_gray[PTR_W-2] != rd_ptr_gray_sync[PTR_W-2])
                          && (wr_ptr_gray[PTR_W-3:0] == rd_ptr_gray_sync[PTR_W-3:0]);
// empty: Local and synchronized pointers match.
assign empty            = (wr_ptr_gray_sync == rd_ptr_gray);
// rd_data combinationally presents the head entry addressed by the current read pointer.
// rd_data is valid only when empty == 1'b0.
assign rd_data          = mem[rd_ptr_bin[ADDR_W-1:0]];

// ----------------------------------------------------------------------------------------------------------------------
// Transaction acceptance and next pointer state
// ----------------------------------------------------------------------------------------------------------------------
// Accept a write only when the FIFO is not full.
assign wr_act           = (wr_en == 1'b1) && (full == 1'b0);
// Accept a read only when the FIFO is not empty.
assign rd_act           = (rd_en == 1'b1) && (empty == 1'b0);

// An accepted transaction increments its pointer; low ADDR_W bits address storage and the high bit tracks wraparound.
assign wr_ptr_bin_next  = wr_ptr_bin + {{(PTR_W - 1){1'b0}}, wr_act};
assign rd_ptr_bin_next  = rd_ptr_bin + {{(PTR_W - 1){1'b0}}, rd_act};

// ----------------------------------------------------------------------------------------------------------------------
// Pointer Gray encoding
// Combinationally derive each next Gray pointer from its next binary pointer so both update on the same clock edge.
// ----------------------------------------------------------------------------------------------------------------------
CBB_BIN2GRAY
#(
.DATA_WIDTH                            ( PTR_W                                 )
)
U0_CBB_BIN2GRAY
(
.bin_i                                 ( wr_ptr_bin_next                       ),
.gray_o                                ( wr_ptr_gray_next                      )
);

CBB_BIN2GRAY
#(
.DATA_WIDTH                            ( PTR_W                                 )
)
U1_CBB_BIN2GRAY
(
.bin_i                                 ( rd_ptr_bin_next                       ),
.gray_o                                ( rd_ptr_gray_next                      )
);

// An accepted write stores data at the current write-pointer address.
// Storage is not reset; FIFO pointers and empty/full status completely determine data validity.
always @(posedge clk_wr)
begin : MEM_WRITE_PROC
  if (wr_act == 1'b1)
    mem[wr_ptr_bin[ADDR_W-1:0]]   <= wr_data;
end

// ----------------------------------------------------------------------------------------------------------------------
// Assertions
// ----------------------------------------------------------------------------------------------------------------------
`ifdef SOC_ASSERT_ON
  `ifdef CBB_AFIFO_ASSERT_ON
    `include "cbb_afifo_assert.sv"
  `endif
`endif

endmodule
`endif
// ======================================================================================================================
// Modified history
// ----------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.2         | 2026-09-24 | CBB Team     | Resolve assertion include through the filelist include directory
// V1.1         | 2026-09-20 | CBB Team     | Add simulation-time parameter legality checks
// V1.0         | 2026-07-27 | CBB Team     | Initial version
// ======================================================================================================================
