// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Designer       : CBB Team
// FileName    : cbb_parity.v
// ModuleName  : CBB_PARITY
// Create Date : 2026-07-17
// Description : Parameterized parity generator (even/odd)
//               Supports DATA_WIDTH from 1 to 256, static PAR_TYPE selection
// =====================================================================================================================

`ifndef CBB_PARITY_V
`define CBB_PARITY_V
module CBB_PARITY
   #(
    parameter DATA_WIDTH                          = 8,                          // Input data width (1~256)
    parameter PAR_TYPE                            = 0                           // 0=even parity, 1=odd parity
    )
    (
   input           [DATA_WIDTH-1:0]              datain,                       // Input data word
   output                                        parity                        // Parity output
    );

assign parity           = (PAR_TYPE == 1'b1) ? (^datain) : (~(^datain));

endmodule
`endif
// =====================================================================================================================
// Modified history
// ---------------------------------------------------------------------------------------------------------------------
// Version      | Date       | Designer     | Description
// V1.0         | 2026-07-17 | CBB Team     | Initial version
// =====================================================================================================================
