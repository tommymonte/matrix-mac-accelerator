`default_nettype none

module mac_array_formal ();

  logic         clk, rst_n, start, done, busy;
  logic [255:0] a_flat, b_flat;
  logic [511:0] c_flat;

  mac_array dut (.*);

  reg f_past_valid = 0;
  always @(posedge clk) f_past_valid <= 1;

  initial assume(!rst_n);

  // -------------------------------------------------------------------------
  // Latency tracker: shift register records (!busy && start) for 6 cycles
  // start_sr[6] == 1 exactly 6 posedge-clk cycles after (!busy && start)
  // -------------------------------------------------------------------------
  logic [6:0] start_sr;
  always @(posedge clk) begin
    if (!rst_n) start_sr <= '0;
    else        start_sr <= {start_sr[5:0], (!busy && start)};
  end

  // -------------------------------------------------------------------------
  // Assertions
  // -------------------------------------------------------------------------
  always @(posedge clk) begin
    if (f_past_valid) begin

      // Reset clears outputs
      if (!$past(rst_n)) begin
        AST_RESET_DONE: assert (!done);
        AST_RESET_BUSY: assert (!busy);
      end

      if ($past(rst_n)) begin

        // done is a one-cycle pulse (DONE → IDLE next cycle)
        if ($past(done))
          AST_DONE_PULSE: assert (!done);

        // After done, back to idle
        if ($past(done))
          AST_DONE_TO_IDLE: assert (!busy);

        // start when idle → busy asserted next cycle
        if (!$past(busy) && $past(start))
          AST_START_SETS_BUSY: assert (busy);

        // busy holds until done fires
        if ($past(busy) && !$past(done))
          AST_BUSY_HOLDS: assert (busy);

        // done can only fire while busy
        if (done)
          AST_DONE_IMPLIES_BUSY: assert (busy);

        // Latency: if start fired 6 cycles ago in idle (and no reset since),
        // done must be asserted now
        if (start_sr[6])
          AST_LATENCY: assert (done);

      end
    end
  end

  // -------------------------------------------------------------------------
  // Coverage
  // -------------------------------------------------------------------------
  always @(posedge clk) begin
    COV_DONE:  cover (done);
    COV_BUSY:  cover (busy);
    COV_START: cover (!busy && start);
  end

endmodule

`default_nettype wire
