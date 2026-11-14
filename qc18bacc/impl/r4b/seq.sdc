# R4b standalone sequencer: impl/constraints.sdc + IO delays of its chip context: inputs come from registers of
# qb_top / qb_act2 (0.3 ns), outputs feed ~0.5 ns of qb_act2 / qb_top logic before their registers (0.6 ns).
source [file dirname [info script]]/../constraints.sdc
set data_in [remove_from_collection [all_inputs] [get_ports {clk rst_n}]]
set_input_delay  0.3 -clock qb_clk $data_in
set_output_delay 0.6 -clock qb_clk [all_outputs]
