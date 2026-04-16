# Implementation Roadmap

## Step 0 — Environment & repo setup ✅ DONE
**Deliverable:** structured repo, working toolchain.

- [x] Folder structure (`rtl/`, `tb/cocotb/`, `tb/sv/`, `constraints/`, `scripts/`, `docs/`)
- [x] `.gitignore` for Vivado and Python artifacts
- [x] Verify toolchain: Verilator 5.020 ✅ | cocotb 2.0.1 ✅ | GTKWave ✅ | Vivado — host-only, deferred to Step 6
- [x] Initial README with description and WIP badge
- [x] `make sim` → `PASS — hello-world OK` (zero `-Wall` warnings)

---

## Step 1 — Single MAC Unit ✅ DONE
**Deliverable:** Q8.8 Multiply-Accumulate unit verified in isolation.

### RTL — `rtl/mac_unit.sv`
- [x] Inputs: two `logic signed [15:0]` operands (Q8.8), 32-bit `acc_in`, `clk`, `rst_n`, `en`
- [x] Output: `acc_out [31:0]`
- [x] 1-stage pipeline: register on `acc_out`
- [x] Saturation: skipped (2's complement wrap); array-level sizing is the v1 contract
- [x] Package `rtl/pkg/types_pkg.sv` with `Q_FRAC`, `q8_8_t`, `mac_acc_t`

### Testbench — `tb/cocotb/test_mac.py`
- [x] Directed tests: 0×0, 1×1, max×max, neg×neg, neg×pos, mixed, hold, reset
- [x] Random test: 1000 vectors against a Python reference (native int → wrap-to-int32)
- [x] Bit-exact comparison between DUT and model — **6/6 PASS**
- [x] Generate `dump.vcd` for GTKWave inspection

### Toolchain note
- Simulator: **Icarus Verilog 12.0** (cocotb 2.0.1 requires Verilator ≥ 5.036; Ubuntu 24.04 ships 5.020).
- Verilator 5.020 kept for lint only via `make lint` (`-Wall --Wpedantic` clean).

---

## Step 2 — 4×4 MAC Array ✅ DONE
**Deliverable:** array of 16 MAC instances computing C = A·B in fixed-point.

### RTL — `rtl/mac_array.sv`
- [x] Flat-bus ports (`a_flat[255:0]`, `b_flat[255:0]`, `c_flat[511:0]`) to work around Icarus VPI 2-D unpacked-array limit
- [x] 16 instantiated MACs, each computing one C[i][j] over k = 0..3
- [x] Control FSM: `IDLE → LOAD → COMPUTE×4 → DONE` (6-cycle latency)
- [x] One-cycle `done` pulse asserted when `c_flat` is valid

### Testbench — `tb/cocotb/test_array/test_array.py`
- [x] Directed: zero, identity, identity×M, ones, negatives, known-result, max pos/neg, back-to-back runs
- [x] 100 random 4×4 matrices vs. NumPy golden model — **10/10 PASS**, bit-exact

---

## Step 3 — AXI4-Lite Slave ✅ DONE
**Deliverable:** AXI4-Lite slave interface compliant with the ARM IHI 0022 spec.

### RTL — `rtl/axi_slave.sv`
- [x] All 5 channels: AW, W, B, AR, R with correct handshake (two 2-state FSMs)
- [x] Internal register file:
  - `0x00` CTRL   (W1P self-clearing: bit0 = start, bit1 = soft_reset)
  - `0x04` STATUS (RO bit0 = busy live; W1C bit1 = done sticky)
  - `0x10–0x4C` matrix A (16 RW words)
  - `0x50–0x8C` matrix B (16 RW words)
  - `0x90–0xCC` matrix C (read-only, 16 words sliced from c_flat)
- [x] `SLVERR` response on unmapped / unaligned / write-to-RO accesses

### Testbench — `tb/cocotb/test_axi/test_axi.py`
- [x] Hand-rolled AXI4-Lite master (no `cocotbext-axi` dependency yet)
- [x] 9 tests: reset defaults, A/B R+W, C read-only, unmapped+unaligned SLVERR,
      CTRL W1P pulse, STATUS sticky/W1C, STATUS.busy pass-through, 200-op random stress

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
