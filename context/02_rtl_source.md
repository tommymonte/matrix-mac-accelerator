# RTL Source — All Modules

## `rtl/pkg/types_pkg.sv`

```systemverilog
// Shared Q8.8 fixed-point types for the matrix-MAC accelerator.
package types_pkg;
  parameter int Q_FRAC = 8;
  typedef logic signed [(2*Q_FRAC)-1:0] q8_8_t;    // 16-bit, Q8.8
  typedef logic signed [(4*Q_FRAC)-1:0] mac_acc_t;  // 32-bit accumulator
endpackage
```

---

## `rtl/mac_unit.sv`

```systemverilog
`default_nettype none

module mac_unit
  import types_pkg::*;
(
  input  logic     clk,
  input  logic     rst_n,
  input  logic     en,
  input  q8_8_t    a,
  input  q8_8_t    b,
  input  mac_acc_t acc_in,
  output mac_acc_t acc_out
);

  // No saturation: overflow wraps in 2's complement; array-level accumulator sizing is the v1 contract.
  always_ff @(posedge clk) begin
    if (!rst_n)    acc_out <= '0;
    else if (en)   acc_out <= acc_in + (a * b);
  end

endmodule

`default_nettype wire
```

---

## `rtl/mac_array.sv`

```systemverilog
`default_nettype none

// 4×4 Q8.8 matrix-multiply array.
// Flat-bus interface used because Icarus VPI cannot index 2-D unpacked ports from cocotb.
// Port encoding (row-major): element [i][j] at bits 16*(4i+j)+15:16*(4i+j) (q8_8_t) for a/b,
//                                              32*(4i+j)+31:32*(4i+j) (mac_acc_t) for c.
// Latency: 6 cycles. FSM: IDLE → LOAD → COMPUTE×4 → DONE → IDLE.

module mac_array
  import types_pkg::*;
(
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  output logic       done,
  output logic       busy,
  input  logic [255:0] a_flat,
  input  logic [255:0] b_flat,
  output logic [511:0] c_flat
);

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

  typedef enum logic [1:0] {IDLE=2'd0, LOAD=2'd1, COMPUTE=2'd2, DONE=2'd3} state_t;
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

  logic [1:0] k_reg;
  always_ff @(posedge clk) begin
    if (!rst_n || state_r != COMPUTE) k_reg <= 2'd0;
    else                              k_reg <= k_reg + 2'd1;
  end

  q8_8_t a_reg [0:3][0:3];
  q8_8_t b_reg [0:3][0:3];
  integer li, lj;
  always_ff @(posedge clk) begin
    if (state_r == LOAD)
      for (li = 0; li < 4; li = li + 1)
        for (lj = 0; lj < 4; lj = lj + 1) begin
          a_reg[li][lj] <= a_in[li][lj];
          b_reg[li][lj] <= b_in[li][lj];
        end
  end

  logic mac_en;
  assign mac_en = (state_r == COMPUTE);
  assign done   = (state_r == DONE);
  assign busy   = (state_r != IDLE);

  mac_acc_t acc_out_w [0:3][0:3];
  mac_acc_t acc_in_w  [0:3][0:3];

  generate
    for (genvar i = 0; i < 4; i++) begin : g_row
      for (genvar j = 0; j < 4; j++) begin : g_col
        assign acc_in_w[i][j] = (k_reg == 2'd0) ? '0 : acc_out_w[i][j];
        mac_unit u_mac (
          .clk(clk), .rst_n(rst_n), .en(mac_en),
          .a(a_reg[i][k_reg]), .b(b_reg[k_reg][j]),
          .acc_in(acc_in_w[i][j]), .acc_out(acc_out_w[i][j])
        );
      end
    end
  endgenerate

  generate
    for (genvar oi = 0; oi < 4; oi++) begin : g_pack_row
      for (genvar oj = 0; oj < 4; oj++) begin : g_pack_col
        assign c_flat[32*(4*oi+oj) +: 32] = acc_out_w[oi][oj];
      end
    end
  endgenerate

endmodule

`default_nettype wire
```

---

## `rtl/axi_slave.sv`

See full source in [rtl/axi_slave.sv](../rtl/axi_slave.sv). Key points:

- **Write FSM**: `W_IDLE → W_RESP`. Accepts AW+W atomically (both must be valid simultaneously).
- **Read FSM**: `R_IDLE → R_RESP`. `arready` is combinationally high in R_IDLE.
- **CTRL** (0x00): W1P — `start_pulse` and `soft_reset` are asserted for one cycle then cleared.
- **STATUS** (0x04): `busy` is live pass-through from `mac_array`; `done` is sticky (set on `mac_array.done` pulse, cleared by W1C or by a new `start`).
- **SLVERR** conditions: unaligned address, unmapped address, write to C region.
- `start` while busy: `start_pulse` is generated but `mac_array` ignores it in non-IDLE state (silently dropped).

---

## `rtl/top.sv`

```systemverilog
`default_nettype none

// Wires axi_slave → mac_array.
// soft_reset (CTRL.bit1) pulses mac_array reset only; axi_slave keeps register state.

module top
  import types_pkg::*;
#(parameter int ADDR_WIDTH=8, parameter int DATA_WIDTH=32)(
  input  logic clk, rst_n,
  // full AXI4-Lite port list (see rtl/top.sv for all signals)
  ...
);
  logic start_pulse, soft_reset, busy, done;
  logic [255:0] a_flat, b_flat;
  logic [511:0] c_flat;

  logic rst_n_core;
  assign rst_n_core = rst_n & ~soft_reset;   // soft_reset gates mac_array only

  axi_slave #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_axi (...);
  mac_array  u_mac (.clk(clk), .rst_n(rst_n_core), .start(start_pulse), ...);
endmodule

`default_nettype wire
```
