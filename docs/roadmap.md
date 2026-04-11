# Implementation Roadmap

## Step 0 — Environment & repo setup
**Deliverable:** structured repo, working toolchain.

- [x] Folder structure (`rtl/`, `tb/cocotb/`, `tb/sv/`, `constraints/`, `scripts/`, `docs/`)
- [x] `.gitignore` for Vivado and Python artifacts
- [ ] Verify toolchain: Verilator, cocotb, GTKWave, Vivado 2023.x
- [x] Initial README with description and WIP badge
- [ ] `make sim` runs a Verilator hello-world with no errors

---

## Step 1 — Single MAC Unit
**Deliverable:** Q8.8 Multiply-Accumulate unit verified in isolation.

### RTL — `rtl/mac_unit.sv`
- [ ] Inputs: two `logic signed [15:0]` operands (Q8.8), 32-bit `acc_in`, `clk`, `rst_n`, `en`
- [ ] Output: `acc_out [31:0]`
- [ ] 1-stage pipeline: register on `acc_out`
- [ ] Optional saturation logic
- [ ] Package `rtl/pkg/types_pkg.sv` with typedefs `q8_8_t`, `mac_acc_t`

### Testbench — `tb/cocotb/test_mac.py`
- [ ] Directed tests: 0×0, 1×1, max×max, neg×neg, neg×pos
- [ ] Random test: 1000 vectors against a Python reference model (`numpy` with `int16`/`int32`)
- [ ] Bit-exact comparison between DUT and model
- [ ] Generate `dump.vcd` for GTKWave inspection

---

## Step 2 — 4×4 MAC Array
**Deliverable:** array of 16 MAC instances computing C = A·B in fixed-point.

### RTL — `rtl/mac_array.sv`
- [ ] Inputs: matrices A and B as packed arrays `logic signed [15:0] a_matrix [0:3][0:3]`
- [ ] Output: matrix C `logic signed [31:0] c_matrix [0:3][0:3]`
- [ ] 16 instantiated MACs, each computing one C[i][j] over 4 cycles iterating on k
- [ ] Control FSM: `IDLE → LOAD → COMPUTE → DONE`
- [ ] `done` signal asserted when computation completes

### Testbench — `tb/cocotb/test_array.py`
- [ ] Tests on known matrices (identity, zero, random)
- [ ] Reference model: `numpy.matmul` with Q8.8 scaling
- [ ] At least 100 random matrices, bit-exact

---

## Step 3 — AXI4-Lite Slave
**Deliverable:** AXI4-Lite slave interface compliant with the ARM IHI 0022 spec.

### RTL — `rtl/axi_slave.sv`
- [ ] All 5 channels: AW, W, B, AR, R with correct handshake
- [ ] Internal register file:
  - `0x00` CTRL (bit 0 = start, bit 1 = reset)
  - `0x04` STATUS (bit 0 = busy, bit 1 = done)
  - `0x10–0x4C` matrix A (16 words)
  - `0x50–0x8C` matrix B (16 words)
  - `0x90–0xCC` matrix C (read-only, 16 words)
- [ ] `SLVERR` response on unmapped addresses

### Testbench — `tb/cocotb/test_axi.py`
- [ ] Uses `cocotbext-axi` as AXI master
- [ ] Tests: single write, single read, write+read back, invalid address

---

## Step 4 — Top-level Integration
**Deliverable:** `top.sv` integrating `axi_slave` + `mac_array` with control FSM.

### RTL — `rtl/top.sv`
- [ ] Instantiates `axi_slave` and `mac_array`
- [ ] Glue logic: CTRL.start → load A/B → wait `done` → write C → set STATUS.done
- [ ] Single clock, synchronous active-low reset

### Testbench — `tb/cocotb/test_top.py`
- [ ] End-to-end: write A/B via AXI → start → poll done → read C → compare `numpy.matmul`
- [ ] At least 50 random end-to-end matrices
- [ ] Stress test: two back-to-back computations

---

## Step 5 — SVA Assertions and Coverage
**Deliverable:** formal assertions on the protocol and functional coverage report.

### Assertions — `tb/sv/assertions.sv`
- [ ] AXI handshake stability: VALID must stay high until READY
- [ ] No X on AXI control signals after reset
- [ ] `done` pulse lasts exactly one cycle
- [ ] STATUS.busy blocks new start commands
- [ ] Unmapped read → `RRESP = SLVERR`

### Functional Coverage
- [ ] Coverpoints on matrix types (zero, identity, negative, saturated)
- [ ] Coverpoints on AXI transaction sequences
- [ ] Target: >90% coverage

---

## Step 6 — Vivado Synthesis and Timing Closure
**Deliverable:** bitstream on Xilinx Arty A7-35T, timing met at 50 MHz.

### Constraints — `constraints/arty_a7.xdc`
- [ ] 50 MHz clock on pin E3
- [ ] Status LEDs mapped to STATUS[0:1]

### Script — `scripts/synth.tcl`
- [ ] Non-project mode: `read_verilog`, `synth_design`, `place_design`, `route_design`, `write_bitstream`
- [ ] `report_timing_summary` shows WNS ≥ 0 ns

---

## Step 7 — Documentation
**Deliverable:** complete README and architecture/timing docs.

- [ ] `README.md`: overview, architecture diagram, build instructions, verification results, synthesis table
- [ ] `docs/architecture.md`: MAC unit, array, AXI slave, FSM state diagrams, register map
- [ ] `docs/timing_report.md`: Vivado timing summary, critical path analysis
