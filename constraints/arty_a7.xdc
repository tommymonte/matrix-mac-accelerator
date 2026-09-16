# Arty A7-35T constraints — Matrix MAC Accelerator
# Clock: 100 MHz on E3 (onboard oscillator), we target 50 MHz via create_clock
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk }]
create_clock -add -name sys_clk_pin -period 20.000 -waveform { 0 10 } [get_ports { clk }]

# Reset: active-low, tied to CPU_RESET button (C2, active-high on board)
# You must invert it externally or adjust rst_n polarity
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports { rst_n }]

# AXI4-Lite signals — exposed via PMOD JA for scope/LA probing (optional)
# Uncomment and assign to your board's I/O if you wire a master externally.
# For synthesis/timing closure without physical I/O, leave constrained as virtual.

# STATUS LEDs (Arty A7 green LEDs LD0–LD1)
#   LD0 = busy   (0x04 bit0)
#   LD1 = done   (0x04 bit1)
# These require wiring STATUS bits out from top — add output ports if needed.
# Placeholders (comment out if top has no LED ports):
# set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports { led_busy }]
# set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports { led_done }]

# AXI signals to PMOD JA (JA1=awvalid, JA2=awready, JA3=wvalid, JA4=wready,
#                          JA7=bvalid,  JA8=bready,  JA9=arvalid, JA10=arready)
# Uncomment only if you add PMOD ports to top.sv:
# set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports { s_axi_awvalid }]
# ...

# Timing exceptions: none needed for a single-domain 50 MHz design
# All paths are synchronous, single clock
