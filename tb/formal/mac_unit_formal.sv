`default_nettype none

module mac_unit_formal ();

  logic               clk, rst_n, en;
  logic signed [15:0] a, b;
  logic signed [31:0] acc_in, acc_out;

  mac_unit dut (.*);

  // Track when $past() is valid (at least 1 cycle elapsed)
  reg f_past_valid = 0;
  always @(posedge clk) f_past_valid <= 1;

  // Start in reset
  initial assume(!rst_n);

  always @(posedge clk) begin
    if (f_past_valid) begin

      // Reset clears output
      if (!$past(rst_n))
        AST_RESET_CLEARS: assert (acc_out == '0);

      if ($past(rst_n)) begin
        // MAC computation: acc_out == acc_in + sign_ext(a)*sign_ext(b)
        if ($past(en))
          AST_MAC_COMPUTE: assert (acc_out == $past(acc_in) + $past(a) * $past(b));

        // Hold when not enabled
        if (!$past(en))
          AST_HOLD_WHEN_DISABLED: assert (acc_out == $past(acc_out));
      end

    end
  end

  // Coverage
  always @(posedge clk) begin
    COV_EN_HIGH:  cover (en);
    COV_EN_LOW:   cover (!en);
    COV_RESET:    cover (!rst_n);
    COV_NONZERO:  cover (acc_out != '0);
  end

endmodule

`default_nettype wire
