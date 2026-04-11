#!/usr/bin/env bash
# sim.sh — Step 0 toolchain smoke-test.
# Compiles rtl/hello.sv with Verilator and runs the resulting binary.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RTL="${REPO_ROOT}/rtl"
OBJ_DIR="${REPO_ROOT}/obj_dir"

echo "[sim.sh] Verilator version: $(verilator --version)"

verilator --Wall --cc --exe --build \
    --top-module hello \
    "${RTL}/hello.sv" \
    "${REPO_ROOT}/scripts/main.cpp" \
    --Mdir "${OBJ_DIR}"

echo "[sim.sh] Running simulation..."
"${OBJ_DIR}/Vhello"
echo "[sim.sh] PASS — hello-world OK"
