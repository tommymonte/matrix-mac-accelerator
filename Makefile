SHELL := /bin/bash
REPO_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: sim test_mac test_array lint clean

## Default simulation target: run all cocotb testbenches
sim: test_mac test_array

## Step 1: mac_unit cocotb testbench (Icarus Verilog backend)
test_mac:
	$(MAKE) -C $(REPO_ROOT)tb/cocotb

## Step 2: mac_array cocotb testbench (Icarus Verilog backend)
test_array:
	$(MAKE) -C $(REPO_ROOT)tb/cocotb/test_array

## Verilator lint-only check (-Wall). Uses Verilator 5.020 — simulation runs on Icarus.
lint:
	verilator --lint-only -Wall --Wpedantic \
	    $(REPO_ROOT)rtl/pkg/types_pkg.sv \
	    $(REPO_ROOT)rtl/mac_unit.sv \
	    --top-module mac_unit
	verilator --lint-only -Wall --Wpedantic \
	    $(REPO_ROOT)rtl/pkg/types_pkg.sv \
	    $(REPO_ROOT)rtl/mac_unit.sv \
	    $(REPO_ROOT)rtl/mac_array.sv \
	    --top-module mac_array

clean:
	$(MAKE) -C $(REPO_ROOT)tb/cocotb clean 2>/dev/null || true
	$(MAKE) -C $(REPO_ROOT)tb/cocotb/test_array clean 2>/dev/null || true
	rm -rf $(REPO_ROOT)obj_dir $(REPO_ROOT)sim_build $(REPO_ROOT)results.xml $(REPO_ROOT)*.vcd
	rm -rf $(REPO_ROOT)tb/cocotb/sim_build $(REPO_ROOT)tb/cocotb/results.xml $(REPO_ROOT)tb/cocotb/dump.vcd
	rm -rf $(REPO_ROOT)tb/cocotb/test_array/sim_build $(REPO_ROOT)tb/cocotb/test_array/results.xml $(REPO_ROOT)tb/cocotb/test_array/dump.vcd
