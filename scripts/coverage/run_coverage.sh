#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(dirname "$(dirname "${BASH_SOURCE[0]}")")
VLT_MIN=5.036

# Check Verilator version
VLT_VER=$(verilator --version | awk '{print $2}')
if [ "$(printf '%s\n%s\n' "$VLT_MIN" "$VLT_VER" | sort -V | head -n1)" != "$VLT_MIN" ]; then
  echo "Error: Verilator >= $VLT_MIN required for cocotb simulation. Found $VLT_VER."
  echo "Please install/upgrade Verilator (see coverage/README.md for instructions)."
  exit 1
fi

mkdir -p "$REPO_ROOT/coverage/tmp"
cd "$REPO_ROOT"

BENCHES=("tb/cocotb" "tb/cocotb/test_array" "tb/cocotb/test_axi" "tb/cocotb/test_top")
COVERAGE_DAT_FILES=()

for d in "${BENCHES[@]}"; do
  echo "\n=== Running coverage for $d ==="
  make -C "$d" clean || true
  # Build and run using Verilator with coverage flags
  make -C "$d" SIM=verilator EXTRA_ARGS="--coverage --coverage-line --coverage-toggle" || {
    echo "Simulation failed in $d"; exit 1
  }
  SIM_BUILD_DIR="$d/sim_build"
  if [ -f "$SIM_BUILD_DIR/coverage.dat" ]; then
    out="$REPO_ROOT/coverage/tmp/coverage_$(basename $d).dat"
    cp "$SIM_BUILD_DIR/coverage.dat" "$out"
    COVERAGE_DAT_FILES+=("$out")
    echo "Collected $out"
  else
    echo "Warning: no coverage.dat produced in $SIM_BUILD_DIR"
  fi
done

if [ ${#COVERAGE_DAT_FILES[@]} -eq 0 ]; then
  echo "No coverage data files found; aborting report generation."
  exit 1
fi

# Merge and produce lcov-style .info
mkdir -p "$REPO_ROOT/coverage/artifacts"
INFO_OUT="$REPO_ROOT/coverage/artifacts/coverage.info"
MERGED_DAT="$REPO_ROOT/coverage/artifacts/merged.dat"

verilator_coverage -write "$MERGED_DAT" -read ${COVERAGE_DAT_FILES[*]}
verilator_coverage -write-info "$INFO_OUT" -read ${COVERAGE_DAT_FILES[*]}
verilator_coverage --annotate "$REPO_ROOT/coverage/artifacts/annotated" -read ${COVERAGE_DAT_FILES[*]} || true

# Generate Markdown report (Python script)
python3 "$REPO_ROOT/scripts/coverage/generate_md.py" "$INFO_OUT" "$REPO_ROOT/coverage/COVERAGE_REPORT.md"

# Create README with instructions
python3 - <<'PY'
from pathlib import Path
p=Path('coverage/README.md')
if not p.exists():
    p.write_text('# Coverage README\n\nSee COVERAGE_REPORT.md for results.\n')
PY

echo "\nCoverage artifacts written under coverage/"
ls -la coverage
