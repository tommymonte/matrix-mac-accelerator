SHELL := /bin/bash
REPO_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: sim test_mac lint clean

## Default simulation target: run all cocotb testbenches
sim: test_mac

## Step 1: mac_unit cocotb testbench (Icarus Verilog backend)
test_mac:
	$(MAKE) -C $(REPO_ROOT)tb/cocotb

## Verilator lint-only check (-Wall). Uses Verilator 5.020 — simulation runs on Icarus.
lint:
	verilator --lint-only -Wall --Wpedantic \
	    $(REPO_ROOT)rtl/pkg/types_pkg.sv \
	    $(REPO_ROOT)rtl/mac_unit.sv \
	    --top-module mac_unit

clean:
	$(MAKE) -C $(REPO_ROOT)tb/cocotb clean 2>/dev/null || true
	rm -rf $(REPO_ROOT)obj_dir $(REPO_ROOT)sim_build $(REPO_ROOT)results.xml $(REPO_ROOT)*.vcd
	rm -rf $(REPO_ROOT)tb/cocotb/sim_build $(REPO_ROOT)tb/cocotb/results.xml $(REPO_ROOT)tb/cocotb/dump.vcd
