// Sim-only VCD dumper for Icarus Verilog runs of top.
module top_sim_dump;
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, top);
  end
endmodule
