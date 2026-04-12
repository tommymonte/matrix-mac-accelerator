# cocotb Makefile for mac_unit
#
# Default simulator: Icarus Verilog (cocotb 2.0.1 requires Verilator >= 5.036;
# the Ubuntu 24.04 apt build is 5.020, so we use Icarus for simulation and
# keep Verilator purely for lint via the top-level `make lint` target).

TOPLEVEL_LANG = verilog
SIM ?= icarus

# Compute REPO_ROOT relative to this Makefile's directory.
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(MAKEFILE_DIR)/../..)

# Package must be compiled first, then the DUT, then the sim-only dumper root.
VERILOG_SOURCES  = $(REPO_ROOT)/rtl/pkg/types_pkg.sv
VERILOG_SOURCES += $(REPO_ROOT)/rtl/mac_unit.sv
VERILOG_SOURCES += $(REPO_ROOT)/tb/sv/mac_unit_sim_dump.sv

TOPLEVEL = mac_unit
MODULE   = test_mac

# Icarus: elaborate the sim-only dumper as an additional root.
# ($(SIM)=icarus already adds -g2012 and -s $(TOPLEVEL) via cocotb's Makefile.)
ifeq ($(SIM),icarus)
  COMPILE_ARGS += -s mac_unit_sim_dump
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
