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
