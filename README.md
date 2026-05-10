# Matrix Multiply Accelerator 4×4

![Status](https://img.shields.io/badge/status-WIP-yellow)
![Language](https://img.shields.io/badge/language-SystemVerilog-blue)
![Simulator](https://img.shields.io/badge/sim-Icarus%20%7C%20cocotb-green)
![Lint](https://img.shields.io/badge/lint-Verilator%205.020-brightgreen)
![Target](https://img.shields.io/badge/target-Xilinx%20Arty%20A7--35T-red)
![Tests](https://img.shields.io/badge/tests-33%2F33%20passing-success)

A 4×4 fixed-point (Q8.8) matrix-multiply accelerator in SystemVerilog with an AXI4-Lite slave interface, targeting the Xilinx Arty A7-35T (Artix-7) at 50 MHz.

---

## Features

- **16 parallel MAC units** in a 4×4 grid, each computing one element of `C = A·B` over 4 k-iterations.
- **Q8.8 fixed-point** operands (16-bit signed); 32-bit accumulators with 2's-complement wrapping (no saturation).
- **AXI4-Lite slave** (ARM IHI 0022 compliant) with `OKAY` / `SLVERR` responses, register-mapped operand and result matrices.
- **Single clock domain**, synchronous active-low reset.
- **6-cycle latency** per matrix multiplication: `IDLE → LOAD → COMPUTE×4 → DONE`.
- **8 SVA properties + 7 functional coverage points** validated with Verilator lint.

---

## Architecture

```
top.sv
├── axi_slave.sv     — AXI4-Lite register file + handshake FSMs (write/read)
└── mac_array.sv     — control FSM (IDLE/LOAD/COMPUTE/DONE) + 16 MACs
    └── mac_unit.sv  — registered Q8.8 MAC: acc <= acc + (a*b)
```

### AXI4-Lite register map

| Address     | Register | Access | Description                              |
|-------------|----------|--------|------------------------------------------|
| `0x00`      | CTRL     | W1P    | bit0 = start, bit1 = soft_reset          |
| `0x04`      | STATUS   | RO/W1C | bit0 = busy (live), bit1 = done (sticky) |
| `0x10–0x4C` | A[0..15] | RW     | Matrix A, row-major (Q8.8 in low 16 bits)|
| `0x50–0x8C` | B[0..15] | RW     | Matrix B, row-major                      |
| `0x90–0xCC` | C[0..15] | RO     | Matrix C, row-major (32-bit accumulators)|

Unmapped or unaligned addresses → `SLVERR`. Writes to the read-only C region → `SLVERR`.

---

## Verification

| Module      | Tests | Status | Coverage                                              |
|-------------|-------|--------|-------------------------------------------------------|
| `mac_unit`  | 7     | ✅     | Directed + 1000 random vectors, bit-exact vs. Python  |
| `mac_array` | 10    | ✅     | Directed + 100 random 4×4 matrices vs. NumPy          |
| `axi_slave` | 9     | ✅     | Reset/RW/RO/SLVERR/W1P/W1C + 200-op random stress     |
| `top`       | 7     | ✅     | End-to-end + 50 random matrices + back-to-back stress |
| **Total**   | **33**| ✅     | All cocotb regressions pass, lint clean (0 warnings)  |

### SVA assertions (Step 5)

8 `assert property` statements bound to `top` via `bind`:
- AXI A3.2.1 VALID stability on all 5 channels (AW, W, B, AR, R).
- `done` is always a 1-cycle pulse.
- `done` implies `busy`; `busy` clears the cycle after `done`.

Validated with `make lint_sva` (Verilator 5.020). Not exercised under Icarus simulation due to limited SVA support.

---

## Build & test

### Toolchain

| Tool             | Version | Role                            |
|------------------|---------|---------------------------------|
| Icarus Verilog   | 12.0    | Simulation (cocotb backend)     |
| Verilator        | 5.020   | Lint only (`make lint`)         |
| cocotb           | 2.0.1   | Python testbench framework      |
| Python           | ≥ 3.10  | Reference models                |
| GTKWave          | any     | Waveform viewer (optional)      |

> cocotb 2.0.1 requires Verilator ≥ 5.036 for simulation, but Ubuntu 24.04 ships 5.020. Simulation therefore runs on Icarus; Verilator is kept for lint.

### Commands

```bash
make sim         # run all 33 cocotb tests (Icarus backend)
make test_mac    # run a single module's testbench (also test_array, test_axi, test_top)
make lint        # Verilator lint on all RTL + SVA bind (0 warnings expected)
make lint_sva    # SVA-only lint subset
make clean       # wipe all build artifacts
```

To run a single test by name:
```bash
cd tb/cocotb && TESTCASE=test_zero make
```

VCD waveforms are written to `tb/cocotb/{,test_array/,test_axi/,test_top/}dump.vcd`.

---

## Repository layout

```
.
├── rtl/
│   ├── pkg/types_pkg.sv     # Q8.8 typedefs (q8_8_t, mac_acc_t)
│   ├── mac_unit.sv          # Single registered MAC
│   ├── mac_array.sv         # 4×4 grid + control FSM
│   ├── axi_slave.sv         # AXI4-Lite slave + register file
│   └── top.sv               # Integration wrapper
├── tb/
│   ├── cocotb/              # 4 cocotb testbenches (test_mac, test_array, test_axi, test_top)
│   └── sv/                  # VCD dumpers + SVA checker (assertions_top.sv, bind_top.sv)
├── docs/
│   └── roadmap.md           # Step-by-step implementation plan
├── constraints/             # Vivado XDC (Step 6)
├── scripts/                 # Vivado TCL (Step 6)
└── Makefile                 # Top-level build targets
```

---

## Roadmap

| Step | Focus                              | Status |
|------|------------------------------------|--------|
| 0    | Repo + toolchain setup             | ✅     |
| 1    | `mac_unit` (single Q8.8 MAC)       | ✅     |
| 2    | `mac_array` (4×4 grid + FSM)       | ✅     |
| 3    | `axi_slave` (AXI4-Lite)            | ✅     |
| 4    | `top` (integration + end-to-end TB)| ✅     |
| 5    | SVA assertions + functional cov    | ✅     |
| 6    | Vivado synthesis + timing closure  | 🎯     |
| 7    | Documentation polish               | ⏳     |

See [`docs/roadmap.md`](docs/roadmap.md) for full details.

---

## Design notes

- **Why Q8.8?** Fixed-point is cheap in hardware; Q8.8 fits a 16-bit signed word and gives ±127.996 with 1/256 resolution.
- **Why no saturation?** v1 contract — overflow wraps in 2's complement. Sizing the accumulator to 32 bits prevents practical overflow for typical workloads.
- **Why flat-bus ports on `mac_array`?** Icarus 12 VPI exposes 2-D unpacked ports as a single packed handle that cocotb cannot index. Flat buses are the workaround; unpacking happens internally.
- **Why `bind` for SVA?** Standard industry pattern: keeps RTL clean, allows checker to access internal nets without exposing them as ports.

---

## License

TBD (likely MIT or Apache 2.0 — to be added before Step 7).
