# Headless read of the Squawk & Talk JTAG probes.
#   ~/intelFPGA_lite/quartus/bin/quartus_stp -t tools/snt_probe.tcl [samples]
# Works against a core the HPS loaded normally - the probe lives in the
# bitstream, so it does not matter who configured the FPGA.
set n 1
if {$argc > 0} { set n [lindex $argv 0] }

set hw ""
foreach h [get_hardware_names] { if {[string match "*DE-SoC*" $h]} { set hw $h } }
if {$hw eq ""} { puts "ERROR: no DE-SoC cable found"; exit 1 }
puts "hardware: $hw"

set dev ""
foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d } }
if {$dev eq ""} { puts "ERROR: no Cyclone V device found"; exit 1 }
puts "device:   $dev"

start_insystem_source_probe -device_name $dev -hardware_name $hw
for {set i 0} {$i < $n} {incr i} {
    set raw [read_probe_data -instance_index 1]
    # raw is a binary string, MSB first
    set hexw [format %024llX [expr {"0b$raw"}]]
    set sig  [string range $hexw 0 1]
    set cmdc [string range $hexw 2 3]
    set lcmd [string range $hexw 4 5]
    set stat [string range $hexw 6 7]
    set pc   [string range $hexw 8 11]
    set wsc  [string range $hexw 12 13]
    set rsc  [string range $hexw 14 15]
    set in2  [string range $hexw 16 17]
    set op4  [string range $hexw 18 19]
    set irqe [string range $hexw 20 21]
    set catr [string range $hexw 22 23]
    set cab  [expr {("0x$in2" & 0x80) ? "UPRIGHT" : "ENVIRONMENTAL"}]
    puts "step=$op4 | cmds=$cmdc last_cmd=$lcmd status=$stat pc=$pc ws=$wsc rs=$rsc | IP2=$in2 ($cab) irq=$irqe cmd_at_read=$catr"
    if {$n > 1} { exec sleep 1 }
}
end_insystem_source_probe
