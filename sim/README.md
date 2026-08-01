# sim/ — Squawk & Talk timing testbenches

Rebuilt 2026-08-01 after the originals were lost to a power cut (they lived
only in scratch — that is why these are committed).

## Why these exist

The board assembles one 8-bit sound command from TWO reads of PIA2 port A,
separated by a delay loop at `$FA57` in `pre.u5`
(`LDAB #$C1 / DECB / BNE *-1`, 193 iterations). The game presents the low
nibble first (with the strobe) and the high nibble **1255 us later**, so the
loop duration is load-bearing: too short and both reads return the low nibble,
the handler assembles a doubled byte, and the dispatcher routes it away from
the speech table. The board is then silent with nothing else wrong.

## tb_speed.v — how many `cen` per E cycle?

    iverilog -g2012 -o tbspd tb_speed.v jt680x*.v && ./tbspd

Answers whether jt680x's `cen` is the crystal or the bus rate. Result: **4 cen
per E cycle**, i.e. `cen` is the crystal rate, so 3.579545 MHz gives the
correct E = 894.886 kHz. It also exposes the real problem — the loop takes
**5** cycles per iteration, not 6, because jt680x is a 6801/6803 core and
6801 branches are 3 cycles where the board's MC6802 (a 6800 part) takes 4.

## tb_time.v — does the delay loop last long enough?

    iverilog -g2012 -DCPU_HZ=2982954 -o tbt tb_time.v jt680x*.v && ./tbt

Measures the loop in wall-clock time using the same 40 MHz fractional enable
`squawk_n_talk.sv` uses. Thresholds come from MAME:

| CPU_HZ | loop | verdict |
|---|---|---|
| 3_579_545 (true crystal) | 1085 us | FAIL — second read beats the host's high nibble |
| 2_982_954 (x 5/6) | 1302 us | PASS — matches the real 6802's 1294 us |

Run this after ANY change to the clock enable or to jt680x.
