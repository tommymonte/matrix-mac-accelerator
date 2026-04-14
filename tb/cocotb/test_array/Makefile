# cocotb Makefile for mac_array
#
# Simulator: Icarus Verilog (same rationale as test_mac — see tb/cocotb/Makefile).

TOPLEVEL_LANG = verilog
SIM ?= icarus

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT    := $(abspath $(MAKEFILE_DIR)/../../..)

VERILOG_SOURCES  = $(REPO_ROOT)/rtl/pkg/types_pkg.sv
VERILOG_SOURCES += $(REPO_ROOT)/rtl/mac_unit.sv
VERILOG_SOURCES += $(REPO_ROOT)/rtl/mac_array.sv
VERILOG_SOURCES += $(REPO_ROOT)/tb/sv/mac_array_sim_dump.sv

TOPLEVEL = mac_array
MODULE   = test_array

ifeq ($(SIM),icarus)
  COMPILE_ARGS += -s mac_array_sim_dump
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
