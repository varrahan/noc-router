# Tool configuration
IVERILOG := iverilog
VVP := vvp
GTKWAVE := gtkwave

# Project layout
SRC_DIR := ../src
TB_DIR := ../tb
SIM_DIR := ../sim
WAVE_FILE := $(SIM_DIR)/router_waves.vcd
SNAPSHOT := $(SIM_DIR)/router_sim.vvp

RTL_SRCS := $(SRC_DIR)/buffer.v $(SRC_DIR)/route_compute.v $(SRC_DIR)/vc_allocator.v $(SRC_DIR)/switch_allocator.v $(SRC_DIR)/switch.v $(SRC_DIR)/top.v
TB_SRCS := $(TB_DIR)/traffic_gen.v  $(TB_DIR)/router_tb.v
ALL_SRCS := $(RTL_SRCS) $(TB_SRCS)
IVFLAGS := -g2001 -Wall -Wno-implicit-dimensions -I$(SRC_DIR) -I$(TB_DIR)
TOP_MODULE := router_tb

.PHONY: all sim wave lint clean help

all: sim wave

$(SIM_DIR):
	mkdir -p $(SIM_DIR)

sim: $(SIM_DIR)
	@echo "----------------------------------------------------------------------"
	@echo "  [1/2] Compiling NoC Router with Icarus Verilog..."
	@echo "----------------------------------------------------------------------"
	$(IVERILOG) $(IVFLAGS) -s $(TOP_MODULE) -o $(SNAPSHOT) $(ALL_SRCS)
	@echo ""
	@echo "----------------------------------------------------------------------"
	@echo "  [2/2] Running simulation..."
	@echo "----------------------------------------------------------------------"
	$(VVP) $(SNAPSHOT)
	@echo ""
	@echo "  VCD waveform written to: $(WAVE_FILE)"

lint: $(SIM_DIR)
	@echo "  Lint pass (Icarus Verilog syntax check)..."
	$(IVERILOG) $(IVFLAGS) -tnull -s $(TOP_MODULE) $(ALL_SRCS) && \
	echo "  Lint PASSED – no errors detected."

wave: $(WAVE_FILE)
	@echo "  Opening GTKWave..."
	$(GTKWAVE) $(WAVE_FILE) &

$(WAVE_FILE):
	@echo "  VCD file not found. Run 'make sim' first."
	@exit 1

clean:
	rm -rf $(SIM_DIR)
	@echo "  Cleaned simulation artefacts."

help:
	@echo ""
	@echo "  NoC Router Project – Makefile Targets"
	@echo "  ──────────────────────────────────────"
	@echo "  make sim    – Compile RTL + testbench, run simulation, dump VCD"
	@echo "  make wave   – Open GTKWave with latest VCD"
	@echo "  make lint   – Syntax/lint check only (no simulation)"
	@echo "  make clean  – Remove all generated files"
	@echo "  make all    – Run sim then open GTKWave"
	@echo ""
	@echo "  Parameters can be overridden at compile time using:"
	@echo "    iverilog -DROUTER_X_ID=3 ..."
	@echo ""