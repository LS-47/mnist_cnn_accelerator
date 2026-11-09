# Run as: vivado -mode batch -source scripts/run_synthesis.tcl -tclargs int8
set precision [lindex $argv 0]
if {$precision ni {int8 int16}} { error "Pass int8 or int16 as the first Tcl argument." }
set root [file normalize [file join [file dirname [info script]] ..]]
set ::CNN_PRECISION $precision
source [file join $root scripts create_vivado_project.tcl]
launch_runs synth_1 -jobs 2
wait_on_run synth_1
open_run synth_1
file mkdir [file join $root reports]
report_utilization -file [file join $root reports ${precision}_utilization_synth.rpt]
report_timing_summary -file [file join $root reports ${precision}_timing_synth.rpt]
close_project
