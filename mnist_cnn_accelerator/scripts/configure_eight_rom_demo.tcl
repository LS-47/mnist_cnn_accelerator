# Configure the currently open INT8 or INT16 ZC702 project to replay
# mnist_eight.png from on-chip ROM. This does not run synthesis or implementation.
if {[current_project -quiet] eq ""} { error "Open the INT8 or INT16 Vivado project first." }
set project_name [get_property NAME [current_project]]
if {[string match *int8 $project_name]} {
    set precision int8
} elseif {[string match *int16 $project_name]} {
    set precision int16
} else {
    error "Open a project whose name ends in int8 or int16; found '$project_name'."
}
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set sources [get_filesets sources_1]
set simset [get_filesets sim_1]
set constraints [get_filesets constrs_1]
set top "zc702_${precision}_image_top"
set tb "tb_mnist_eight_${precision}"

set_property part xc7z020clg484-1 [current_project]
foreach f [concat \
    [glob -nocomplain [file join $root rtl $precision *.v]] \
    [glob -nocomplain [file join $root rtl common *.v]] \
    [list [file join $root rtl board zc702_clock_gen.v] \
          [file join $root rtl board $top.v]]] {
    if {[llength [get_files -quiet $f]] == 0} { add_files -fileset $sources -norecurse $f }
}

set image_mem [file join $root tb data "mnist_eight_pixels_${precision}.mem"]
if {[llength [get_files -quiet $image_mem]] == 0} {
    add_files -fileset $sources -norecurse $image_mem
    set_property file_type {Memory Initialization Files} [get_files $image_mem]
}

foreach f [glob -nocomplain [file join $root weights $precision *.mem]] {
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -fileset $sources -norecurse $f
        set_property file_type {Memory Initialization Files} [get_files $f]
    }
}

set tb_file [file join $root tb "${tb}.v"]
if {[llength [get_files -quiet $tb_file]] == 0} { add_files -fileset $simset -norecurse $tb_file }
set_property top $top $sources
set_property top $tb $simset
set_property xsim.simulate.runtime all $simset

foreach f [get_files -quiet -of_objects $constraints] {
    if {[string equal -nocase [file extension $f] ".xdc"]} { remove_files $f }
}
set xdc [file join $root constraints zc702_image_demo.xdc]
add_files -fileset $constraints -norecurse $xdc
update_compile_order -fileset sources_1

puts "Precision: $precision"
puts "Synthesis top: $top"
puts "Simulation top: $tb"
puts "Image ROM: $image_mem"
puts "Constraints: $xdc"
puts "Configuration only; runs were not launched."
