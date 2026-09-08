// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module otbn_rejv_unit #(
  parameter WLEN = 256
) (
  input  logic [WLEN-1:0]  operand_i,
  input  logic [WLEN-1:0]  mod_i,
  input  logic             vec_type_i,
  output logic [WLEN-1:0]  result_o,
  output logic [4:0]       count_o
);

  localparam int NUM_LANES_16 = 16;
  localparam int NUM_LANES_32 = 8;
  localparam int MAX_LANES    = 16;

  logic [MAX_LANES-1:0] accept_mask;
  logic [15:0] lane_16 [0:MAX_LANES-1];
  logic [15:0] mod_16;
  logic [31:0] lane_32 [0:NUM_LANES_32-1];
  logic [31:0] mod_32;

  assign mod_16 = mod_i[15:0];
  assign mod_32 = mod_i[31:0];

  genvar gi;
  for (gi = 0; gi < MAX_LANES; gi = gi + 1) begin : g_extract_16
    assign lane_16[gi] = operand_i[gi*16 +: 16];
  end
  for (gi = 0; gi < NUM_LANES_32; gi = gi + 1) begin : g_extract_32
    assign lane_32[gi] = operand_i[gi*32 +: 32];
  end

  integer ci;
  always @(*) begin
    accept_mask = 16'd0;
    if (vec_type_i) begin
      for (ci = 0; ci < NUM_LANES_32; ci = ci + 1) begin
        accept_mask[ci] = (lane_32[ci] < mod_32) ? 1'b1 : 1'b0;
      end
    end else begin
      for (ci = 0; ci < MAX_LANES; ci = ci + 1) begin
        accept_mask[ci] = (lane_16[ci] < mod_16) ? 1'b1 : 1'b0;
      end
    end
  end

  logic [4:0] prefix_sum [0:MAX_LANES];
  logic [4:0] dest_idx   [0:MAX_LANES-1];
  integer pi;
  always @(*) begin
    prefix_sum[0] = 5'd0;
    for (pi = 0; pi < MAX_LANES; pi = pi + 1) begin
      prefix_sum[pi+1] = prefix_sum[pi] + {4'd0, accept_mask[pi]};
      dest_idx[pi]     = prefix_sum[pi];
    end
  end
  assign count_o = prefix_sum[MAX_LANES];

  logic [15:0] result_16 [0:MAX_LANES-1];
  integer j16, i16;
  always @(*) begin
    for (j16 = 0; j16 < MAX_LANES; j16 = j16 + 1) begin
      result_16[j16] = 16'd0;
      for (i16 = 0; i16 < MAX_LANES; i16 = i16 + 1) begin
        if (accept_mask[i16] && (dest_idx[i16] == j16[4:0])) begin
          result_16[j16] = lane_16[i16];
        end
      end
    end
  end

  logic [31:0] result_32 [0:NUM_LANES_32-1];
  integer j32, i32;
  always @(*) begin
    for (j32 = 0; j32 < NUM_LANES_32; j32 = j32 + 1) begin
      result_32[j32] = 32'd0;
      for (i32 = 0; i32 < NUM_LANES_32; i32 = i32 + 1) begin
        if (accept_mask[i32] && (dest_idx[i32] == j32[4:0])) begin
          result_32[j32] = lane_32[i32];
        end
      end
    end
  end

  integer oi;
  always @(*) begin
    result_o = {WLEN{1'b0}};
    if (vec_type_i) begin
      for (oi = 0; oi < NUM_LANES_32; oi = oi + 1) begin
        result_o[oi*32 +: 32] = result_32[oi];
      end
    end else begin
      for (oi = 0; oi < MAX_LANES; oi = oi + 1) begin
        result_o[oi*16 +: 16] = result_16[oi];
      end
    end
  end
endmodule
