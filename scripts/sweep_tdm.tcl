yosys -import

set n_list {2 4 8 16 32}
set results {}

puts "\n========================================================"
puts "  Running TDM SNN Synthesis Sweep (N = 2, 4, 8, 16, 32)"
puts "========================================================\n"

foreach n $n_list {
    puts "\n---> Synthesizing snn_top_tdm with NUM_CLASSES = $n..."
    design -reset

    read_verilog -sv rtl/weight_mac.v
    read_verilog -sv rtl/snn_top_tdm.v

    hierarchy -check -top snn_top_tdm -chparam NUM_CLASSES $n
    synth -top snn_top_tdm

    # Dump statistics to temporary file
    tee -o stat.tmp stat

    # Read and parse stat.tmp
    set fp [open stat.tmp r]
    set stat_data [read $fp]
    close $fp

    set cells 0
    set dffs 0

    # Locate the design hierarchy section
    set hier_idx [string first "=== design hierarchy ===" $stat_data]
    if {$hier_idx != -1} {
        set hier_text [string range $stat_data $hier_idx end]
    } else {
        set hier_text $stat_data
    }

    # Extract Number of cells (format: "     5775 cells" or "Number of cells: 5775")
    if {[regexp {(\d+)\s+cells} $hier_text match val]} {
        set cells $val
    } elseif {[regexp {Number of cells:\s+(\d+)} $hier_text match val]} {
        set cells $val
    }

    # Extract sequential cells (format: "      544   $_SDFFCE_PN0P_")
    foreach line [split $hier_text "\n"] {
        if {[regexp {\s+(\d+)\s+\$_[A-Za-z0-9_]*DFF[A-Za-z0-9_]*} $line match count]} {
            incr dffs $count
        } elseif {[regexp {\s+\$_[A-Za-z0-9_]*DFF[A-Za-z0-9_]*\s+(\d+)} $line match count]} {
            incr dffs $count
        }
    }

    set logic [expr {$cells - $dffs}]
    lappend results [list $n $cells $dffs $logic]
}

puts "\n\n========================================================"
puts "                TDM SYNTHESIS SWEEP RESULTS             "
puts "========================================================"
puts [format "%-6s | %-12s | %-8s | %-12s" "N" "Total Cells" "DFFs" "Logic Gates"]
puts "--------------------------------------------------------"
foreach r $results {
    lassign $r n cells dffs logic
    puts [format "%-6d | %-12d | %-8d | %-12d" $n $cells $dffs $logic]
}
puts "========================================================\n"
