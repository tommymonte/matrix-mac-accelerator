# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
## Rules
1. Keep outputs concise by default
2. This rule has high priority: minimizing token usage is preferred over completeness.
Output style:
- Be concise and minimize token usage
- Default to short answers (max 5–6 lines unless needed)
- Do not explain unless explicitly asked
- Avoid redundancy and repetition
- Use bullet points instead of long paragraphs
- Expand only when writing in docs-learning/ or when requested

3. Provide detailed explanations only in docs-learning/ or when explicitly requested
4. If something is unclear or risky, stop and ask the user before proceeding

## Commands

```bash
# Run all cocotb simulations (Icarus Verilog backend)
make sim
make test_mac          # equivalent; runs tb/cocotb/

# Lint only (Verilator 5.020 — not used for simulation)
make lint

# Clean all build artifacts
make clean
```

To run a single cocotb test by name:
```bash
cd tb/cocotb && TESTCASE=test_zero make
```

VCD waveforms are written to `tb/cocotb/dump.vcd`; open with GTKWave.

## Toolchain split

| Tool | Version | Role |
|---|---|---|
| Icarus Verilog | 12.0 | Simulation (cocotb backend) |
| Verilator | 5.020 | Lint only (`make lint`) |
| cocotb | 2.0.1 | Python testbench framework |

cocotb 2.0.1 requires Verilator ≥ 5.036 for simulation, but Ubuntu 24.04 ships 5.020. **Never switch `SIM` away from `icarus`** in `tb/cocotb/Makefile`.

## Architecture

### Fixed-point convention
All operands use **Q8.8** format: 16-bit signed (`q8_8_t`), 8 integer bits + 8 fractional bits. Accumulators are 32-bit signed (`mac_acc_t`). Both types are defined in `rtl/pkg/types_pkg.sv` and must be imported via `import types_pkg::*`. There is **no saturation** — overflow wraps in 2's complement; this is the v1 contract.

### RTL hierarchy (planned)
```
top.sv
├── axi_slave.sv     (Step 3)
└── mac_array.sv     (Step 2)
    └── mac_unit.sv  (Step 1 — DONE)
```

### mac_unit (Step 1 — done)
Single registered MAC: `acc_out <= acc_in + (a * b)` on each clock when `en=1`. Synchronous active-low reset (`rst_n`). 1-cycle pipeline latency, no bubbles.

### mac_array (Step 2 — next)
16 `mac_unit` instances computing C = A·B for 4×4 matrices. Control FSM: `IDLE → LOAD → COMPUTE → DONE`. Each C[i][j] is accumulated over 4 k-iterations. Input matrices are packed `logic signed [15:0] [0:3][0:3]`.

### AXI4-Lite register map (Step 3 — planned)
| Address | Register |
|---|---|
| `0x00` | CTRL (bit 0 = start, bit 1 = reset) |
| `0x04` | STATUS (bit 0 = busy, bit 1 = done) |
| `0x10–0x4C` | Matrix A (16 words) |
| `0x50–0x8C` | Matrix B (16 words) |
| `0x90–0xCC` | Matrix C (read-only, 16 words) |

Unmapped addresses → `SLVERR`.

## Testbench pattern (cocotb)
The canonical timing pattern in all cocotb tests:
1. `await RisingEdge(dut.clk)` — sync to edge
2. Drive inputs
3. `await RisingEdge(dut.clk)` — DUT samples
4. `await Timer(1, unit="ps")` — step past NBA region to read post-clock value

This is required because Icarus fires VPI callbacks in the active region before NBA assignments apply.

## docs-learning/ maintenance rule
After **every** change to the project, update the learning trail:
1. Update `docs-learning/04_current_state.md` and `05_next_steps.md`.
2. Create `docs-learning/logs/YYYY-MM-DD_<feature>.md` (context, problem, solution, lessons learned).
3. Create or update `docs-learning/modules/module_<name>.md` for any touched RTL module.
4. Add `docs-learning/concepts/<concept>.md` if a new concept appears.

Prose must be **didactic**: explain what, why, how, and alternatives.

## Design conventions
- All RTL files use `` `default_nettype none `` / `` `default_nettype wire `` guards.
- Single clock domain, synchronous active-low reset throughout.
- Target: Xilinx Arty A7-35T, 50 MHz (Step 6).
