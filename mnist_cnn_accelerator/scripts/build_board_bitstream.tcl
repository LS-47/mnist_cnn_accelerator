# Run with: vivado -mode batch -source scripts/build_board_bitstream.tcl -tclargs int8
# Replace int8 with int16 for the alternate arithmetic configuration.
set precision [lindex $argv 0]
if {$precision ni {int8 int16}} { error "Usage: build_board_bitstream.tcl int8|int16" }
set ::CNN_PRECISION $precision
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir create_vivado_project.tcl]
source [file join $script_dir build_bitstream.tcl]
