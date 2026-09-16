`default_nettype none

module mac_unit (
  input  wire                clk,
  input  wire                rst_n,
  input  wire                en,
  input  wire signed [15:0]  a,
  input  wire signed [15:0]  b,
  input  wire signed [31:0]  acc_in,
  output logic signed [31:0] acc_out
);

  // No saturation: overflow wraps in 2's complement; array-level accumulator sizing is the v1 contract.
  always_ff @(posedge clk) begin
    if (!rst_n)    acc_out <= '0;
    else if (en)   acc_out <= acc_in + (a * b);
  end

endmodule

`default_nettype wire
