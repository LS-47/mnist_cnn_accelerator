# Run as: vivado -mode batch -source scripts/run_simulation.tcl -tclargs int8
set precision [lindex $argv 0]
if {$precision ni {int8 int16}} { error "Pass int8 or int16 as the first Tcl argument." }
set root [file normalize [file join [file dirname [info script]] ..]]
set project_name "mnist_cnn_${precision}"
set project_file [file join $root vivado $precision ${project_name}.xpr]
open_project $project_file
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
