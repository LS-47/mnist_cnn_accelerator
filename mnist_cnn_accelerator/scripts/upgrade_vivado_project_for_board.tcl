# Run in Vivado Tcl Console after opening the INT8 or INT16 .xpr:
#   set CNN_PRECISION int8
#   source C:/.../mnist_cnn_accelerator/scripts/upgrade_vivado_project_for_board.tcl
if {![info exists ::CNN_PRECISION] || $::CNN_PRECISION ni {int8 int16}} {
    error "Set CNN_PRECISION to int8 or int16 before sourcing this script."
}
set precision $::CNN_PRECISION
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set top_name "nexys4ddr_${precision}_top"

if {[current_project -quiet] eq ""} {
    open_project [file join $root vivado $precision mnist_cnn_${precision}.xpr]
}

set sources [get_filesets sources_1]
set constraints [get_filesets constrs_1]
foreach f [glob -nocomplain [file join $root rtl $precision *.v]] {
    if {[llength [get_files -quiet $f]] == 0} { add_files -norecurse $f }
}
foreach f [glob -nocomplain [file join $root rtl common *.v] \
                         [file join $root rtl board "nexys4ddr_${precision}_top.v"]] {
    if {[llength [get_files -quiet $f]] == 0} { add_files -norecurse $f }
}
foreach f [glob -nocomplain [file join $root weights $precision *.mem]] {
    if {[llength [get_files -quiet $f]] == 0} {
        add_files -fileset $sources -norecurse $f
        set_property file_type {Memory Initialization Files} [get_files $f]
    }
}

# Both board builds use the same 100 MHz -> 10 MHz Clocking Wizard.
set clk_xci [file join $root vivado int8 mnist_cnn_int8.srcs sources_1 ip clk_wiz_0 clk_wiz_0.xci]
if {[llength [get_ips -quiet clk_wiz_0]] == 0} {
    add_files -norecurse $clk_xci
}
if {[llength [get_ips -quiet clk_wiz_0]] > 0} {
    generate_target all [get_ips clk_wiz_0]
}

# Remove legacy pixel-switch pin maps; this board top uses UART and LEDs.
foreach f [get_files -quiet -of_objects $constraints] {
    if {[string match *nexys4ddr_int8_pins.xdc $f] ||
        [string match *nexys4ddr_int16_pins.xdc $f] ||
        [string match *nexys4ddr_uart.xdc $f]} {
        remove_files $f
    }
}
foreach f [list [file join $root constraints clock_only.xdc] \
                [file join $root constraints nexys4ddr_uart.xdc]] {
    if {[llength [get_files -quiet $f]] == 0} { add_files -fileset $constraints -norecurse $f }
}

set_property top $top_name $sources
update_compile_order -fileset $sources
update_compile_order -fileset sim_1
puts "Board top set to $top_name. UART is 115200 8-N-1; send 784 pixel bytes, receive one ASCII digit."
