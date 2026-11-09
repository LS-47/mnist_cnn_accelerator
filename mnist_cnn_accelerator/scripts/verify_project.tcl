set precision [lindex $argv 0]
if {$precision ni {int8 int16}} { error "Pass int8 or int16 as the first Tcl argument." }
set root [file normalize [file join [file dirname [info script]] ..]]
set ::CNN_PRECISION $precision
source [file join $root scripts create_vivado_project.tcl]
puts "sources_top=[get_property top [get_filesets sources_1]]"
puts "simulation_top=[get_property top [get_filesets sim_1]]"
puts "rtl_count=[llength [get_files -of_objects [get_filesets sources_1] -filter {FILE_TYPE == Verilog}]]"
close_project
exit
