# Run as: vivado -mode batch -source scripts/run_simulation.tcl -tclargs int8
set precision [lindex $argv 0]
if {$precision ni {int8 int16}} { error "Pass int8 or int16 as the first Tcl argument." }
set root [file normalize [file join [file dirname [info script]] ..]]
set ::CNN_PRECISION $precision
source [file join $root scripts create_vivado_project.tcl]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
