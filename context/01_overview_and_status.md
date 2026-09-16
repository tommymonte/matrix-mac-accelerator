# Matrix MAC Accelerator — Project Overview & Status

## What this project is

A 4×4 fixed-point matrix-multiply accelerator in SystemVerilog, built as a CV flagship for RTL design/verification roles (STMicro, Infineon, ARM, Qualcomm). The accelerator computes C = A·B for Q8.8 matrices, exposed via an AXI4-Lite register interface, targeting the Xilinx Arty A7-35T at 50 MHz.

## Architecture

```
top.sv
├── axi_slave.sv    AXI4-Lite register interface (CTRL, STATUS, A, B, C)
└── mac_array.sv    4×4 array of mac_unit instances, control FSM
    └── mac_unit.sv  Single registered MAC: acc_out <= acc_in + (a * b)
```

### Fixed-point convention
- **Q8.8**: 16-bit signed (`q8_8_t`), 8 integer + 8 fractional bits
- **Accumulator**: 32-bit signed (`mac_acc_t`), no saturation (2's complement wrap — v1 contract)
- Types defined in `rtl/pkg/types_pkg.sv`, imported everywhere via `import types_pkg::*`

### AXI4-Lite register map (byte-addressed, 32-bit words)

| Address    | Register | Access | Notes                                              |
|------------|----------|--------|----------------------------------------------------|
| `0x00`     | CTRL     | W      | bit0 = start (W1P), bit1 = soft_reset (W1P)        |
| `0x04`     | STATUS   | R/W1C  | bit0 = busy (RO), bit1 = done (sticky, W1C)        |
| `0x10–0x4C`| A[0..15] | RW     | Matrix A, row-major, low 16 bits = Q8.8 operand    |
| `0x50–0x8C`| B[0..15] | RW     | Matrix B, row-major                                |
| `0x90–0xCC`| C[0..15] | RO     | Matrix C, row-major, 32-bit accumulators           |

Unmapped / unaligned / write-to-C → `SLVERR`.

### mac_array FSM
`IDLE → LOAD → COMPUTE×4 → DONE → IDLE`
- 6-cycle latency from `start=1`
- `done` is a one-cycle pulse; `busy` is asserted in all non-IDLE states
- `start` while `busy` is silently dropped (SW must poll `STATUS.busy=0` first)

---

## Step-by-step progress

| Step | Focus                          | Status       |
|------|--------------------------------|--------------|
| 0    | Repo + toolchain setup         | ✅ Done      |
| 1    | `mac_unit` — single MAC        | ✅ Done      |
| 2    | `mac_array` — 4×4 array + FSM  | ✅ Done      |
| 3    | `axi_slave` — AXI4-Lite slave  | ✅ Done      |
| 4    | `top.sv` — integration         | ✅ Done      |
| 5    | SVA assertions + coverage      | ✅ Done      |
| **6**| **Vivado synthesis + timing**  | **⬅ NEXT**  |
| 7    | Documentation + CV README      | Planned      |

### Current test status (snapshot: 2026-05-10)
```
make sim   → 33/33 cocotb tests PASS
              7  mac_unit  (test_mac.py)
              10 mac_array (test_array/test_array.py)
              9  axi_slave (test_axi/test_axi.py)
              7  top       (test_top/test_top.py)
make lint  → 0 warnings (Verilator 5.020, includes SVA files)
```

---

## Step 6 deliverables (immediate next task)

- `constraints/arty_a7.xdc` — 50 MHz clock on pin E3 ✅ created
- `scripts/synth.tcl` — non-project mode: synth → place → route → bitstream ✅ created
- `report_timing_summary` WNS ≥ 0 ns ← **requires Vivado installed on host**
- Verify DSP48 count = 16 in synth log (one per mac_unit)

---

## Known limitations (accepted for v1)

1. No saturation — 32-bit accumulators wrap in 2's complement
2. Flat-bus ports on `mac_array` (`a_flat[255:0]`, `b_flat[255:0]`, `c_flat[511:0]`) — Icarus VPI can't index 2-D unpacked ports from cocotb
3. Simulation uses Icarus Verilog 12.0; Verilator 5.020 is lint-only
4. Hand-rolled AXI master in cocotb (no `cocotbext-axi`)
5. No CI yet (planned Step 7)
6. SVA validated under Verilator lint only — Icarus SVA support is insufficient
7. `start` while `busy` is silently dropped
