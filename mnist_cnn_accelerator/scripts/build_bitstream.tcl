# In Vivado batch mode, source this after the board-upgrade script.
set synth_run [get_runs synth_1]
set impl_run [get_runs impl_1]
if {[llength $synth_run] == 0 || [llength $impl_run] == 0} {
    error "Expected synth_1 and impl_1 runs are missing from the open project."
}
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis did not complete. See the Vivado Messages and run log."
}
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set status [get_property STATUS [get_runs impl_1]]
if {![string match *Complete* $status]} {
    error "Implementation/bitstream did not complete (status: $status)."
}
puts "Bitstream build complete. Find the .bit file in the project .runs/impl_1 folder."
