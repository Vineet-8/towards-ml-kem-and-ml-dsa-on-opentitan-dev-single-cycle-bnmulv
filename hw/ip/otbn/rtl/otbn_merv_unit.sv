// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// otbn_merv_unit: Variable-Offset Vector Merge Unit for OTBN
//
// Implements the bn.merv instruction: merge compacted values from bn.rejv
// into an accumulator WDR at a variable lane offset.
//
// Operation:
//   result = accumulator OR (new_values << (offset * lane_width))
//
// This replaces the serial "extract-shift-accumulate" loop (3 instructions
// per accepted value) with a single-cycle barrel-shift-and-OR.
//
// Modes:
//   .16H (vec_type_i = 0): 16-bit lanes, shift by offset × 16 bits
//   .8S  (vec_type_i = 1): 32-bit lanes, shift by offset × 32 bits
//
// The offset comes from a GPR (0 to NUM_LANES-1) tracking how many
// coefficients are already in the accumulator.
//
// Latency: 1 cycle (combinational)
// Area estimate: ~800-1200 LUTs (barrel shifter dominates)
//
// Security:
//   Constant-time: barrel shifter processes all bits regardless of offset
//   Compatible with OTBN integrity-coded WDR write path

module otbn_merv_unit #(
  parameter WLEN = 256
) (
  input  logic [WLEN-1:0]  accumulator_i,  // Current accumulator WDR (wrd read)
  input  logic [WLEN-1:0]  new_values_i,   // Compacted values from bn.rejv (wrs)
  input  logic [4:0]       offset_i,       // Current fill level from GPR (0-15 or 0-7)
  input  logic             vec_type_i,     // 0 = .16H (16-bit), 1 = .8S (32-bit)
  output logic [WLEN-1:0]  result_o        // accumulator OR (new_values << offset)
);

  // --------------------------------------------------------------------------
  // Barrel Shifter: shift new_values left by (offset × lane_width) bits
  // --------------------------------------------------------------------------
  logic [WLEN-1:0] shifted;
  logic [7:0] shift_amount;  // shift in bits (max: 15*16=240 or 7*32=224)

  always @(*) begin
    if (vec_type_i) begin
      // .8S mode: shift by offset × 32 bits
      // offset is 0-7, shift is 0-224 bits
      shift_amount = {offset_i[2:0], 5'b00000};  // offset * 32
    end else begin
      // .16H mode: shift by offset × 16 bits
      // offset is 0-15, shift is 0-240 bits
      shift_amount = {offset_i[3:0], 4'b0000};   // offset * 16
    end
  end

  // Barrel shifter: left shift by shift_amount bits
  // Implemented as a cascade of conditional shifts (log-depth mux tree)
  logic [WLEN-1:0] sh0, sh1, sh2, sh3, sh4, sh5, sh6, sh7;

  // Stage 0: shift by 0 or 1 bit
  assign sh0 = shift_amount[0] ? {new_values_i[WLEN-2:0], 1'b0} : new_values_i;
  // Stage 1: shift by 0 or 2 bits
  assign sh1 = shift_amount[1] ? {sh0[WLEN-3:0], 2'b0} : sh0;
  // Stage 2: shift by 0 or 4 bits
  assign sh2 = shift_amount[2] ? {sh1[WLEN-5:0], 4'b0} : sh1;
  // Stage 3: shift by 0 or 8 bits
  assign sh3 = shift_amount[3] ? {sh2[WLEN-9:0], 8'b0} : sh2;
  // Stage 4: shift by 0 or 16 bits
  assign sh4 = shift_amount[4] ? {sh3[WLEN-17:0], 16'b0} : sh3;
  // Stage 5: shift by 0 or 32 bits
  assign sh5 = shift_amount[5] ? {sh4[WLEN-33:0], 32'b0} : sh4;
  // Stage 6: shift by 0 or 64 bits
  assign sh6 = shift_amount[6] ? {sh5[WLEN-65:0], 64'b0} : sh5;
  // Stage 7: shift by 0 or 128 bits
  assign sh7 = shift_amount[7] ? {sh6[WLEN-129:0], 128'b0} : sh6;

  assign shifted = sh7;

  // --------------------------------------------------------------------------
  // Merge: OR the shifted new values into the accumulator
  // --------------------------------------------------------------------------
  assign result_o = accumulator_i | shifted;

endmodule
