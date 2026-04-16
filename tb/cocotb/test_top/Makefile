# cocotb Makefile for top (Step 4 — full end-to-end integration)

TOPLEVEL_LANG = verilog
SIM ?= icarus

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT    := $(abspath $(MAKEFILE_DIR)/../../..)

VERILOG_SOURCES  = $(REPO_ROOT)/rtl/pkg/types_pkg.sv
VERILOG_SOURCES += $(REPO_ROOT)/rtl/mac_unit.sv
VERILOG_SOURCES += $(REPO_ROOT)/rtl/mac_array.sv
VERILOG_SOURCES += $(REPO_ROOT)/rtl/axi_slave.sv
VERILOG_SOURCES += $(REPO_ROOT)/rtl/top.sv
VERILOG_SOURCES += $(REPO_ROOT)/tb/sv/top_sim_dump.sv

TOPLEVEL = top
MODULE   = test_top

ifeq ($(SIM),icarus)
  COMPILE_ARGS += -s top_sim_dump
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
