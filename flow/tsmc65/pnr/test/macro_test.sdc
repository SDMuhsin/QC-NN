create_clock -name clk -period 3.0 [get_ports clk]
set_input_delay 0.5 -clock clk [get_ports d*]
set_output_delay 0.5 -clock clk [get_ports q*]
set_load 0.01 [all_outputs]
