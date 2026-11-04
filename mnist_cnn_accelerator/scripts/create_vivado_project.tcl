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

# Preserve an existing project and open it; only create a new one when absent.
if {[file exists $project_file]} {
    open_project $project_file
    puts "Opened existing project: $project_file"
    return
}

create_project $project_name $project_dir -part xc7a100tcsg324-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [glob -nocomplain [file join $root rtl $precision *.v]]
add_files -norecurse $rtl_files
set top_name "cnn_${precision}_top"
set_property top $top_name [get_filesets sources_1]

set mem_files [glob -nocomplain [file join $root weights $precision *.mem]]
foreach mem_file $mem_files {
    add_files -fileset sources_1 -norecurse $mem_file
    set_property file_type {Memory Initialization Files} [get_files $mem_file]
}

set sim_top "tb_cnn_${precision}"
set tb_file [file join $root tb ${sim_top}.v]
add_files -fileset sim_1 -norecurse $tb_file
set_property top $sim_top [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]

set xdc_file [file join $root constraints clock_only.xdc]
add_files -fileset constrs_1 -norecurse $xdc_file
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
save_project
puts "Created $precision project: [file join $project_dir ${project_name}.xpr]"
puts "RTL top: $top_name; simulation top: $sim_top"
