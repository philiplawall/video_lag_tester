# Command-line build with Gowin's Tcl shell, equivalent to Synthesize +
# Place & Route in the GUI. Output: impl/pnr/hdmi_out.fs
#
#   gw_sh build.tcl
#
# The language and top-module settings are not stored in hdmi_out.gprj, so
# they are set here. The sources use SystemVerilog constructs.
set here [file dirname [file normalize [info script]]]
open_project $here/hdmi_out.gprj
set_option -top_module lagtester
set_option -verilog_std sysv2017
set_option -output_base_name hdmi_out
run all
