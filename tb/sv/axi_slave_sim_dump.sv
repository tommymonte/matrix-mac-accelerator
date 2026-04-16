// Sim-only VCD dumper for Icarus Verilog runs of axi_slave.
module axi_slave_sim_dump;
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, axi_slave);
  end
endmodule
