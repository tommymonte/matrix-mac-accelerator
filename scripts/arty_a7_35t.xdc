# =============================================================================
# constraints/arty_a7_35t.xdc
# Xilinx Design Constraints for matrix-mac-accelerator on Arty A7-35T
#
# Part:  xc7a35tcsg324-1  (commercial, CSG324, speed grade -1)
# Clock: on-board 100 MHz oscillator → pin E3
#
# AXI4-Lite signals non hanno pin fisici assegnati:
# in un demo reale andrebbero su PMOD o via Microblaze.
# Per ora sopprimiamo i warning DRC relativi a I/O non piazzati —
# il timing report rimane comunque valido.
# =============================================================================

# -----------------------------------------------------------------------------
# Clock principale: 100 MHz oscillator on-board
# Period = 10.000 ns  →  target 100 MHz
# -----------------------------------------------------------------------------
create_clock -period 10.000 -name clk [get_ports clk]

# Input/output delay: consenti 2 ns di skew su tutti i boundary I/O
# (conservativo per AXI senza pin fisici, rimuovi quando hai la board)
set_input_delay  -clock clk 2.0 [all_inputs]
set_output_delay -clock clk 2.0 [all_outputs]

# -----------------------------------------------------------------------------
# Reset: BTN0 (active-low pushbutton) → pin C2, LVCMOS33
# -----------------------------------------------------------------------------
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports rst_n]

# -----------------------------------------------------------------------------
# Status LED opzionali (non presenti nel top.sv attuale —
# decommentare se aggiungi output di debug al wrapper)
# LD4 → H5, LD5 → J5, LD6 → T9, LD7 → T10
# -----------------------------------------------------------------------------
# set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports busy_led]
# set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports done_led]

# -----------------------------------------------------------------------------
# AXI4-Lite: nessun pin fisico (solo timing analysis)
# I DRC NSTD-1 e UCIO-1 si lamenterebbero di porte non piazzate —
# li degradiamo a Warning perché il timing report resta valido.
# RIMUOVI queste due righe quando assegni i pin reali (board demo).
# -----------------------------------------------------------------------------
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

# -----------------------------------------------------------------------------
# False path sul reset asincrono
# (rst_n è sincrono nel design, ma Vivado può aprire path spurî
#  attraverso il reset — questo lo esclude dal timing analysis)
# -----------------------------------------------------------------------------
set_false_path -from [get_ports rst_n]
