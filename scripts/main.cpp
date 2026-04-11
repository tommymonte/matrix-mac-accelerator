// Verilator C++ harness for hello-world smoke test (Step 0).
#include "Vhello.h"
#include "verilated.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vhello* dut = new Vhello;

    dut->clk = 0;
    dut->eval();

    for (int i = 0; i < 10; ++i) {
        dut->clk = !dut->clk;
        dut->eval();
    }

    dut->final();
    delete dut;
    return 0;
}
