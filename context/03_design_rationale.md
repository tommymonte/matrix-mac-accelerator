# Design Rationale — Key Decisions

## Fixed-point & types

**Why Q8.8?**
Fixed-point is cheap in hardware (no FPU). Q8.8 fits a 16-bit signed word, matches common embedded/accelerator conventions, and keeps multiplier output at 32 bits — exactly one DSP48 slice on Xilinx.

**Why a separate `types_pkg`?**
Single source of truth for bit-widths. Changing `Q_FRAC` propagates everywhere automatically. All RTL imports via `import types_pkg::*`.

**Why no saturation (v1)?**
Saturation adds logic (comparators + mux) on the critical path. The v1 contract is: caller ensures operand magnitudes don't overflow. The testbench golden model uses int64 accumulation then `.astype(np.int32)` to match 2's-complement wrap exactly.

**Why int64 in the golden model for `test_top`?**
Q8.8 raw int16 operands: max product ≈ 32767² ≈ 1.07×10⁹; 4-term dot product can reach 4.3×10⁹, which overflows int32. int64 gold then `np.int32` wrap mirrors the RTL.

---

## Simulation toolchain

**Why Icarus Verilog, not Verilator?**
cocotb 2.0.1 requires Verilator ≥ 5.036 for simulation; Ubuntu 24.04 ships Verilator 5.020. Verilator is kept for lint only (`make lint`). **Never change `SIM=icarus` in tb/cocotb/Makefile.**

**Why the 1 ps `Timer` wait after `RisingEdge` in cocotb tests?**
Icarus fires VPI callbacks in the active region before NBA (non-blocking assignment) updates. Waiting 1 ps steps past the NBA region so `acc_out` reads the post-clock registered value.

---

## mac_array interface

**Why flat buses (`a_flat[255:0]`, `b_flat[255:0]`, `c_flat[511:0]`)?**
Icarus VPI exposes 2-D unpacked arrays as a single packed handle that cocotb cannot index per element. Flat buses work around this limitation; unpacking to typed internal 2-D arrays happens inside the module.

**Why LOAD state (1 cycle) before COMPUTE?**
Captures `a_in`/`b_in` combinational unpacked signals into registered `a_reg`/`b_reg`. Without this, the input matrices could change mid-computation if the AXI master writes new data.

---

## AXI slave

**Why accept AW+W atomically (both valid required simultaneously)?**
Keeps the write FSM to two states. AXI4-Lite allows the slave to wait for both; requiring simultaneous handshake avoids needing separate AW and W holding registers.

**Why poll `BVALID`/`RVALID` in the cocotb AXI master instead of `AWREADY`/`ARREADY`?**
The slave's READY is combinational and drops on the same edge as the handshake. Post-NBA sampling misses it. Response-phase VALID (`BVALID`/`RVALID`) is an unambiguous completion signal that stays high until READY.

**Why does `soft_reset` only reset `mac_array`, not `axi_slave`?**
`axi_slave` holds the matrix register file (A, B). Resetting it would force the AXI master to re-upload both matrices before restarting. Preserving the register file is more useful and simpler for the SW driver.

**Why W1P for CTRL.start and CTRL.soft_reset?**
These are commands, not persistent configuration. Self-clearing after one cycle avoids the need for the SW to explicitly de-assert them and prevents re-triggering on a subsequent read.

---

## SVA

**Why Verilator lint for SVA validation instead of a formal tool?**
No formal tool is available in the free toolchain. `make lint` with `--Wall` on Verilator 5.020 catches syntax/type errors in assertions. Icarus has no meaningful SVA support.

**Why avoid `##` in cover properties?**
Verilator 5.020 flags `## N` inside `cover property` as unsupported even if it parses the assertion correctly. The cover properties were written without temporal operators to stay lint-clean.

---

## Reset

**Why synchronous active-low reset throughout?**
AXI4-Lite requires synchronous reset for protocol compliance. Consistent across all modules simplifies timing analysis (reset treated as a regular data path, no async path exceptions needed).
