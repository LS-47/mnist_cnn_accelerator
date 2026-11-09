# Usage (batch): vivado -mode batch -source scripts/setup_zc702_project.tcl -tclargs int8
# In the GUI Tcl Console: set CNN_PRECISION int8; source scripts/setup_zc702_project.tcl
if {[info exists ::CNN_PRECISION]} {
    set precision $::CNN_PRECISION
} elseif {[llength $argv] > 0} {
    set precision [lindex $argv 0]
} else {
    error "Set CNN_PRECISION to int8/int16, or pass it as the first -tclargs value."
}
if {$precision ni {int8 int16}} { error "Precision must be int8 or int16." }

set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set project_name "mnist_cnn_${precision}_zc702"
set project_dir [file join $root vivado zc702 $precision]
set project_file [file join $project_dir ${project_name}.xpr]
file mkdir $project_dir

if {[file exists $project_file]} {
    open_project $project_file
    set_property part xc7z020clg484-1 [current_project]
} else {
    create_project $project_name $project_dir -part xc7z020clg484-1
    set_property target_language Verilog [current_project]
    set_property simulator_language Mixed [current_project]
}

set top_name "zc702_${precision}_top"
set sources [get_filesets sources_1]
set constraints [get_filesets constrs_1]
set sim_files [get_filesets sim_1]

foreach f [concat \
    [glob -nocomplain [file join $root rtl $precision *.v]] \
    [glob -nocomplain [file join $root rtl common *.v]] \
    [list [file join $root rtl board "${top_name}.v"] \
          [file join $root rtl board zc702_clock_gen.v]]] {
    if {[llength [get_files -quiet $f]] == 0} { add_files -fileset $sources -norecurse $f }
}

foreach f [glob -nocomplain [file join $root weights $precision *.mem]] {
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -fileset $sources -norecurse $f
        set_property file_type {Memory Initialization Files} [get_files $f]
    }
}

set xdc [file join $root constraints zc702_uart.xdc]
if {[llength [get_files -quiet -of_objects $constraints $xdc]] == 0} {
    add_files -fileset $constraints -norecurse $xdc
}

set_property top $top_name $sources
set tb [file join $root tb "tb_cnn_${precision}.v"]
if {[llength [get_files -quiet -of_objects $sim_files $tb]] == 0} {
    add_files -fileset $sim_files -norecurse $tb
}
set_property top "tb_cnn_${precision}" $sim_files
set_property xsim.simulate.runtime all $sim_files

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Created/opened $project_file for XC7Z020-1CLG484."
puts "Top: $top_name; system clock: 200 MHz differential -> MMCM -> 10 MHz CNN/UART clock."
puts "External UART adapter uses J62 pins 3/4 at 115200 baud, 8-N-1."
