# Nexys 4 DDR onboard oscillator: 100 MHz (10 ns period).
create_clock -name clk -period 10.000 [get_ports clk]
