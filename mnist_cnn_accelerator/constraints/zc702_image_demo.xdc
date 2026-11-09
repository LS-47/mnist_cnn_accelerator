# ZC702 200 MHz differential oscillator
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVDS_25} [get_ports SYSCLK_P]
set_property -dict {PACKAGE_PIN C19 IOSTANDARD LVDS_25} [get_ports SYSCLK_N]
create_clock -name sysclk_200 -period 5.000 [get_ports SYSCLK_P]

# SW5 is an active-high pushbutton (pulled low when released).
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS25} [get_ports reset_btn]
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS25} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS25} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN W17 IOSTANDARD LVCMOS25} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN W5  IOSTANDARD LVCMOS25} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN V7  IOSTANDARD LVCMOS25} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS25} [get_ports {led[5]}]
set_false_path -from [get_ports reset_btn]
