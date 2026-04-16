# cocotb Makefile for axi_slave
#
# Simulator: Icarus Verilog (same rationale as test_mac/test_array).

TOPLEVEL_LANG = verilog
SIM ?= icarus

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT    := $(abspath $(MAKEFILE_DIR)/../../..)

VERILOG_SOURCES  = $(REPO_ROOT)/rtl/pkg/types_pkg.sv
VERILOG_SOURCES += $(REPO_ROOT)/rtl/axi_slave.sv
VERILOG_SOURCES += $(REPO_ROOT)/tb/sv/axi_slave_sim_dump.sv

TOPLEVEL = axi_slave
MODULE   = test_axi

ifeq ($(SIM),icarus)
  COMPILE_ARGS += -s axi_slave_sim_dump
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
