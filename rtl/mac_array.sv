`default_nettype none

// 4×4 Q8.8 matrix-multiply array.
//
// Computes C = A · B for two 4×4 matrices of Q8.8 operands.
// 16 mac_unit instances are arranged in a 4×4 grid; each C[i][j] is
// accumulated over k = 0..3 by a control FSM.
//
// Interface
// ---------
//   start  — assert (level or pulse) to begin a new computation.
//             Sampled in IDLE state on each rising clock edge.
//   done   — one-cycle pulse asserted when c_flat is valid.
//
//   Port encoding (row-major, i = row, j = column)
//     a_flat / b_flat : element [i][j] at bits 16*(4i+j)+15 : 16*(4i+j)  (q8_8_t)
//     c_flat          : element [i][j] at bits 32*(4i+j)+31 : 32*(4i+j)  (mac_acc_t)
//
//   The flat-bus interface is used so that Icarus VPI / cocotb can drive and
//   sample the ports without hitting the 2-D unpacked-array VPI limitation.
//   Unpacking to typed internal signals happens inside the module.
//
// Latency: 6 cycles from the rising edge that first sees start=1
//   IDLE (1) → LOAD (1) → COMPUTE×4 (4) → DONE (1) → IDLE
//
// Overflow: v1 contract — 32-bit wrapping, no saturation.

module mac_array
  import types_pkg::*;
(
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  output logic       done,
  output logic       busy,
  input  logic [255:0] a_flat,   // 16 × q8_8_t  (Q8.8, 16-bit signed)
  input  logic [255:0] b_flat,   // 16 × q8_8_t
  output logic [511:0] c_flat    // 16 × mac_acc_t (32-bit signed)
);

  // -------------------------------------------------------------------------
  // Unpack flat inputs to typed 2-D arrays used by the datapath
  // -------------------------------------------------------------------------
  q8_8_t a_in [0:3][0:3];
  q8_8_t b_in [0:3][0:3];

  generate
    for (genvar ui = 0; ui < 4; ui++) begin : g_unpack_row
      for (genvar uj = 0; uj < 4; uj++) begin : g_unpack_col
        assign a_in[ui][uj] = q8_8_t'(a_flat[16*(4*ui+uj) +: 16]);
        assign b_in[ui][uj] = q8_8_t'(b_flat[16*(4*ui+uj) +: 16]);
      end
    end
  endgenerate

  // -------------------------------------------------------------------------
  // FSM
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] {IDLE = 2'd0, LOAD = 2'd1, COMPUTE = 2'd2, DONE = 2'd3} state_t;
  state_t state_r, state_next;

  always_ff @(posedge clk) begin
    if (!rst_n) state_r <= IDLE;
    else        state_r <= state_next;
  end

  always_comb begin
    state_next = state_r;
    case (state_r)
      IDLE:    if (start)          state_next = LOAD;
      LOAD:                        state_next = COMPUTE;
      COMPUTE: if (k_reg == 2'd3)  state_next = DONE;
      DONE:                        state_next = IDLE;
      default:                     state_next = IDLE;
    endcase
  end

  // -------------------------------------------------------------------------
  // k counter — 2-bit, increments each cycle in COMPUTE, clears otherwise
  // -------------------------------------------------------------------------
  logic [1:0] k_reg;

  always_ff @(posedge clk) begin
    if (!rst_n || state_r != COMPUTE)
      k_reg <= 2'd0;
    else
      k_reg <= k_reg + 2'd1;
  end

  // -------------------------------------------------------------------------
  // Input-matrix registers (captured during LOAD)
  // -------------------------------------------------------------------------
  q8_8_t a_reg [0:3][0:3];
  q8_8_t b_reg [0:3][0:3];

  // Icarus 12 does not support whole-array assignment; use explicit loops.
  integer li, lj;
  always_ff @(posedge clk) begin
    if (state_r == LOAD) begin
      for (li = 0; li < 4; li = li + 1)
        for (lj = 0; lj < 4; lj = lj + 1) begin
          a_reg[li][lj] <= a_in[li][lj];
          b_reg[li][lj] <= b_in[li][lj];
        end
    end
  end

  // -------------------------------------------------------------------------
  // Control signals
  // -------------------------------------------------------------------------
  logic mac_en;
  assign mac_en = (state_r == COMPUTE);
  assign done   = (state_r == DONE);
  assign busy   = (state_r != IDLE);

  // -------------------------------------------------------------------------
  // 16 mac_unit instances — 4×4 generate grid
  // -------------------------------------------------------------------------
  mac_acc_t acc_out_w [0:3][0:3];   // registered outputs of each mac_unit
  mac_acc_t acc_in_w  [0:3][0:3];   // inputs: 0 on k=0, feedback otherwise

  generate
    for (genvar i = 0; i < 4; i++) begin : g_row
      for (genvar j = 0; j < 4; j++) begin : g_col

        // Clear the accumulator on the first k-iteration; self-feed after that.
        // No combinational loop: acc_out_w is a flip-flop output.
        assign acc_in_w[i][j] = (k_reg == 2'd0) ? '0 : acc_out_w[i][j];

        mac_unit u_mac (
          .clk    (clk),
          .rst_n  (rst_n),
          .en     (mac_en),
          .a      (a_reg[i][k_reg]),
          .b      (b_reg[k_reg][j]),
          .acc_in (acc_in_w[i][j]),
          .acc_out(acc_out_w[i][j])
        );

      end
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Pack outputs to flat bus (valid when done=1)
  // -------------------------------------------------------------------------
  generate
    for (genvar oi = 0; oi < 4; oi++) begin : g_pack_row
      for (genvar oj = 0; oj < 4; oj++) begin : g_pack_col
        assign c_flat[32*(4*oi+oj) +: 32] = acc_out_w[oi][oj];
      end
    end
  endgenerate

endmodule

`default_nettype wire
