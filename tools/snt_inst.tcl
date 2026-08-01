set hw ""; foreach h [get_hardware_names] { if {[string match "*DE-SoC*" $h]} { set hw $h } }
set dev ""; foreach d [get_device_names -hardware_name $hw] { if {[string match "*5CSE*" $d]} { set dev $d } }
start_insystem_source_probe -device_name $dev -hardware_name $hw
for {set i 0} {$i < 4} {incr i} {
    if {[catch {set raw [read_probe_data -instance_index $i]} err]} {
        puts "instance $i : (none)"
    } else {
        puts "instance $i : probe width [string length $raw]"
    }
}
end_insystem_source_probe
