// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// otbn_extv_unit: Vectorized Bit-Field Extraction Unit for OTBN
//
// Implements the bn.extv instruction: extract consecutive N-bit fields
// from a byte stream in a 256-bit WDR into lane-aligned positions.
//
// Modes:
//   .16H (vec_type_i = 0): Extract 16 x 12-bit fields -> 16-bit lanes
//                          (ML-KEM SampleNTT, FIPS 203 Algorithm 7)
//   .8S  (vec_type_i = 1): Extract 8 x 24-bit fields -> 32-bit lanes
//                          (ML-DSA RejNTTPoly, FIPS 204 Algorithm 14)
//
// Both modes consume exactly 192 bits (24 bytes) from the source WDR,
// leaving 64 bits (8 bytes) as remainder for cross-squeeze stitching.
//
// Microarchitecture: Pure combinational wiring + mode mux.
// Each output lane is a fixed bit-slice of the input, zero-extended.
// No arithmetic, no comparators, no shifters.
//
// Latency: 1 cycle (combinational)
// Area estimate: ~200-400 LUTs (dominated by the mode mux)
//
// Security:
//   Constant-time: fixed wiring, no data-dependent paths
//   Output lanes are zero-extended (no stale bits)
//   Compatible with OTBN integrity-coded WDR write path

module otbn_extv_unit #(
  parameter WLEN = 256
) (
  input  logic [WLEN-1:0]  operand_i,   // Source WDR (raw byte stream)
  input  logic             vec_type_i,  // 0 = .16H (12-bit), 1 = .8S (24-bit)
  output logic [WLEN-1:0]  result_o     // Extracted candidates in lane-aligned positions
);

  // --------------------------------------------------------------------------
  // .16H mode: 16 x 12-bit -> 16-bit lanes
  // lane[i] = operand[i*12 +: 12], zero-extended to 16 bits
  // --------------------------------------------------------------------------
  logic [15:0] lane_16h [0:15];

  genvar gi;
  for (gi = 0; gi < 16; gi = gi + 1) begin : g_extract_12bit
    assign lane_16h[gi] = {4'b0000, operand_i[gi*12 +: 12]};
  end

  // --------------------------------------------------------------------------
  // .8S mode: 8 x 24-bit stride -> 32-bit lanes (23 bits kept, MSB masked)
  // lane[i] = operand[i*24 +: 23], zero-extended to 32 bits
  // Per FIPS 204 CoeffFromThreeBytes: z = b0 + 256*b1 + 65536*(b2 mod 128)
  // The stride is 24 bits (3 bytes) to maintain byte alignment.
  // --------------------------------------------------------------------------
  logic [31:0] lane_8s [0:7];

  for (gi = 0; gi < 8; gi = gi + 1) begin : g_extract_24bit
    assign lane_8s[gi] = {9'b0, operand_i[gi*24 +: 23]};
  end

  // --------------------------------------------------------------------------
  // Output mux: select between .16H and .8S
  // --------------------------------------------------------------------------
  integer oi;
  always @(*) begin
    result_o = {WLEN{1'b0}};
    if (vec_type_i) begin
      // .8S mode
      for (oi = 0; oi < 8; oi = oi + 1) begin
        result_o[oi*32 +: 32] = lane_8s[oi];
      end
    end else begin
      // .16H mode
      for (oi = 0; oi < 16; oi = oi + 1) begin
        result_o[oi*16 +: 16] = lane_16h[oi];
      end
    end
  end

endmodule
