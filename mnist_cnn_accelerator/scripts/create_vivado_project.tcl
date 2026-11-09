# Called by setup_vivado_int8.tcl or setup_vivado_int16.tcl.
if {![info exists ::CNN_PRECISION]} {
    error "Set CNN_PRECISION to int8 or int16 before sourcing this script."
}
set precision $::CNN_PRECISION
if {$precision ni {int8 int16}} {
    error "CNN_PRECISION must be int8 or int16."
}

set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set project_name "mnist_cnn_${precision}"
set project_dir [file join $root vivado $precision]
set project_file [file join $project_dir ${project_name}.xpr]
file mkdir $project_dir

# Open an existing project or create it, then converge both paths on the same
# board-ready source set and constraints.
if {[file exists $project_file]} {
    open_project $project_file
    puts "Opened existing project: $project_file"
} else {
    create_project $project_name $project_dir -part xc7a100tcsg324-1
    set_property target_language Verilog [current_project]
    set_property simulator_language Mixed [current_project]
}

set sources [get_filesets sources_1]
set constraints [get_filesets constrs_1]
set rtl_files [concat \
    [glob -nocomplain [file join $root rtl $precision *.v]] \
    [glob -nocomplain [file join $root rtl common *.v]] \
    [list [file join $root rtl board "nexys4ddr_${precision}_top.v"]]]
foreach rtl_file $rtl_files {
    if {[llength [get_files -quiet $rtl_file]] == 0} { add_files -norecurse $rtl_file }
}
set top_name "nexys4ddr_${precision}_top"
set_property top $top_name $sources

set clk_xci [file join $root vivado int8 mnist_cnn_int8.srcs sources_1 ip clk_wiz_0 clk_wiz_0.xci]
if {[llength [get_ips -quiet clk_wiz_0]] == 0} { add_files -norecurse $clk_xci }
if {[llength [get_ips -quiet clk_wiz_0]] > 0} { generate_target all [get_ips clk_wiz_0] }

set mem_files [glob -nocomplain [file join $root weights $precision *.mem]]
foreach mem_file $mem_files {
    if {[llength [get_files -quiet $mem_file]] == 0} {
        add_files -fileset $sources -norecurse $mem_file
        set_property file_type {Memory Initialization Files} [get_files $mem_file]
    }
}

set sim_top "tb_cnn_${precision}"
set tb_file [file join $root tb ${sim_top}.v]
if {[llength [get_files -quiet $tb_file]] == 0} { add_files -fileset sim_1 -norecurse $tb_file }
set_property top $sim_top [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]

foreach old_pin_xdc [get_files -quiet -of_objects $constraints] {
    if {[string match *nexys4ddr_int8_pins.xdc $old_pin_xdc] ||
        [string match *nexys4ddr_int16_pins.xdc $old_pin_xdc]} {
        remove_files $old_pin_xdc
    }
}
foreach xdc_file [list [file join $root constraints clock_only.xdc] \
                      [file join $root constraints nexys4ddr_uart.xdc]] {
    if {[llength [get_files -quiet $xdc_file]] == 0} {
        add_files -fileset $constraints -norecurse $xdc_file
    }
}
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Board-ready $precision project: [file join $project_dir ${project_name}.xpr]"
puts "FPGA top: $top_name; simulation top: $sim_top"
