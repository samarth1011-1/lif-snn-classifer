# Build & run the weighted-neuron (single neuron) testbench
# Usage: tclsh scripts/run.tcl   (from the project root)
set rtl [glob rtl/lif_neuron.v rtl/weight_mac.v rtl/spike_counter.v rtl/snn_top_parallel.v ]

set tb_file [glob -nocomplain tb/custom_input_tb.v]

set all_files [concat $rtl $tb_file]

eval exec iverilog -g2012 -o sim/output_custom $all_files

set sim_out [exec vvp sim/output_custom]

puts $sim_out
