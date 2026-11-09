# Usage: vivado -mode batch -source scripts/build_zc702_bitstream.tcl -tclargs int8
set precision [lindex $argv 0]
if {$precision ni {int8 int16}} { error "Usage: build_zc702_bitstream.tcl int8|int16" }
set ::CNN_PRECISION $precision
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir setup_zc702_project.tcl]
source [file join $script_dir build_bitstream.tcl]
