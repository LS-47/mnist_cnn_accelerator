open_project {C:/Users/User/Documents/ChatGPT/FinalYEARproject/mnist_cnn_accelerator/vivado/int8/mnist_cnn_int8.xpr}
puts "sources_top=[get_property top [get_filesets sources_1]]"
puts "simulation_top=[get_property top [get_filesets sim_1]]"
puts "rtl_count=[llength [get_files -of_objects [get_filesets sources_1] -filter {FILE_TYPE == Verilog}]]"
close_project
exit
