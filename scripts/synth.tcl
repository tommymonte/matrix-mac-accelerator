# synth.tcl — Non-project mode synthesis + P&R for Matrix MAC Accelerator
# Target: Xilinx Arty A7-35T (xc7a35ticsg324-1L)
# Usage:  vivado -mode batch -source scripts/synth.tcl
#         (run from repo root)

set PART "xc7a35ticsg324-1L"
set TOP  "top"
set REPO_ROOT [file normalize [file dirname [info script]]/..]

# ── Source files ──────────────────────────────────────────────────────────────
set SV_SOURCES [list \
    ${REPO_ROOT}/rtl/pkg/types_pkg.sv \
    ${REPO_ROOT}/rtl/mac_unit.sv      \
    ${REPO_ROOT}/rtl/mac_array.sv     \
    ${REPO_ROOT}/rtl/axi_slave.sv     \
    ${REPO_ROOT}/rtl/top.sv           \
]

set CONSTRAINTS [list \
    ${REPO_ROOT}/constraints/arty_a7.xdc \
]

set OUTPUT_DIR ${REPO_ROOT}/build/vivado
file mkdir ${OUTPUT_DIR}

# ── Synthesis ─────────────────────────────────────────────────────────────────
read_verilog -sv {*}${SV_SOURCES}
read_xdc     {*}${CONSTRAINTS}

synth_design \
    -top        ${TOP}      \
    -part       ${PART}     \
    -flatten_hierarchy none \
    -directive  PerformanceOptimized

# Post-synthesis reports
report_utilization         -file ${OUTPUT_DIR}/post_synth_utilization.rpt
report_timing_summary      -file ${OUTPUT_DIR}/post_synth_timing.rpt -max_paths 10

# Check DSP48 inference explicitly
set dsp_count [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]]
puts "INFO: DSP48 primitives inferred: ${dsp_count}  (expect 16 — one per mac_unit)"
set dsp_report [open ${OUTPUT_DIR}/post_synth_dsp.rpt w]
puts $dsp_report "DSP48 primitives inferred: ${dsp_count}"
puts $dsp_report "Expected: 16"
close $dsp_report

# ── Opt + Place ───────────────────────────────────────────────────────────────
opt_design
place_design
phys_opt_design

report_utilization    -file ${OUTPUT_DIR}/post_place_utilization.rpt

# ── Route ─────────────────────────────────────────────────────────────────────
route_design
phys_opt_design

# ── Final reports ─────────────────────────────────────────────────────────────
report_timing_summary \
    -file        ${OUTPUT_DIR}/post_route_timing.rpt \
    -max_paths   20 \
    -warn_on_violation

report_utilization    -file ${OUTPUT_DIR}/post_route_utilization.rpt
report_power          -file ${OUTPUT_DIR}/post_route_power.rpt
report_route_status   -file ${OUTPUT_DIR}/post_route_status.rpt

# Extract WNS for CI / README badge
set wns [get_property SLACK [get_timing_paths -max_paths 1 -sort_by slack]]
puts "INFO: WNS = ${wns} ns  (target: ≥ 0.000)"
if {$wns < 0} {
    puts "ERROR: timing not met — WNS ${wns} ns"
    exit 1
}

# ── Bitstream ─────────────────────────────────────────────────────────────────
write_bitstream -force ${OUTPUT_DIR}/${TOP}.bit
puts "INFO: bitstream written → ${OUTPUT_DIR}/${TOP}.bit"
