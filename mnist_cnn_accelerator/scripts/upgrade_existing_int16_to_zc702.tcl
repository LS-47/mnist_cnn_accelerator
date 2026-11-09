# Migrate the currently open INT16 Vivado project in place to the ZC702.
# Run from the Vivado Tcl Console after opening vivado/int16/mnist_cnn_int16.xpr:
#   source {C:/.../mnist_cnn_accelerator/scripts/upgrade_existing_int16_to_zc702.tcl}
# This configures the project only; it does not launch synthesis or implementation.

if {[current_project -quiet] eq ""} {
    error "Open vivado/int16/mnist_cnn_int16.xpr first, then source this script."
}

set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set project_name [get_property NAME [current_project]]
if {$project_name ne "mnist_cnn_int16"} {
    error "Expected the existing mnist_cnn_int16 project; current project is '$project_name'."
}

set_property part xc7z020clg484-1 [current_project]
set sources [get_filesets sources_1]
set constraints [get_filesets constrs_1]

foreach f [concat \
    [glob -nocomplain [file join $root rtl int16 *.v]] \
    [glob -nocomplain [file join $root rtl common *.v]] \
    [list [file join $root rtl board zc702_int16_top.v] \
          [file join $root rtl board zc702_clock_gen.v]]] {
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -fileset $sources -norecurse $f
    }
}

# Ensure all quantized weights and biases are available as initialization files.
foreach f [glob -nocomplain [file join $root weights int16 *.mem]] {
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -fileset $sources -norecurse $f
        set_property file_type {Memory Initialization Files} [get_files $f]
    }
}

# Remove the locked legacy Clocking Wizard; the ZC702 wrapper uses this RTL MMCM.
set clk_xci [get_files -quiet -all *clk_wiz_0.xci]
if {[llength $clk_xci] > 0} { remove_files $clk_xci }

# Replace the active board pin map with the ZC702 assignments.
foreach f [get_files -quiet -of_objects $constraints] {
    if {[string equal -nocase [file extension $f] ".xdc"]} {
        remove_files $f
    }
}
set zc_xdc [file join $root constraints zc702_uart.xdc]
if {![file exists $zc_xdc]} { error "Missing ZC702 constraints file: $zc_xdc" }
add_files -fileset $constraints -norecurse $zc_xdc

set_property top zc702_int16_top $sources
update_compile_order -fileset sources_1

puts "Updated the existing project in place: [get_property NAME [current_project]]"
puts "Part: [get_property PART [current_project]]"
puts "Synthesis top: [get_property TOP $sources]"
puts "Active XDC: $zc_xdc"
puts "ZC702 200 MHz differential input -> MMCM -> 10 MHz CNN/UART clock. No runs were launched."
