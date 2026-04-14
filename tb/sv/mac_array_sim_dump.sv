// Sim-only VCD dumper for Icarus Verilog runs.
// Compiled as an additional root so it runs alongside the cocotb-driven toplevel.
module mac_array_sim_dump;
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, mac_array);
  end
endmodule
