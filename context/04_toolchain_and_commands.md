# Toolchain & Commands

## Toolchain summary

| Tool           | Version | Role                                      |
|----------------|---------|-------------------------------------------|
| Icarus Verilog | 12.0    | Simulation (cocotb backend, `SIM=icarus`) |
| Verilator      | 5.020   | Lint only (`make lint`, `-Wall --Wpedantic`) |
| cocotb         | 2.0.1   | Python testbench framework                |
| Python         | 3.12    | Test scripts + numpy golden models        |
| GTKWave        | —       | Waveform viewer (opens `dump.vcd`)        |
| Vivado         | 2024.x  | Synthesis/P&R — host only, Step 6         |

**Critical constraint:** cocotb 2.0.1 requires Verilator ≥ 5.036 for simulation. Ubuntu 24.04 ships 5.020. `SIM=icarus` must never be changed.

---

## Commands

```bash
# Run all tests
make sim              # 33/33 cocotb tests (all four modules)
make test_mac         # mac_unit only  (7 tests)
make test_array       # mac_array only (10 tests)
make test_axi         # axi_slave only (9 tests)
make test_top         # top only       (7 tests)

# Run a single named test
cd tb/cocotb && TESTCASE=test_zero make
cd tb/cocotb/test_array && TESTCASE=test_identity make

# Lint
make lint             # all RTL + SVA files, Verilator 5.020, 0 warnings expected
make lint_sva         # SVA checker + bind_top subset only

# Clean
make clean            # removes sim_build/, *.vcd, results.xml
```

---

## Cocotb timing pattern (canonical)

Used in every test that reads registered outputs:

```python
await RisingEdge(dut.clk)   # sync to clock edge
# drive inputs here
await RisingEdge(dut.clk)   # DUT samples inputs
await Timer(1, unit="ps")   # step past NBA region
# read output here — post-clock registered value
```

The 1 ps wait is required because Icarus fires VPI callbacks in the active region before NBA assignments settle.

---

## File layout

```
rtl/
  pkg/types_pkg.sv     Q8.8 types
  mac_unit.sv
  mac_array.sv
  axi_slave.sv
  top.sv
tb/
  cocotb/
    test_mac.py         mac_unit tests
    Makefile
    test_array/         mac_array tests
    test_axi/           axi_slave tests
    test_top/           top integration tests
  sv/
    assertions_top.sv   SVA properties + cover points (Step 5)
    bind_top.sv         binds assertions into top scope
    mac_unit_sim_dump.sv   VCD dumpers (one per module)
    mac_array_sim_dump.sv
    axi_slave_sim_dump.sv
    top_sim_dump.sv
constraints/
  arty_a7.xdc          50 MHz clock on E3, LEDs (Step 6)
scripts/
  synth.tcl            Vivado non-project synthesis flow (Step 6)
docs/
  roadmap.md           canonical step-by-step plan
docs-learning/         didactic trail (architecture, logs, modules, concepts)
```

---

## VCD waveforms

| Module     | File                                  |
|------------|---------------------------------------|
| mac_unit   | `tb/cocotb/dump.vcd`                  |
| mac_array  | `tb/cocotb/test_array/dump.vcd`       |
| axi_slave  | `tb/cocotb/test_axi/dump.vcd`         |
| top        | `tb/cocotb/test_top/dump.vcd`         |

Open with: `gtkwave tb/cocotb/test_top/dump.vcd`

---

## SVA assertions (Step 5)

File: `tb/sv/assertions_top.sv`, bound via `tb/sv/bind_top.sv`.

8 properties:
- AXI VALID stability × 5 (AW, W, B, AR, R channels — VALID must stay high until READY)
- `done` pulse lasts exactly one cycle
- `done` deasserts `busy` (busy low one cycle after done)
- `busy` clears after done

7 cover points: BRESP OKAY/SLVERR, RRESP OKAY/SLVERR, busy, done, idle.
