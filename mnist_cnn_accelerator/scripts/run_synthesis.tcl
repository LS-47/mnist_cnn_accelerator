# Run as: vivado -mode batch -source scripts/run_synthesis.tcl -tclargs int8
set precision [lindex $argv 0]
if {$precision ni {int8 int16}} { error "Pass int8 or int16 as the first Tcl argument." }
set root [file normalize [file join [file dirname [info script]] ..]]
set project_name "mnist_cnn_${precision}"
set project_file [file join $root vivado $precision ${project_name}.xpr]
open_project $project_file
launch_runs synth_1 -jobs 2
wait_on_run synth_1
open_run synth_1
file mkdir [file join $root reports]
report_utilization -file [file join $root reports ${precision}_utilization_synth.rpt]
report_timing_summary -file [file join $root reports ${precision}_timing_synth.rpt]
close_project
