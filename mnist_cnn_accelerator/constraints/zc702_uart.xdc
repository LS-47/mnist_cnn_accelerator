# ZC702 / XC7Z020-1CLG484C.
# 200 MHz LVDS system oscillator: U43, SYSCLK_P D18, SYSCLK_N C19.
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVDS_25} [get_ports SYSCLK_P]
set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVDS_25} [get_ports SYSCLK_N]
create_clock -period 5.000 -name sysclk_200 [get_ports SYSCLK_P]

# SW5 left user button; pulled high and asserted low when pressed.
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS25} [get_ports resetn]

# External 2.5-V-compatible USB-UART adapter on J62 PMOD2:
# pin 3 / PMOD2_2 / P18 = adapter TX -> FPGA RX; pin 4 / PMOD2_3 / P17 = FPGA TX -> adapter RX.
# These two signals are also wired to user LEDs DS16 and DS15.
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS25} [get_ports uart_rxd]
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS25} [get_ports uart_txd]

# Remaining six PL user LEDs / PMOD signals.
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS25} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS25} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN W17 IOSTANDARD LVCMOS25} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS25} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS25} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS25} [get_ports {led[5]}]

# UART and pushbutton are asynchronous to the 200 MHz board-clock domain.
set_false_path -from [get_ports uart_rxd]
set_false_path -from [get_ports resetn]
set_false_path -to [get_ports uart_txd]
