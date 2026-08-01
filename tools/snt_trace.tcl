# Dump the last four OP4 writes with timestamps.
set hw ""; foreach h [get_hardware_names] { if {[string match "*DE-SoC*" $h]} { set hw $h } }
set dev ""; foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d } }
start_insystem_source_probe -device_name $dev -hardware_name $hw
set inst 0
foreach i {0 1 2 3} {
    if {![catch {set r [read_probe_data -instance_index $i]}]} {
        if {[string length $r] == 104} { set inst $i }
    }
}
set n 1
if {$argc > 0} { set n [lindex $argv 0] }
for {set k 0} {$k < $n} {incr k} {
    set raw [read_probe_data -instance_index $inst]
    set w [format %026llX [expr {"0b$raw"}]]
    set cnt [expr 0x[string range $w 0 1]]
    puts "OP4 writes since reset: $cnt   (newest first)"
    foreach {vs ts lbl} {2 4 newest 8 10 -1 14 16 -2 20 22 -3} {
        set v [expr 0x[string range $w $vs [expr {$vs+1}]]]
        set t [expr 0x[string range $w $ts [expr {$ts+3}]]]
        puts [format "   %-7s OP4=%02X  nibble=%2d  strobe=%d   t=%9.1f us" \
              $lbl $v [expr {$v & 0x0F}] [expr {($v>>4)&1}] [expr {$t*1.6}]]
    }
    if {$n > 1} { exec sleep 2; puts "" }
}
end_insystem_source_probe
