SHELL := /bin/bash
REPO_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: sim clean

## Step 0: Verilator hello-world smoke test
sim:
	@bash $(REPO_ROOT)scripts/sim.sh

clean:
	rm -rf obj_dir sim_build results.xml *.vcd
