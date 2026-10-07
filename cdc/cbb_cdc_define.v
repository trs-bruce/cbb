// =====================================================================================================================
// Copyright 2026 TeraSilicon, Inc.（特瑞思）
// SPDX-License-Identifier: Apache-2.0
// Design        : CBB_CDC_DEFINE
// Project       : CBB
// Create Date   : 2026/07/28
// Description   : CDC (Clock Domain Crossing) Module Macro Definitions
//                 Include this file before any CDC RTL source file:
//                 `include "cbb_cdc_define.v"
// =====================================================================================================================

`ifndef CBB_CDC_DEFINE_V
`define CBB_CDC_DEFINE_V

// ---------------------------------------------------------------------------------------------------------------------
// Technology Selection Macros
// ---------------------------------------------------------------------------------------------------------------------
// Define ONE of the following macros to select the synchronizer implementation.
// Standard-cell (ASIC) is unified under TSMC_12 (USE_STDCELL removed as redundant):
//
// `define TSMC_12                  // Standard-cell (ASIC) / TSMC 12nm: dedicated sync cells
//                                   //   (SDFSYNCNQD1BWP7D5T16P96CPD, 6-pin: CDN/CP/D/SE/SI/Q)
//                                   //   Same technology-family DFF cells are used for other standard cells
//
// --- FPGA (secondary) ---
// `define FPGA_XILINX              // Xilinx: FDCE primitive (D with async clear)
//                                   // Fallback: FDPE (async preset) if no clear net available
//                                   // Requires: unify simulation lib (simprim / unisim)
// `define FPGA_ALTERA               // Altera/Intel: dffeas primitive (async clear)
//                                   // Fallback: dffea (async load) if dffeas unavailable
//                                   // Requires: altera_mf / lpm simulation lib
//
// If none of the above is defined, the RTL behavioral implementation is used
// (recommended for most flows, letting synthesis tool map to target library).
// NOTE: USE_STDCELL has been removed and unified into TSMC_12.

// ---------------------------------------------------------------------------------------------------------------------
// Synchronization Configuration Macros
// ---------------------------------------------------------------------------------------------------------------------
`define ASYNC_RST_EN               // Enable asynchronous reset for synchronizer registers
                                   // (enabled by default for simulation; comment out to reduce reset fan-out)
                                   // (active low, applied to all sync stages)
                                   // If not defined, synchronizer registers have no reset
                                   // to reduce reset fan-out (per CODE-GEN10 guideline)

// ---------------------------------------------------------------------------------------------------------------------
// Usage Example
// ---------------------------------------------------------------------------------------------------------------------
// In your project-level define file or compilation script:
//
//   // Choose ONE technology (only one active at a time)
//   // `define TSMC_12       // standard-cell (ASIC)
//   // `define FPGA_XILINX   // FPGA
//   // `define FPGA_ALTERA   // FPGA
//   // If none defined, RTL behavioral is used
//
//   // Choose reset behavior
//   `define ASYNC_RST_EN
//
// Then in filelist/f:
//   +incdir+<path_to_cbb_cdc_define>
//   cbb_cdc_define.v
//   cbb_cdc_lvl.v
//   ...

`endif

// =====================================================================================================================

// =====================================================================================================================
// v1.0  2026-07-28  Initial version
// =====================================================================================================================
