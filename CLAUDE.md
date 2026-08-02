# CLAUDE.md — Arcade-MCR3_MiSTer (Squawk & Talk prototype)

Upstream clone of `MiSTer-devel/Arcade-MCR3_MiSTer` (Cyclone V / DE10-Nano),
living inside the parent project's **gitignored** `refs/` directory. It is its
own git repo — commits here do not touch the parent, and the parent will never
see this file.

**Why we are working in it.** The parent project (`../../CLAUDE.md`, Bally
Midway MCR cores on Sipeed Tang Gowin boards) wants **speech for Discs of Tron
(Environmental)** — the Bally **Squawk & Talk** board. Upstream MiSTer has never
implemented it, and neither have we. The Tang Console 60K merged core is at
**116/118 BSRAM**, so prototyping there means fighting the block budget and the
Gowin toolchain at the same time as debugging a brand-new speech synthesiser.

So: **build Squawk & Talk here first**, on a platform with spare BRAM, a mature
toolchain, real simulation, and a reference emulator to diff against. Once it
makes correct speech on MiSTer, port it to `mcr3_console60k` /
`mcr123s_console60k`. Nothing about the port is blocked by doing it this way —
`src/rtl/mcr3.vhd` in the parent is a patched copy of `rtl/mcr3.vhd` here, and
`src/rtl/pia6821.vhd` is already vendored there.

**Do not point the parent's build at this directory.** Copy files out
deliberately, with a dated comment, per the parent's `refs/` rule.

## The headline fact: `dotron` has no speech; `dotrone` does

This is the thing to not re-derive. Verified against `~/mame` (`-listxml`):

| Set | Sound hardware |
|---|---|
| `dotron`, `dotrona` (Upright) | `midssio` + `ay8910` only — **no speech board exists on this PCB** |
| `dotrone`, `dotronep` (Environmental) | the above **plus** `squawk_n_talk`: `m6802`, 2× `pia6821`, **`tms5200`**, `ad558`, `filter_rc` |

Upstream's `releases/Discs of Tron.mra` is the **upright** set, and so is the
parent's `dotron` spec in `tools/merge_roms.py`. Both are complete and correct
as they stand. Adding speech means adding a **new game variant** (`dotrone`),
not fixing an existing one.

Corollary worth knowing before scoping: **no other game in the parent's 15-game
roster uses Squawk & Talk.** Kozmik Kroozr and Wacko are SSIO-only in MAME,
contrary to the obvious guess. This work buys exactly one variant.

Two stale claims in the parent's docs, to fix when this lands:
- `docs/mcr_core_roadmap.md:203` — "Squawk & Talk = 6809 + TMS5200". It is a
  **6802**. (6809 is the *Turbo Cheap Squeak*, a different board.)
- `docs/mcr_core_roadmap.md:21` — "DoT speech absent upstream" reads as an
  upstream gap; it is absent from the emulated hardware too.

## Build (headless)

Quartus Prime **17.0.2 Lite** at `~/intelFPGA_lite` (the exact MiSTer version;
`Arcade-MCR3.qsf` pins `LAST_QUARTUS_VERSION "17.0.2 Lite Edition"`). Cyclone V
device support is installed. Target `5CSEBA6U23I7` (set in `sys/sys.tcl:2`, not
in the project `.qsf`).

```sh
cd refs/Arcade-MCR3_MiSTer
~/intelFPGA_lite/quartus/bin/quartus_sh --flow compile Arcade-MCR3
```

Output: `output_files/Arcade-MCR3.rbf` (the `.qsf` sets `GENERATE_RBF_FILE ON`).
A full compile is tens of minutes — run it in the background and poll, do not
block on it. Build artefacts (`db/`, `incremental_db/`, `output_files/`) land in
this tree; they are upstream-gitignored.

**Add source files to `files.qip`, never through the Quartus GUI** — the GUI
rewrites `Arcade-MCR3.qsf` and mangles it. The `.qsf` says so in a banner at the
top, and it is the same class of trap as the parent's
`impl/<project>_process_config.json` churn.

Sanity checks per build: zero critical warnings about inferred latches or
truncated ports in `output_files/Arcade-MCR3.map.rpt`, and check timing closure
in `.sta.rpt` — Cyclone V has room here, so a timing failure means a real
structural mistake, not a budget problem.

## How the existing core is wired (what the S&T work plugs into)

**Game select** is the MRA `mod` byte, `ioctl_index==1` (`Arcade-MCR3.sv:456`):
`0=tapper, 1=timber, 2=dotron, 3=journey`. A `dotrone` variant becomes `mod==4`
plus a `mod_dotrone` reg alongside the four at `Arcade-MCR3.sv:450-461`. Note
`mod_dotron` also drives `video_hflip` (`:568`) and the coin mapping (`:388`),
so `dotrone` must set those the same way — easiest as
`wire mod_dotron_any = mod_dotron | mod_dotrone`.

**ROM download map** (`Arcade-MCR3.sv:296-306`, offsets are `ioctl_addr`):

```
00000 - 0DFFF   Main CPU ROM   (8 bit)  -> cpu_rom dpram AND sdram port1
0E000 - 11FFF   SSIO sound ROM (8 bit)  -> sdram port1, read at 16'h7000 + snd_addr[13:1]
12000 - 31FFF   Sprite ROMs    (32 bit) -> sdram port2 (sp_ioctl_addr = addr - 0x12000)
32000 - 39FFF   BG ROMs                 -> dl_addr = addr - 0x32000, into the core
```

The Squawk & Talk region is **`3A000 - 3DFFF`** — **16 KB, not 12** — into a
plain dpram (`snt_rom`) in the top. 16 KB because it then maps 1:1 onto the
6802's `$8000-$BFFF` ROM window with no address arithmetic: the MRA zero-fills
the unpopulated U2 socket at `$8000`, and `pre.u3/u4/u5` land at
`$9000/$A000/$B000` exactly as MAME loads them. Cyclone V has the blocks to
spare — that is the whole point of prototyping here.

**`0x3A000` is not 16 KB aligned**, so the region base must be *subtracted*
(`snt_ioctl_addr = ioctl_addr - 25'h3A000`), the same pattern as `sp_ioctl_addr`
and `dl_addr`. Masking with `ioctl_addr[13:0]` instead rotates the ROM by
`0x2000` inside the RAM — which lands the reset vector in the wrong place and is
completely invisible until step 3 puts a 6802 there to fetch it.

**Trap in that map:** `port1_we` and `port2_we` are both tied to bare
`rom_download` (`:320`, `:336`), so *every* downloaded byte is also written into
SDRAM at its mapped address regardless of region. The region at `0x3A000` lands
at `sp_ioctl_addr = 0x28000` in port2 space, past the 32K-word sprite window the
core reads — harmless, but verify rather than assume if the region moves.
Likewise `cpu_rom`'s write enable is `!ioctl_addr[24:16]`, so only
`0x00000-0x0FFFF` reaches it.

**`output_4` is already brought out** — `Arcade-MCR3.sv:448/579`, sourced from
the SSIO's OP4 latch inside `rtl/mcr_sound_board.vhd:446`. Journey already uses
bit 0 for wave-player pause (`:631`). This is the bus Squawk & Talk hangs off,
so no core surgery is needed to get at it. (In the parent, `mcr3.vhd` exports
the same port but the merged top leaves it unconnected at
`mcr123s_console60k_top.sv:1911`.)

**Audio** mixes at `Arcade-MCR3.sv:552-557`: `audio_l/r` from the core, with
Journey's `wave_sound` PCM summed in for `mod_journey`. S&T output adds a third
summand, gated on `mod_dotrone`. Watch `AUDIO_S` (`:553`) — it is currently
`mod_journey`, i.e. signed only for Journey. The TMS5200 output is **signed**,
the AD558 DAC output is **unsigned**; get the mix into one convention before it
reaches `AUDIO_L/R`.

## What Squawk & Talk is (authoritative: `~/mame`)

`~/mame/src/mame/shared/ballysound.cpp`, `bally_squawk_n_talk_device`. Discs of
Tron uses the **base** variant — **no AY-3-8910** on this board (the `ay8910`
in `dotrone`'s device list belongs to the SSIO):

- **MC6802** @ 3.579545 MHz → E clock ÷4 ≈ **894.9 kHz**
- **2× PIA 6821**
- **TMS5200** @ **640 kHz** (ROMCLK = 160 kHz)
- **AD558** 8-bit DAC + RC filters

Memory map (`squawk_n_talk_map`):

```
0000 - 007F   internal 6802 RAM (128 B — inside the CPU, not in the map)
0080 - 0083   PIA2          mirror 0x4F6C
0090 - 0093   PIA1          mirror 0x4F6C
1000          AD558 DAC     mirror 0x40FF
8000 - BFFF   ROM (U2..U5)  mirror 0x4000  <-- the mirror at C000-FFFF is what
                                               supplies the 6802 reset vector
```

`dotrone` loads only U3/U4/U5 (`pre.u3` @ 0x9000, `pre.u4` @ 0xA000,
`pre.u5` @ 0xB000) — 12 KB; U2 @ 0x8000 is empty.

**The 0x4000 mirror is not a detail — the board executes out of it.** Reading
the vectors straight out of `pre.u5` (verified 2026-07-30):

| Vector | Address | Value |
|---|---|---|
| IRQ | `$FFF8` | `$FA45` |
| SWI | `$FFFA` | `$F983` |
| NMI | `$FFFC` | `$F974` |
| RESET | `$FFFE` | `$F983` |

Every target is in the `$C000-$FFFF` **mirror**, not the `$8000-$BFFF` base
window (`$F983 - $4000 = $B983`, inside `pre.u5`). So decode the ROM on
**`cpu_addr[15]` alone, ignoring `cpu_addr[14]`**, with
`rom_addr = cpu_addr[13:0]` — one decode covering base and mirror. Decode only
`$8000-$BFFF` and the 6802 resets to an unmapped address; the board is then
silent with no other symptom to chase.

**Host → board** (`~/mame/src/mame/bally/mcr.cpp:565`, `dotron_op4_w`, installed
by `init_dotrone` at `:3068` as SSIO custom output 4):

| OP4 bits | Meaning |
|---|---|
| 3:0 | `sound_select` (MD3-0) — read back on PIA2 port A as `~sel & 0x1F` (through inverters) |
| 4 | `sound_int` — **inverted** into PIA2 **CB1** |
| 6 | backlight / flasher (J1-4) |
| 7 | flasher strobe enable (J1-3) |
| 5..0 | lamp sequencer, latched on rising edge of bit 5 (the `edotlamp.u2` PROM) |

Lamps are cosmetic — ignore them for the speech milestone.

**Internal wiring** (`device_add_mconfig`):
- PIA1 PA ↔ TMS5200 data bus (read = `status_r`, write = `data_w`)
- PIA1 PB[0] → `/RS`, PB[1] → `/WS`
- TMS5200 READY → PIA1 **CA2**, TMS5200 /INT → PIA1 **CB1**
- PIA2 PA (read) = `~sound_select & 0x1F`; PIA2 CA2 → a front-panel LED
- **All four PIA IRQ lines OR'd → 6802 IRQ**

The 6802 runs LPC data out of its own ROM into the TMS5200 FIFO — this is
**Speak External** mode only. There is **no TMS6100 VSM / phrase ROM** on this
board, so any VSM interface in a donor core can be tied off and deleted.

## References — what we have and where

**ROMs: already on disk, nothing to acquire.** `../../roms/dotron.zip` carries
the whole `dotrone/` subfolder: `pre.u3` (crc `c3d0f762`), `pre.u4`
(`7ca79b43`), `pre.u5` (`24e9618e`) = the 12 KB S&T ROM, plus `edotlamp.u2` and
the Environmental CPU/SSIO ROMs. A `dotrone` MRA has to be written by hand —
upstream ships only the upright one.

**TMS5200 gateware, option A — `zeldin/Mega99`, `gateware/tms5200/`**
(Verilog, **LGPL-3.0**). Implements the chip from the patent schematics
(US4335277A). Clean Verilog-2001, no vendor primitives, two `$readmemh` files.
**Its `tms5200_parameter_rom.hex` carries the genuine TMS5200 coefficient set** —
verified here: its pitch table reads `000 00E 00F 010 011 …`, exactly MAME's
`TI_2501E_PITCH`. Use `tms5200_vsp` directly and drop `tms6100_vsm` and the
whole wishbone ROM port; `tms5200_dac.v` gives the audio sample.

**TMS5220 gateware, option B — `MiSTer-devel/Arcade-Qix_MiSTer`,
`rtl/cpu/TMS5220/source/TMS5220.vhd`** (d18c7db, **GPL-3.0**). Written against
the MAME driver and log-verified against it sample-for-sample; implements
**Speak External only**, which is exactly our mode. Nicely packaged single
entity with a straight `I_DBUS/O_DBUS + /WS + /RS + READY + /INT` interface.

**The Qix repo is the better structural template overall** — `rtl/Qix_Sound.sv`
builds essentially the same board (6802 + 2× PIA6821 + TMS5200 + 8-bit DAC),
and also carries **`rtl/sound/jt680x/`** (Jotego's 6800/6801 core, GPL-3),
wired there as an MC6802 with the 6801-only interrupts tied low. That
instantiation is worth copying almost verbatim.

**But its coefficient tables are the 5220's, not the 5200's** — their own
comment concedes the shortcut ("using TMS5220 core — functionally equivalent").
Confirmed here: their `ktable` K1 begins `-501,-498,-497,-495,…`
(MAME `TI_5110_5220_LPC`), whereas the TMS5200's is `-501,-498,-495,-490,…`
(`TI_2801_2501E_LPC`). The **pitch table and all ten K tables differ** between
the parts; energy, chirp and interpolation are shared. Using it unmodified
gives speech with wrong pitch and wrong formants — intelligible-ish, but not
right, and easy to mistake for a bug elsewhere. Either swap in MAME's
`T0285_2501E_coeff` (`~/mame/src/devices/sound/tms5110r.hxx:588`) or use
Mega99's ROM, which is already correct.

**Reference emulator, for diffing:** `~/mame` is a full source tree.
`src/devices/sound/tms5220.cpp` has extensive comments on 5200-vs-5220
behavioural differences (`TMS5220_IS_5200`, `:1729`). d18c7db's README documents
the technique that got their core to match: compile the MAME driver standalone,
dump internal state per sample, diff against a testbench log. That is the method
to reuse — a testbench that streams `pre.u3-u5`'s LPC frames and diffs against
MAME is worth far more than staring at waveforms.

**Already available, do not rewrite:** `../../src/rtl/pia6821.vhd` (vendored into
the parent with Cheap Squeak Deluxe). The PIA is done.

## Implementation order

1. **Baseline build green** — compile upstream unmodified, confirm the toolchain
   and keep the `.rbf` + resource numbers as the delta reference.
2. **`dotrone` as a new `mod==4` variant, speech stubbed** — MRA, S&T ROM region
   at `0x3A000`, `mod_dotrone` reg, `output_4` decode. Game must still boot and
   play exactly like `dotron`. Ship-able on its own.
3. **`squawk_n_talk.sv`** — jt680x in 6802 mode + 2× `pia6821` + DAC, memory map
   above, TMS5200 **stubbed** (READY always true, /INT idle). Verify the 6802
   runs, takes IRQs, and writes plausible LPC bytes at the FIFO — before any
   speech core is in the picture.
4. **Drop in the TMS5200**, correct coefficient tables. Diff against MAME.
5. **Mix into `AUDIO_L/R`**, sort out the signed/unsigned convention.
6. **Then** port to `mcr3_console60k`, and only after that fight
   `mcr123s_console60k`'s 116/118 BSRAM (where the 12 KB ROM ≈ 6 blocks has to
   come out of SDRAM, alongside the SSIO sound ROM that already lives there).

Clocking, when it comes up: everything is clock-enables off the core's 40 MHz
`clock_40`. 6802 E ≈ 894.886 kHz → 40e6/894886 ≈ 44.7, so a **fractional**
enable, not an integer divider. TMS5200 wants 640 kHz with a 160 kHz ROMCLK-rate
`clk_en` (Mega99's core is written against that 160 kHz enable, not the 640 kHz
pin clock — read its port comments before wiring it).

## Status

**Baseline upstream compile: GREEN (2026-07-30).** Unmodified upstream at
`1ec8944`, Quartus 17.0.2 Lite, full compile in **5:07** — 0 errors, 0 critical
warnings, 115 ordinary warnings. Keep these as the delta reference:

| Metric | Baseline |
|---|---|
| ALMs | 11,897 / 41,910 (28%) |
| Registers | 16,574 |
| Block memory | 1,356,581 bits (24%) — **192 / 553 M10K (35%)** |
| DSP | 35 / 112 (31%) |
| PLLs | 3 / 6 |
| Worst setup slack | +0.580 ns (TNS 0.000 on every clock) |
| Worst hold slack | +0.250 ns (TNS 0.000 on every clock) |
| `output_files/Arcade-MCR3.rbf` | 3,054,920 bytes |

That `.rbf` size is in family with `releases/Arcade-MCR3_20260417.rbf`
(3,042,116), which is the sanity check that the build is real and not a
degenerate fit.

**The headroom that justifies prototyping here**: 65% of M10K and 72% of ALMs
free. The 12 KB Squawk & Talk ROM is ~10 M10K — noise on this device, versus 6
of the 2 remaining BSRAM blocks on the Tang merged core.

"Design is not fully constrained for setup/hold" in the STA log is normal for
MiSTer (`sys/` leaves the HPS-side paths unconstrained) — not a regression
signal. Judge future builds by the table above.

**Step 2 (dotrone selectable, speech stubbed): BUILDS CLEAN (2026-07-30).**
0 errors, 118 warnings — the 3 over baseline are the expected "assigned but
never read" on the shell's two registers. Delta vs baseline:

| Metric | Baseline | Step 2 |
|---|---|---|
| ALMs | 11,897 | 11,891 |
| Registers | 16,574 | 16,493 |
| Block memory bits | 1,356,581 | **1,356,581 (identical)** |
| Worst setup / hold | +0.580 / +0.250 ns | +0.659 / +0.148 ns |

**The identical block-memory figure is the expected result, not a bug**: the
16 KB `snt_rom` has no consumer yet (the shell drives `rom_addr` to 0 and
ignores `rom_do`), so Quartus strips it whole. Step 3 is where the numbers move.

Verified without hardware:
- MRA byte layout walked programmatically — every region boundary lands where
  the top's decode expects, `pre.u3/u4/u5` at `$9000/$A000/$B000`, total
  `0x3E000`. All 30 parts resolve **by CRC** against `../../roms/dotron.zip`.
- The 6802 vector table (see the mirror section above).

**Step 2 RUNS ON HARDWARE (2026-07-30).** Deployed to the bench MiSTer and
launched via mrext; `/api/games/playing` reports `core: dotrone`. The **entire
attract cycle** was captured by screenshot and is correct:

1. POINT VALUES (HIT SARK / GRAZE SARK / SUPER CHASERS) — sprites, palette, text
2. attract gameplay demo — arena, discs, both players, HIGH 12000
3. title card — DISCS OF TRON / BALLY MIDWAY MFG CO / COPYRIGHT MCMLXXXIII

So the MRA assembles, `mod==4` decodes, and the dotrone CPU/SSIO ROM revision
boots and plays. No regression to the other four sets (they resolve to the
untouched `MCR3` core — see the naming note below).

**Honest gap: the Environmental cabinet strap is not yet independently
confirmed.** IP2 bit 7 is wired per MAME's `dotrone` port definitions, but
`dotrone` does not check for the speech board at boot, so the attract cycle
looks identical either way — there is no free signal here. (MAME documents a
"SOUND BOARD INTERFACE ERROR" only for `dotronep`, the prototype.) The natural
confirmation is step 3: once a 6802 exists, OP4 traffic from the game becomes
observable, and SignalTap over the working JTAG link is the way to watch it.

**The MRA part names had to change to match the real ROM set.** The first draft
used current-MAME names (`loc-cpu1`, `ssi_o_loc-a_disc_of_tron_aug_19`); the
zip actually in circulation is the old **merged** `dotron.zip`, where the clone
ROMs live under a **`dotrone/` prefix** (`dotrone/loc-cpu1`, `dotrone/loc-a`,
`dotrone/pre.u3`) and only the shared gfx sits at the root. CRCs are identical
either way — only the names differ. Two things were confirmed against MRAs
already installed on the bench machine before relying on them:
- **path-style names work** (e.g. `atlantis2/boa_1.2c` in Battle of Atlantis)
- **`<part repeat="N">00</part>` zero-fill works** (widely used)

**Deployed as `MCR3SNT`, deliberately not `MCR3`.** MiSTer resolves an MRA's
`<rbf>` tag against `_Arcade/cores/<name>_<date>.rbf`, so dropping this build in
as `MCR3_<newer date>.rbf` would silently have become the core for Tapper,
Timber, Journey and the upright Discs of Tron too. The work-in-progress speech
core stays isolated to its own MRA until it is finished:
`_Arcade/cores/MCR3SNT_20260730.rbf` + `<rbf>mcr3snt</rbf>`.

### Step 3 — 6802 + PIAs + DAC (TMS5200 still stubbed)

Vendored (both GPL-3.0, both already proven together in Arcade-Qix):
- `rtl/jt680x/` — jt680x.v + _ctrl/_alu/_regs, plus **`6801.vh`,
  `6801_param.vh` and the 4096x40 microcode `6801.uc`**. The modules
  `` `include `` the first two and `$readmemb` the third, all by bare filename,
  so **`files.qip` must carry `set_global_assignment -name SEARCH_PATH
  rtl/jt680x`** or none of them resolve.
- `rtl/pia6821.vhd` — byte-identical to `../../src/rtl/pia6821.vhd` (only a
  provenance header differs), deliberately, so the Tang port is a move not a
  rewrite.

Implementation notes that cost thought:
- **`cen` is the CRYSTAL rate, not E.** jt680x's header says
  "crystal clock freq. = 4x E pin freq.", so cen = 3.579545 MHz and
  E = 894.886 kHz. 40e6/3.579545e6 = 11.1745, so it must be a **fractional**
  phase-accumulator enable, not a counter compare.
- **PIA `cs` must be a one-cycle pulse.** `pia6821.vhd` commits a write on any
  rising clock with `cs=1, rw=0`, so a level-held select writes repeatedly for
  the whole CPU cycle. Gate with `cen`. `rw` is 6800 polarity: 1 = read.
- **Decode by mirror MASK, not by range.** MAME states the mirrors as
  don't-care masks; since the board demonstrably executes through the ROM
  mirror, range compares would miss the aliases its code actually uses.
  PIA2 `(addr & B090) == 0080`, PIA1 `== 0090`, DAC `(addr & BF00) == 1000`,
  ROM `addr[15]` with `addr[14]` ignored.
- The 128 B internal RAM is **not** in jt680x (it is a bare CPU core) and not
  in MAME's map either (it is inside the 6802) — it has to be added here.
- Audio mix clamps at **both** ends: unsigned core audio plus a signed board
  offset. Clamping only the top wraps loud negative swings to full scale,
  which sounds like a broken speech core rather than a broken mixer.

**Step 3 builds clean and runs on hardware** — 0 errors, 120 warnings; dotrone
still boots and plays (attract demo captured), so no regression from adding the
board. Delta vs step 2:

| Metric | Step 2 | Step 3 |
|---|---|---|
| ALMs | 11,891 | 13,028 (+1,137) |
| Registers | 16,493 | 16,603 |
| Block memory bits | 1,356,581 | 1,488,932 (+132,351) |
| Core clock (clk_sys) setup slack | — | +1.401 ns |

The +132,351 bits is `snt_rom` (131,072) + `iram` (1,024) landing in M10K —
they are real now, not stripped. **jt680x's microcode does NOT go to block
RAM**: `6801.vh` reads it asynchronously (`assign ucode_data =
ucode_rom[uaddr]`), which no M10K can do, so 4096x40 bits go to logic/MLAB —
that is the +1,137 ALMs. Far less than the naive 2,560 because the unused
microcode bit slices get stripped. Expect the same, or worse, on Gowin.

### Observability — read this before adding a probe

**`LED_USER` is NOT usable in this core.** `sys/sys_top.v:184` hard-assigns
`assign LED_USER = VGA_TX_CLK;` with the normal assignment commented out on the
line above. The core's `led_user` still reaches **`LED[0]` on the DE10-Nano**
(`sys_top.v:157`, `~led_u` = `led_user`) and the I/O-board LEDs via the
MCP23009, but not the `LED_USER` pin. Either way it needs eyes on the bench.

**The probe that actually works remotely: `status[8]` "S&T Probe".** The module
exports **`seen`** — sticky, set on the first non-zero sound command and held
until reset — and the top forces the blue channel when it is set. Sticky is the
whole point: a single mrext screenshot answers the question, whereas an LED or
a 0.17 s pulse needs lucky timing. Blue reads unmistakably against this game's
red/purple palette.

**OP4[3:0] IS DUAL-PURPOSE — do not treat it as a speech signal.** The first
version of this probe triggered on any change of `sound_select` (OP4[3:0]) and
lit up brightly. It was wrong. Re-reading `dotron_op4_w`: those same four bits
feed the Squawk & Talk MD3-0 *and* the lamp sequencer (J1-4 enable, J1-5
sequence select, J1-6 speed, latched on bit 5's rising edge). The game drives
that nibble for lamps on **any** cabinet, so activity there says nothing about
speech. **The real strobe is OP4 bit 4** (`sound_int`), which MAME routes
inverted into PIA2 CB1 to interrupt the 6802 — rising edges of *that* are the
"game is commanding the speech board" event. The probe now counts those, and
requires **two** before latching so a single reset glitch cannot pass for
traffic.

**Always run the falsification control.** `mod == 5`
(`releases/zzz Discs of Tron (Env, strap=Upright CONTROL).mra`) is not a real
machine: it is the Environmental ROM set with the cabinet strap forced to
Upright, everything else identical, shipped as its own MRA so it can be
launched over mrext without OSD access. The strap decode is deliberately keyed
to `mod_dotrone` alone; the board, probe, LED and audio mux all follow
`mod_dotrone_any`, so both variants are instrumented identically and the strap
is the single variable.

That control is what caught the dual-purpose-nibble mistake — it lit just as
brightly as Environmental did. **A probe that cannot be shown to go dark proves
nothing.** Delete the control MRA once the speech core is finished.

### The probe as it stands: three sticky bits in the backdrop colour

Only already-black pixels are tinted, so the game stays fully visible and one
screenshot carries three independent facts:

| Channel | Signal | Means |
|---|---|---|
| RED | `cpu_run` | 6802 address bus has changed 255 times — it is fetching |
| GREEN | `dac_written` | 6802 has written the AD558 — executing board code |
| BLUE | `seen` | OP4 bit 4 has changed twice — host is commanding us |

Read the dominant background colour: black = nothing, red = CPU alive but idle,
yellow = running board code with no host traffic, white = all three.

**Count EITHER edge on OP4 bit 4, not just rising.** MAME inverts that line into
CB1 (`cb1_w(!param)`), so whether a command appears as 0->1 or 1->0 depends on
the board's idle level, which is not documented anywhere checkable. A pulse of
the unexpected polarity would be invisible to a rising-edge detector.

### Step 3 measured results (2026-07-30, hardware)

**CONFIRMED — the 6802 executes.** RED lit, stable across every frame. That
retires a whole class of doubt at once: the `$4000` mirror decode is right, the
fractional 3.579545 MHz `cen` is right, the 16 KB ROM window is right, and the
vendored jt680x + its microcode work under Quartus. The board is alive.

**CONFIRMED — the game does NOT strobe OP4 bit 4 during attract mode**, in
either polarity. BLUE stays dark across every frame of the attract cycle.

**CONFIRMED — the game DOES write OP4[3:0] during attract** (that is what lit
the first, mistaken, version of the probe). Consistent with the lamp sequencer
sharing those bits.

**CONFIRMED — the 6802 never writes the DAC.** GREEN dark. Expected: it has
received no command to act on.

**CONFIRMED — the game DOES strobe OP4 bit 4, but only during GAMEPLAY.**
Measured with a real game in progress: backdrop went red `(102,0,0)` ->
magenta `(102,0,102)` and stayed there. Discs of Tron's speech is a
gameplay event, so **attract mode alone can never settle any speech question** —
do not debug this game from the attract screen.

That also means the host path works end to end (game Z80 -> SSIO OP4 -> board)
and strongly implies **IP2 bit 7 is being read as Environmental**, since an
upright cabinet has no speech board to command. Not yet proven outright: the
decisive test is starting a game under the `mod == 5` strap=Upright control and
checking that BLUE stays dark. Worth doing before trusting the strap.

### Step 4 — TMS5200 in, no stubs left (2026-07-31)

Vendored `rtl/tms5200/` from **zeldin/Mega99** (LGPL-3.0): `tms5200_vsp` plus
crom/prom/fifo/bstack/kstack/multiplier/pram/dac and the two coefficient hex
files. **`tms6100_vsm` is deliberately NOT used** — Squawk & Talk has no phrase
ROM, the 6802 streams LPC itself, so the chip only runs Speak External and the
VSM pins tie off.

Chosen over the Qix TMS5220 because its `tms5200_parameter_rom.hex` is the
genuine **TMS5200** table (pitch verified against MAME `TI_2501E_PITCH`), so it
needs none of the 5220->5200 coefficient surgery.

**Polarities — all measured, none guessed.** Every one inverts relative to the
chip pins the PIA wires to:

| Model signal | Convention | Evidence |
|---|---|---|
| `rs`, `ws` | ACTIVE HIGH | Mega99: `.rs(enable_vsp && sbe && !a[5])` |
| `rdy` | ACTIVE HIGH ready | Mega99 ANDs into `sysrdy`; sim shows `rdy=1` after reset |
| `int_o` | ACTIVE HIGH | sim shows `int=1` (buffer low) after 64 bytes streamed |

So `.rs(~pia1_pb_o[0])`, `.ws(~pia1_pb_o[1])`, `tms_ready = ~rdy` into CA2,
`tms_int_n = ~int_o` into CB1.

`clk_en` is **160 kHz** (ROMCLK = 640 kHz / 4; Mega99's `clkgen.v` says so).
40 MHz / 160 kHz = 250 exactly — a plain divider, unlike the 6802's fractional
enable.

**THREE TRAPS, all of which cost a build or nearly did:**

1. **`int` is a SystemVerilog keyword.** Marking the vendored files
   `VERILOG_FILE` is NOT enough — the *instantiation* lives in
   `squawk_n_talk.sv`, which is SystemVerilog, and `.int(...)` is rejected at
   the CALL SITE. The port is renamed to **`int_o`** in `tms5200_vsp.v` (three
   occurrences, header documents it). The Tang port will hit this too; its tops
   are SystemVerilog as well.
2. **Verilog concatenation is UNSIGNED.** `{dac_centered, 6'b0}` silently threw
   away the sign and turned every negative DAC sample into a large positive
   one. Sign-extend first, then shift; saturate rather than wrap. A wrapped mix
   sounds like a broken speech core.
3. **Two benign warnings that look alarming.** `truncated value with size 12 to
   match size of target (10)` on the parameter ROM is just the hex file's
   3-digit literals — all 272 values max out at `0x3FD` and fit. `Memory depth
   (64) differs from (52)` on the chirp ROM is Quartus rounding a 52-entry
   array up and zero-filling. Both verified, neither is a real truncation.

**Result: RED=7, GREEN=7 in attract mode** — the 6802 drives TMS /WS during
board init, as real hardware does at power-on. Every digital link in the chain
is confirmed. What is NOT yet confirmed is the audio itself: whether it sounds
like speech, and whether it sounds *right*. That needs ears, not a screenshot.

### THE THIRD STEP-4 BUG: a pulsed data bus read as if it were held

`tms5200_vsp` drives its data bus only during the internal read strobe:

```verilog
assign dq = ({8{c1}} & data_reg) | ({8{c2}} & { talkst, bl, be, 5'b00000 });
```

That is a **one-`clk_en` pulse** (160 kHz); every other cycle `dq` reads 0. A
real TMS5220 drives the bus for as long as `/RS` is asserted. Squawk & Talk's
6802 asserts `/RS`, **waits for `/READY`**, and only then reads the port — by
which point the pulse is long gone, so it sampled `0x00` = `TS=0 BL=0 BE=0`,
which decodes as "buffer full, do not send". The board obediently sent nothing.

Fix: export `dq_valid = c1 | c2` from the core (second minimal local change,
alongside the `int` -> `int_o` rename) and hold the value in the wrapper, the
way the bus transceiver does:

```verilog
always @(posedge clk) if (tms_dq_valid) tms_dq_hold <= tms_dq;
assign tms_status = tms_dq_hold;
```

**SPEECH WORKS IN SIMULATION after this.** Measured:

| | before | after |
|---|---|---|
| status read | `00` | `60` (BL,BE) then **`80` = TS=1, talking** |
| /WS edges | 22 | **186** |
| /RS edges | 6 | **5999** |
| `tms_audio_nz` | 0 | **1** |

Healthy trace: `SPEAK EXTERNAL`, then `ddis=1` and ~90 LPC data bytes stream in
while status polls flip `TS` high.

### COMMAND MAP (disassembled from pre.u5, verified in simulation)

Dispatcher at `$F180`, reached from the IRQ handler with the assembled byte:

| assembled byte | goes to |
|---|---|
| `$07-$0F` | table `$F2D8` |
| `$10-$27` | table `$F538` |
| **`$28-$38`** | **table `$F235` — SPEECH (~17 phrases)** |
| `$39-$BF` | **IGNORED** — straight back to the wait loop |
| `$C0-$CF` / `$D0-$DF` | handlers `$F13D` / `$F15B` |
| `$E0-$EF` / `$F0-$FF` | handlers `$F936` / `$F943` |

`assembled = ~( ((~hi & 0x1F) << 4) + ((~lo & 0x1F) & 0x0F) )`

**To reach the speech table the HIGH nibble must be 3**; the low nibble then
selects the phrase (`$30`+low = table index low+8). Verified in simulation:
low=0/high=3 -> `$30` -> 68 TMS writes, `tms_audio_nz=1`, speech.

`$F1C9: LDAA $04 / BEQ *` is the idle loop the probe kept showing as `pc=F1C9`.

**SUPERSEDED — this paragraph is WRONG, see "THE GAME WAS ASKING FOR SPEECH ALL
ALONG" below (2026-08-01).** ~~Nibbles observed from the game: 8 and 11. As a
pair those assemble to `$B8`/`$8B`, both in the IGNORED range; doubled they give
`$88`/`$BB`, also ignored. So during the sampled sessions the game was genuinely
not requesting speech — the board's silence was correct behaviour, not a
defect.~~ 8 and 11 are the LOW NIBBLES of `$38` and `$2B`, both of which are
genuine speech commands. The high nibble is carried by the *other* write.

### THE SOUND COMMAND IS 8 BITS SENT AS TWO NIBBLES

Disassembly of the IRQ handler at `$FA45` (in `pre.u5`):

```
$FA54: LDAA $80      ; read PIA2 port A   (FIRST  read -> low nibble)
$FA57: LDAB #$C1 / DECB / BNE *           ; ~193 iters -- ~1300 us, NOT 650.
                                          ; DECB+BNE is 6 cycles on a 6800,
                                          ; 193*6 = 1158 cy / 894.886 kHz.
                                          ; MEASURED in MAME: reads land
                                          ; 231 us and 1535 us after the
                                          ; strobe. The 650 us figure was a
                                          ; 2x error and it matters -- see
                                          ; the read/write race below.
$FA5C: LDAA $80      ; read PIA2 port A   (SECOND read -> high nibble)
$FA5E: ASLA x4 / PULB / ANDB #$0F / ABA / COMA
$FA67: JMP $F180     ; dispatch on the assembled byte
```

**So OP4[3:0] carries HALF a command.** The game writes one nibble, strobes,
then writes the other; the board samples port A twice ~650 us apart and
assembles them. `last_cmd` from the JTAG probe is therefore only ever one
nibble — do not read it as a command number.

This also explains why the simulation "worked": the testbench HELD
`sound_select`, so both reads returned the same nibble and produced a
degenerate-but-valid byte that happened to select a real phrase. Right by
accident. A faithful testbench must present two different nibbles with the
correct spacing.

### FIDELITY: MEASURED against real-cabinet recordings (2026-08-01)

Reference wavs in the repo root: `tron_greetings_arcadeyoutube.wav` and
`tron_youtube_phrases.wav` are REAL CABINET captures from YouTube;
`tron1.mp4.wav` is OUR output. (Do not mix these up — the analysis is
meaningless reversed.)

**FOUND AND FIXED — no reconstruction filter on the speech output.**

| | 95% rolloff | energy > 4 kHz |
|---|---|---|
| ours, before fix | 8500-10000 Hz | **22-29%** |
| real cabinet | 3500-4800 Hz | 3-6% |
| ours, brick-walled at 4 kHz | 3502 Hz | 0% |

`tms5200_dac` emits an 8 kHz STAIRCASE held across 20 of the 160 kHz clk_en
ticks, so its 8/16/24 kHz images went straight into the mix. A real TMS5220
cannot produce content above ~4 kHz; the board filters it in analog (MAME
models a filter on the speech output too). Fix: two cascaded one-pole IIRs at
the 160 kHz tick, shift 3 (~3.2 kHz corner, -12 dB/oct). This is almost
certainly what "sounds harsh / not quite the same" was.

**Rate is essentially CORRECT — a 2x error is ruled out.** Pitch, after
correcting for autocorrelation octave errors:

| | fundamental |
|---|---|
| real cabinet, phrases | 206 Hz (103 Hz was a subharmonic) |
| real cabinet, greetings | 183 Hz |
| ours, hardware capture | 229 Hz |
| ours, simulation (cmd `$30`) | 216 Hz |

~10% high, and different phrases have different pitch, so this is within noise.
The 160 kHz `clk_en` (ROMCLK = 640 kHz / 4) is sound.

**Still to do:** a SAME-PHRASE comparison. Identify which sweep step is
"GREETINGS", capture it, and compare against `tron_greetings_arcadeyoutube.wav`
(183 Hz). That is the only way to settle the residual 10%.

### SUPERSEDED: earlier speculation about speech fidelity

Parked deliberately (2026-08-01) — getting speech at all was the milestone.
User compared against a YouTube recording of a real Environmental cabinet: the
speech is recognisably speech and sounds good, but not quite the same. Expected
first phrase on start is **"GREETINGS"**.

Candidates, cheapest first — none investigated yet:

1. **`clk_en` rate.** 160 kHz is taken from Mega99's `clkgen.v` comment
   (ROMCLK = 640 kHz / 4), never measured. Wrong here shifts pitch and
   speed together. Compare a capture against a real recording's pitch.
2. **Which phrase.** If the assembled 2-nibble command differs from the real
   machine's, a *different* phrase plays and nothing is wrong with synthesis
   at all. Check by forcing known command bytes and cataloguing what each says.
3. **Coefficient set.** `tms5200_parameter_rom.hex` was verified to be the
   genuine 5200 pitch table (MAME `TI_2501E_PITCH`), so this is unlikely — but
   the chirp/energy tables were never cross-checked against MAME.
4. **Interpolation / frame rate.** Mega99 implements the patent's behaviour;
   MAME notes real 5200s differ subtly from the patent in places
   (`tms5220.cpp` around `TMS5220_IS_5200`).

Best debugging route: capture MiSTer audio during a known phrase and compare
spectrally against MAME's `dotrone` output for the same command — MAME is the
reference and runs locally.

### SPEECH WORKS ON HARDWARE (2026-08-01) — confirmed by ear

Discs of Tron (Environmental) speaks on the bench MiSTer, and it sounds right.
JTAG probe captured mid-phrase:

```
cmds=06 last_cmd=03 status=80 pc=F285 ws=FF rs=FF   <- TS=1, talking
cmds=06 last_cmd=03 status=60 pc=F1CB ws=FF rs=FF   <- done, back to idle
```

`status=80` is TALK STATUS set; `pc=F27E/F285` is the 6802 inside the speech
routine; `ws`/`rs` saturated at 255 from LPC streaming. Full path proven:
host command -> interrupt -> handler -> SPEAK EXTERNAL -> LPC stream -> audio.

**SUPERSEDED (2026-08-01).** ~~THERE WAS NEVER A FOURTH BUG. The apparent
"hardware doesn't speak" was this: the game only issued commands 8 and 11
during the sampled play sessions, and simulation confirms neither is a speech
cue.~~ Both halves of that are wrong: 8 and 11 are LOW NIBBLES of real speech
commands, and there IS a fourth bug — a read/write race. See the next two
sections. The one true part: injecting command **3** made it speak instantly,
because a doubled nibble 3 assembles to `$33`, which IS a speech command.

### THE GAME WAS ASKING FOR SPEECH ALL ALONG (2026-08-01)

Settled from the GAME's Z80 ROM (`dotrone/loc-cpu1..4` concatenated = `$0000`-
`$DFFF`, so file offset == CPU address) and confirmed against MAME. Twelve
`OUT ($04),A` sites exist; only three matter:

| Site | What it is |
|---|---|
| `$79EB` / `$79F8` | backlight on/off (bit 6) — the `40`/`00` writes |
| `$95CD`-`$95D8` | LAMP SEQUENCER triple: value, `SET 5`, `AND $C0`. The `44`,`64`,`40` burst ~4 us apart. Nothing to do with speech |
| `$9548` / `$993E` | **the speech pair** |

```
$9526: LD A,($E420) / BIT 4,A / JR Z   ; speech-pending flag
$9539: LD A,($E4D6) / RRCA x4 / AND $0F / RES 4,A / OR B
$9548: OUT ($04),A                     ; HIGH nibble, strobe LOW
...
$9927: LD A,($E420) / BIT 4,A / RET Z
$9933: LD A,($E4D6) / AND $0F / SET 4,A / OR B
$993E: OUT ($04),A                     ; LOW nibble, strobe HIGH
```

`$E4D6` holds the whole 8-bit command and has **exactly one writer**, `$7E0B`,
inside `speak(A)` at **`$7DF9`**:

```
$7DF9: PUSH AF / LD A,($E517) / OR A / JR NZ -> POP AF, RET   ; gate
$7E05: LD HL,$E420 / DI / SET 4,(HL) / LD ($E4D6),A / EI / RET
```

So **speech is gated on `($E517)==0`**, and there are six `speak()` call sites:

| Call site | Command byte |
|---|---|
| `$0913` | `$2A` |
| `$0921` | `$2B` |
| `$0B04` | `$2E` |
| `$0C52` | `$33` or `$2E` |
| `$9F26` | `$30` |
| `$D347` | from a table at `$D330`: `$32`, `$33`, `$36`, `$37`, `$38` |

Every one lands in **`$28`-`$38`**, the speech dispatch table at `$F235`. That
is the answer to "which command numbers are speech cues".

**ORDER AND TIMING, measured in MAME** (`$993E` fires first):

```
speak($32):  t+0 us     OP4=12   low nibble 2, strobe HIGH   <- interrupts board
             t+1255 us  OP4=03   high nibble 3, strobe LOW
board:       t+231 us   reads PIA2A = 1D  (= ~2, the low nibble)
             t+1535 us  reads PIA2A = 1C  (= ~3, the high nibble)  -> SPEAKS
```

**The margin is only ~165 us.** The board's second read must land after the
host's second write, and only ~165 us separates them on the reference.

### THE FOURTH BUG — FOUND AND FIXED, IN-GAME SPEECH WORKS (2026-08-01)

**Fix: `CPU_HZ = (3_579_545 * 5) / 6` in `squawk_n_talk.sv`.** jt680x is a
6801 core (3-cycle branches); the board's MC6802 is a 6800 (4-cycle), so the
193-iteration delay loop between the handler's two command reads ran 1078 us
instead of 1294 us and the second read beat the game's second nibble. Full
reasoning is in the source; `sim/tb_time.v` regression-tests it.

Confirmed on hardware with a game in progress:

```
cmds=02 last_cmd=0B status=60 ws=FF rs=FF cmd_at_read=1D   <- $2B assembled
cmds=03 last_cmd=07 status=60 ws=FF rs=FF cmd_at_read=1C   <- $37 assembled
cmds=04 last_cmd=02 status=80 pc=F289 ws=FF rs=FF          <- TALKING
```

`ws` went from stuck at `14` (init only) to **saturated `FF`** = LPC streaming,
`status=80` is TALK STATUS, and `pc=F289` is inside the speech routine. Three
different commands assembled correctly. Read `cmd_at_read` against the
COMPLEMENT of the expected HIGH nibble (`$2B` -> `1D`, `$37` -> `1C`); it is
easy to misread because `~2` and the old broken value are both `1D`.

### SUPERSEDED — the diagnosis that led there

Measured on the bench, `mcr123s`-era build `df1c6209`, with a game running:

```
cmds=03  last_cmd=02  cmd_at_read=1D  status=60  ws=14  pc=F1C9
trace newest: OP4=03 (nibble 3, strobe 0)
```

`last_cmd=02` (low nibble) + trace `03` (high nibble) = the game asked for
**`$32`**, a real speech command from the `$D330` table. But `cmd_at_read=1D`
is `~2` — **the SECOND read saw the LOW nibble again**, not `1C`. The board
therefore assembles a doubled byte `$22`, which falls in the `$10`-`$27` range
and is dispatched away from speech. `ws` frozen at 20 and `status=60` confirm
no LPC ever streamed. **The board is behaving correctly; it is being handed the
wrong byte.**

Which side is off is NOT yet established — either our 6802 reaches its second
read too early, or our host presents the high nibble too late. The 4-entry
trace buffer cannot separate them (lamp traffic floods the window, and its
16-bit/1.6 us timestamp wraps every 105 ms).

**Next step: a transaction probe.** Capture, for ONE command, four timestamps —
the strobe write, the high-nibble write, and BOTH PIA2 port A reads — and latch
them until read. That single measurement says which side to fix. Do not add
another sticky boolean; this is a timing question and needs timestamps.

### Driving the bench remotely: uinput (2026-08-01)

**mrext DOES have input endpoints — the earlier "no usable input API" was
wrong**, and so was the method that produced it. Guessing routes with GET is
useless: the catch-all answers *everything* with HTTP 200 + 916 bytes of HTML,
so a 200 proves nothing. **Probe with POST and compare the response SIZE.**
Two real routes found that way:

| Route | Argument | Result |
|---|---|---|
| `POST /api/controls/keyboard/{name}` | symbolic, e.g. `volume_up` | 200; `unknown key: X` + 500 for anything else |
| `POST /api/controls/keyboard-raw/{code}` | Linux keycode int | 200; 500 `strconv.Atoi` on a non-integer |

The binary confirms them: `main.setupApi.HandleKeyboard.func30`,
`HandleRawKeyboard.func31`, `control.SendRawKeyboardDown/Up`. Note
`keyboard-raw` accepts ANY integer (99999 returns 200), so a 200 is not
evidence the key did anything.

**Neither route could insert a coin through the JOYSTICK MAPPING layer** —
`CREDITS 0` regardless, and `joy[]` is what `m_coin1`/`m_start1` normally come
from. Why that layer ignores an injected keyboard is still unexplained.

**The fix is to bypass it: decode raw PS/2 scancodes in the core.** `hps_io`
hands every core `ps2_key` regardless of joystick mapping (it is how the
computer cores get typing), so `Arcade-MCR3.sv` now decodes `5`/`1`/`2`
(scancodes `$2E`/`$16`/`$1E`) straight to coin/start and ORs them with the
joystick bits — no change for a human at the bench, and coin/start now work
over HTTP:

```sh
curl -X POST http://<mister>:8182/api/controls/keyboard-raw/6   # '5' = coin
curl -X POST http://<mister>:8182/api/controls/keyboard-raw/2   # '1' = start
```

Linux keycodes, not PS/2 ones, on the wire. **Movement/fire still go through
`joy` and still do not work remotely** — enough to start a game and let it run,
which is all the speech work needed. Extend the decode if a future job needs
real play.

**Do not send F12 blind.** It opens the OSD, and subsequent injected keys then
navigate the MENU instead of the game — that is how a probing session
accidentally launched `sharpmz` over a running test. If you must, verify the
core afterwards with `/api/games/playing` or `cat /tmp/CORENAME`.

A hand-rolled fallback lives in `tools/mister_key.py` (scp to `/tmp`): the
MiSTer has `/usr/bin/python3` and `/dev/uinput`, and the device does appear
(`/sys/class/input/event*/device/name` shows `mrext-virtual-kbd` alongside
MiSTer's own `MiSTer virtual input` and mrext's `mrext`). Whether MiSTer acts
on it is the open question.

Instead: the MiSTer has **`/usr/bin/python3` and `/dev/uinput`**, and MiSTer
hot-plugs input devices. `tools/mister_key.py` (scp to `/tmp`) creates a
virtual keyboard and injects MiSTer's arcade defaults — `5`=Coin 1, `1`=Start
1, arrows, LCtrl/LAlt/Space. Verified: coin+start took the game from
`cmds=00` to `cmds=03` with no hands on the bench. This makes the whole
in-game speech path measurable over SSH.

Note the bench box answers on **two** addresses; `192.168.1.75` is the fast
NIC and the one with SSH keys installed. `.198` currently refuses port 22.

### MAME as the reference harness — how to drive it

`~/mame/mame` is a working v0.244 build. `dotrone` needs the SSIO PROM, which
is not in `dotron.zip`: build a `midssio.zip` holding `82s123.12d` (copy it out
of `kickman.zip`) and add its directory to `-rp`.

Traps, both of which cost a run:
- **`-noplugins` is required.** `~/mame/plugins` is newer than the binary and
  its `layout` plugin calls `add_machine_frame_notifier`, which does not exist
  in 0.244 — the failure is reported against *your* script, not the plugin.
- Redirecting stdout block-buffers everything until exit; use `stdbuf -oL`.

OP4 is written by the MAIN Z80 into its own I/O space (offsets `$04`-`$07`,
`midway_ssio_device::ioport_write`, `which = offset >> 2`), so a Lua write tap
sees every one with no rebuild:

```lua
TAP = manager.machine.devices[":maincpu"].spaces["io"]
        :install_write_tap(0x00, 0x1f, "op4", function(offset, data, mask) ... end)
```

Keep a GLOBAL reference to the tap — a collected tap silently stops firing.
The S&T side is tappable too: `:snt:cpu` program space, `$0080` = PIA2 port A
(the two command reads), `$0090` = PIA1 port A (the TMS5200 data bus).

To trigger speech on demand without playing, poke `speak()`'s own state —
`$E4D6` = command byte, then set bit 4 of `$E420` — and let the game's own
routines emit the pair. That reproduces the real ordering exactly.

**Ordinary play DOES request speech — it just needs varied input.** A fixed
wiggle pattern over 150 s produced ZERO strobes, which nearly led to the wrong
conclusion that speech is vanishingly rare. Feeding pseudo-random stick/button
input instead gives **3 strobes in 60 s** (`tools/mame_op4long.lua`):

```
*** STROBE t=20.20 pc=$9940 data=5A nib=10   -> $?A   (call site $0913 = $2A)
*** STROBE t=52.13 pc=$9940 data=56 nib= 6   -> $?6   ($D330 table)
*** STROBE t=56.47 pc=$9940 data=57 nib= 7   -> $?7   ($D330 table)
pc=$954A 3 writes                            -> the matching high-nibble writes
```

So a session that sees no strobe means the PLAY was too repetitive, not that
the game is quiet. Judge by strobe COUNT over varied input, never by absence.

Two MAME operational notes:
- `-skip_gameinfo` skips the startup information screen. Runs complete with or
  without it here, but it removes a whole class of "is it hung?" ambiguity on
  a headless run and costs nothing — use it.
- **Every run exits with SIGSEGV (rc=139) after printing its results.** MAME
  0.244 crashes on teardown here. It is harmless: `emu.register_stop` has
  already run and the log is complete. Do NOT read rc=139 as a failed run.

**Two measurement mistakes to not repeat**, both of which sent this chase down
wrong paths for several cycles:

1. **A sticky flag cannot answer a per-event question.** The command sweep's
   `tms_audio_nz` stayed latched after command 3 spoke, so commands 4-15 all
   read as "SPEAKS". Reading the `ws` traffic column instead shows only
   command 3 ever streamed. Use counters/deltas, not booleans, for "did this
   happen *now*".
2. **A testbench that holds an input steady cannot reproduce a fault caused by
   that input changing.** The sim held `sound_select`; hardware rewrites it.
   That difference was invisible until the JTAG probe measured both the value
   at the strobe (`last_cmd`) and at the handler's read (`cmd_at_read`) — which
   turned out to match, killing the theory, but only measurement could show it.

### RESOLVED: the "simulation speaks, hardware does not" divergence

Same RTL, same ROM, two different outcomes:

| | simulation | hardware |
|---|---|---|
| /WS after command | **186 edges** (streaming) | ~22 (init only) |
| status read | `60` -> **`80` TS=1** | — |
| `tms_audio_nz` | **1** | **0** |
| probe | — | `R=7 G=7 B=1` (strobe only) |

Hardware gets through init, configures both PIAs, takes the host interrupt, and
toggles /WS a few times — then stops, exactly where it did before the `dq` fix.
Simulation with the identical RTL streams ~90 LPC bytes and talks.

**So the testbench differs from the machine somewhere that matters.** Candidates,
roughly in order of suspicion — none of these has been tested yet:

1. **The command value.** The testbench sets `sound_select = 3` once and pulses
   the strobe. On hardware OP4[3:0] is SHARED WITH THE LAMP SEQUENCER and the
   game rewrites it constantly, so the nibble the board latches at interrupt
   time may not be a speech cue at all. Cheapest test: log OP4 writes on
   hardware, or sweep `sound_select` 0..15 in the testbench and see which values
   produce speech.
2. **The patched ROM.** Simulation runs `snt_rom_fast.hex` with the `LDX #20000`
   delay loops shortened. That should be behaviourally neutral, but it has NOT
   been confirmed — re-run the sim against the unpatched image to rule it out.
3. **Reset timing.** The core's `reset` is asserted during ROM download on
   hardware; the testbench simply deasserts once. If the board initialises the
   TMS before the download finishes, its 9x RESET sequence lands on a chip whose
   ROM data is still arriving.
4. **Speech may be a rare game event** that the sampled play sessions never hit.
   The probe bits are sticky, so this only holds if no speech cue was ever
   issued during play.

The sim harness in `sim/` is the tool for 1 and 2 and costs nothing per run.

### ALL THREE STEP-4 BUGS WERE INTERFACE BUGS, NOT LOGIC BUGS

Every vendored core was correct. Each fault was this project connecting it with
a wrong assumption about timing or drive:

| Bug | Wrong assumption |
|---|---|
| double-registered ROM read | that `dpram`'s output still needed latching |
| PIA output register w/o direction | that `pb_o` reflects the pin when `DDR=0` |
| pulsed data bus read as held | that `dq` stays valid after the read strobe |

**Check these three things first when porting to Gowin.** None of them produce
an error, a warning, or a failed build — all three present as a board that is
demonstrably alive and silently does nothing.

### THE BUG THAT COST STEP 4: PIA output register used without its direction

**A 6821 comes out of reset with DDR = 0 — its port pins are INPUTS.** On the
real board, pull-ups hold `/RS` and `/WS` HIGH (inactive) until the ROM sets
`DDRB` at `$FA12`. Driving the TMS5200 from `pia1_pb_o` (the output *register*,
which reads 0 at reset) presents **both strobes asserted** from power-on. That
is a reset condition on a 5220-class part, and in Mega99's model it leaves
`ldce_gate` set, which blocks every subsequent command load. The speech chip was
wedged before the board ever spoke to it.

```verilog
// WRONG: ignores direction, drives both strobes low out of reset
.rs(~pia1_pb_o[0]), .ws(~pia1_pb_o[1])

// RIGHT: an undriven bit reads high, which is what a pull-up does
wire [7:0] pia1_pb = pia1_pb_o | ~pia1_pb_oe;
.rs(~pia1_pb[0]),   .ws(~pia1_pb[1])
```

**Generalise this for the Tang port:** any signal taken off a 6821 that is
open-drain or pulled up on the real PCB needs `x_o | ~x_oe`, never `x_o`. Same
for port A and for CA2/CB2.

Measured effect (simulation, same testbench either way):

| | before | after |
|---|---|---|
| progress | `011` | **`111`** |
| /WS edges | 3 | **22** |
| DAC written | no | **yes** |

**How it was found — the method, not the luck.** Bench probing said 6802
healthy, PIAs configured, IRQ working, exactly ONE /WS edge, no audio. That is
consistent with a dozen causes. Tracing the board ROM in simulation showed the
6802 parked at `$F2BF`:

```
$F2BF: LDAA $91    ; PIA1 CRA
$F2C1: ASLA        ; IRQA2 (the CA2 flag) into sign
$F2C2: BPL  $F2BF  ; spin until the TMS asserts /READY
```

One byte written, /WS asserted, waiting forever for a `/READY` that could never
come. That points at exactly one wire.

### Simulating this board — the practical notes

- **`ghdl synth --std=08 -fsynopsys --out=verilog pia6821.vhd -e pia6821`**
  translates the VHDL PIA to Verilog so iverilog can run the WHOLE board. This
  is the trick that makes any mixed-language MiSTer/Tang core simulatable —
  the parent repo is full of VHDL that can now be co-simulated.
- **The board's power-on sequence is LONG.** A 128-byte x 256-value RAM test
  (~16M clocks, and `BNE *` is its failure trap) followed by an LED-blink
  sequence with `LDX #20000` delay loops. Under ~25M clocks the sim is still
  initialising, which is indistinguishable from "hung". `snt_rom_fast.hex`
  patches the delay constants (detector: `LDX #large` followed by `DEX/BNE *-1`)
  — SIMULATION ONLY.
- The RAM test passing is a free proof that the `iram` implementation is
  byte-correct; the board checks it more thoroughly than any testbench would.

### THE BUG THAT COST STEP 3: double-registered ROM read

**Never re-register `dpram`'s output.** `dpram.vhd` registers `q_b` internally
(`q_b <= ram(addr_b)` on `clk_b`). `squawk_n_talk` then latched that *again* at
`cen_d`, which hands the CPU the byte from the PREVIOUS address:

```
edge N   (cen)    jt680x drives the new address; dpram samples the OLD one
                  (its value before the edge)      -> q_b = ram[A_old]
edge N+1 (cen_d)  a second latch captures ram[A_old].  Stale by one.
```

Arcade-Qix does not hit this because it reads an **inferred array** directly at
`cen_d` — one register stage total. Routing through `dpram` silently adds a
second. Copying the *shape* of their pipeline without accounting for the
different memory primitive is what introduced it. The address is stable for
~45 clocks per bus cycle, so the fix is simply to use dpram's registered output
as-is: `wire [7:0] rom_do_r = rom_do;`.

**Why it was so hard to see.** The 6802 fetched garbage, crashed, re-read the
reset vector, and looped forever. Every liveness probe read TRUE — address bus
moving, internal RAM touched, ROM returning non-zero — while it never reached a
single PIA. "Alive" and "working" are not the same measurement, and a
crash-loop satisfies every cheap definition of alive.

### SIMULATE. It is faster than the bench, and it is where this was caught.

`sim/` holds the harness (`tb.v` ideal, `tb_hw.v` modelling the exact hardware
pipeline, `tb_fix.v` with the fix), plus `snt_rom.hex` built from the real
`pre.u3/u4/u5`. Rebuild it with iverilog:

```sh
cd sim && iverilog -g2012 -o tb tb.v jt680x*.v && ./tb
```

Healthy output: reset vector at `$FFFE`, execution at `$F983`, stack writes to
`$007F/$007E`, then **first PIA access at bus cycle 19** (`0091, 0093, 0081,
0083, 0080, 0090` — textbook 6821 DDR/control init). `tb_hw.v` instead reports
`pia_touched=0` and loops `fffe -> f983`.

Three hardware round-trips at ~5 minutes each narrowed nothing; one 30-second
simulation found the bug and a second proved the fix before it was built. Once
static reasoning stops narrowing the problem, go to simulation — not to another
bitstream. The same harness will validate the step-4 TMS5200 handshake without
touching the bench at all.

**mrext has no usable input API from here.** `/api/controls/keyboard/...` and
the `raw` variants all fall through to the SPA catch-all (HTTP 200 + HTML), and
the binary could not be located to extract its routes (it runs as `/tmp/remote.sh`,
`/tmp/.mrext/` is not readable). Four attempts, then stopped. **Coin/start has
to be pressed at the bench**; screenshot immediately after and read the
backdrop colour.

`active` (the 0.17 s pulse) and `dbg_dac` / `dbg_cpu_addr` / `dbg_tms_wsn/rsn`
remain as ready-made SignalTap taps for cycle-level work.

**The TMS5200 stub is the thing most likely to mislead in step 4.** It returns
status `0x60` (buffer low + buffer empty, not talking) with READY asserted and
/INT idle, deliberately chosen to keep the board's speech loop moving rather
than wedging. Both handshake polarities are ASSUMPTIONS — re-derive them from
the datasheet against the real core rather than carrying them over.

## Hardware access

A MiSTer is on the bench and reachable two ways:

- **Network — `192.168.1.198`.** SSH is OpenSSH 8.6 but **password-only from
  here (no key installed)**; run `ssh-copy-id root@192.168.1.198` once to fix.
  No Samba (445 refused).
- **mrext Remote API — `http://192.168.1.198:8182`, unauthenticated.** Useful
  endpoints: `/api/games/playing`, `/api/systems`, `/api/games/search`,
  `/api/launch`, and **`/api/screenshots`** — screenshot capture is the cheapest
  way to confirm a core actually boots and renders. It does **not** appear to
  offer arbitrary file upload, so deploying an `.rbf`/`.mra` still needs SSH.
- **USB JTAG — Altera DE-SoC (`09fb:6010`)**, chain enumerates as
  `SOCVHPS + 5CSEBA6` via `~/intelFPGA_lite/quartus/bin/jtagconfig`.

**What JTAG is and isn't good for here.** It will not shortcut core loading:
programming the fabric with a `.sof` leaves the HPS `MiSTer` binary unaware, so
no MRA ROM download happens and the core sits with blank ROMs. Its real value is
**SignalTap** — an on-chip logic analyser compiled into the build, which is
exactly the tool for steps 3-5 (watch the OP4 writes land, the 6802 fetch its
vectors, the TMS5200 FIFO fill). Budget a SignalTap instance in the step-3
build rather than trying to infer behaviour from audio alone.

Courtesy note: the bench MiSTer is a shared machine and was mid-session on the
FM-7 core when this was written. Check `/api/games/playing` before launching
anything.

### FIDELITY MEASURED AGAINST MAME — pitch is RIGHT, the filter is WRONG (2026-08-01)

The earlier fidelity notes compared our output against a YouTube cabinet
recording. That reference is contaminated (game music and effects are mixed
into it) and the phrases were never matched, so every conclusion drawn from it
— including "ours is 25% high in pitch" and "ours carries too much energy above
4 kHz" — was unsound.

**Use MAME as the reference instead, and isolate the speech by SUBTRACTION.**
MAME is bit-deterministic, so running the identical session twice — once with a
speech command injected, once without — and subtracting the two WAVs yields the
speech with the game audio removed EXACTLY (measured residual before the
injection point: 0.00). `tools/mame_ref_phrase.lua` + `-wavwrite` does the
capture, `tools/pitch_compare.py` does the analysis:

```sh
CMDBYTE=0x2A mame -rp <roms> dotrone -video none -sound none -nothrottle \
  -seconds_to_run 28 -noplugins -skip_gameinfo -autoboot_delay 1 \
  -autoboot_script tools/mame_ref_phrase.lua -wavwrite ref.wav
# then the same run with CMDBYTE=none, and subtract
```

Reference phrase durations, useful for identifying an unknown capture:

| cmd | duration | F0 |
|---|---|---|
| `$2A` | 0.74 s | 186.1 Hz |
| `$2B` | 3.95 s | 186.0 Hz |
| `$32` | 0.74 s | 155.3 Hz |
| `$33` | 2.33 s | 186.0 Hz |
| `$37` | 2.13 s | 205.6 Hz |

**Result — our hardware capture vs MAME `$2A` (the same phrase, identified by
duration AND pitch):**

| | ours | MAME |
|---|---|---|
| voiced duration | 0.760 s | 0.740 s |
| F0 median | 184.7 Hz | 186.1 Hz |
| 95% rolloff | **795 Hz** | **5764 Hz** |
| energy > 4 kHz | **0.2%** | **6.5%** |

**Pitch ratio 0.993, duration ratio 1.027.** Rate and pitch are CORRECT — the
160 kHz `tms_cen` is right and needs no further investigation. Do not go
looking for a clock error; that question is closed.

**The remaining defect is the RECONSTRUCTION FILTER, and it errs the opposite
way from what was assumed: our speech is far too DULL.** Two cascaded one-pole
IIRs at shift 3 (~3.2 kHz) strip almost everything above 800 Hz, where MAME —
which models the board's actual `filter_rc` — keeps content out to ~5.8 kHz.
That is very likely what "sounds good but not quite the same" is.

Note the earlier "9.0% vs 3.8%" figures are NOT comparable to the numbers
above — they were computed on a magnitude spectrum against the contaminated
recording, whereas these use a power spectrum against clean MAME output.
Compare like with like.

**DONE — filter widened to shift 2 (2026-08-01).** Settled analytically rather
than by capture, which is the better evidence anyway: composite response
including the 8 kHz staircase, normalised at 100 Hz —

| design | 1k | 2k | 3k | 4k | 12k (image) |
|---|---|---|---|---|---|
| shift 3 x2 (was) | -0.9 | -3.5 | -7.1 | **-11.4** | -35.9 |
| **shift 2 x2 (now)** | -0.4 | -1.5 | -3.4 | **-6.2** | -24.6 |
| shift 1 x2 | -0.2 | -1.0 | -2.3 | -4.3 | -16.6 |
| boxcar 20 | -0.4 | -1.8 | -4.2 | -7.8 | -26.8 |

Shift 3 was discarding the top third of the speech band. Shift 2 recovers
5.2 dB at 4 kHz and still rejects images by 24.6 dB. Speech re-verified on
hardware after the change (`cmds=02`, `ws=FF`, `cmd_at_read=1D` = the correct
high nibble of `$2B`).

Two constraints for anyone tuning this further:
- **The 8 kHz staircase alone costs 3.9 dB at 4 kHz**, so ~-4.3 dB is the
  practical floor without ZOH compensation. Do not chase flatness past it.
- **MAME is not a model for this filter.** It puts only a 15.9 Hz DC blocker
  on the speech path (`FILTER_RC ... set_ac()` = 10k/1uF, `ballysound.cpp:704`)
  because its 8 kHz -> 48 kHz resampler band-limits for free. We emit a real
  160 kHz staircase and need a reconstruction filter MAME does not.

**VERIFIED on hardware by recording (2026-08-01).** A phone capture of the new
build, matched to MAME's `$2B` reference (the probe confirmed the game issued
`$2B`), band energies normalised to the 200-500 Hz band:

| band | ours | MAME | deficit |
|---|---|---|---|
| 500-1000 | +7.7 | -0.7 | +8.4 |
| 1000-1500 | -5.4 | -3.6 | -1.7 |
| 1500-2000 | -10.9 | -9.1 | -1.8 |
| 2000-3000 | -8.9 | -10.5 | **+1.6** |
| 3000-4000 | -13.2 | -13.8 | **+0.6** |

1-4 kHz is now within ~2 dB of MAME; under shift 3 the top two bands would
have been 4-5 dB lower. The +8.4 dB at 500-1000 Hz is chain coloration
(speaker resonance + phone AGC), not the core — a core defect would trend
across neighbouring bands, not spike in one.

Pitch re-confirmed at the same time: 190-221 Hz across seven utterances
against MAME's 186-206 Hz.

### THE PHRASE CATALOGUE, and speech CONFIRMED CORRECT (2026-08-01)

All 17 speech commands isolated from MAME by subtraction and measured. Use
this to identify an unknown capture — duration plus F0 pins a phrase down:

| cmd | dur | F0 | | cmd | dur | F0 | | cmd | dur | F0 |
|---|---|---|---|---|---|---|---|---|---|---|
| `$28` | 1.76s | 116 | | `$2E` | 1.79s | 118 | | `$34` | 0.81s | 222 |
| `$29` | 0.61s | 129 | | `$2F` | 0.82s | 118 | | `$35` | 1.65s | 266 |
| `$2A` | 0.71s | 186 | | `$30` | 2.43s | 182 | | `$36` | 1.82s | 211 |
| `$2B` | 4.40s | 178 | | `$31` | 2.22s | 129 | | `$37` | 2.11s | 205 |
| `$2C` | 1.15s | 211 | | `$32` | 0.64s | 157 | | `$38` | 1.11s | 178 |
| `$2D` | 1.30s | 216 | | `$33` | 2.19s | 186 | | | | |

**`$2A` = "GREETINGS", `$2B` = "MASTER CONTROL..."** — identified from a bench
recording. They are the pair the game issues back to back at `$0913`/`$0921`,
i.e. the game-start greeting.

**FINAL VERIFICATION — synthesis is correct.** Bench recording vs MAME, matched
phrase, speech gated at -20 dB to exclude the room reverb tail:

| phrase | duration ours/MAME | pitch ours/MAME |
|---|---|---|
| `$2A` "greetings" | 0.61 / 0.61 s = **1.000** | **0.994** |
| `$2B` "master control" | 4.42 / 4.40 s = **1.005** | **0.981** (per-frame) |

Rate and pitch both match to within 2%. Combined with the band profile being
within ~2 dB of MAME from 1-4 kHz, **the speech path is correct** and any
remaining audible difference is the playback/recording chain.

**Measurement traps this exposed, all of which produced a false alarm first:**
- **A -33 dB voiced-duration gate counts ROOM REVERB as speech.** It made the
  "greetings" clip read 1.49 s against MAME's 0.73 s — an apparent 2.04x rate
  error that vanished at a -20 dB gate (1.000). Gate hard, or measure in an
  anechoic path.
- **Median F0 is corrupted by OCTAVE ERRORS.** Medians differed by 9.7% on
  `$2B`; per-frame comparison showed 0.981 with 10.7% of frames sitting at
  exactly 2x. Compare contours frame by frame, never medians alone.
- **A clip may hold MORE THAN ONE phrase.** The first "greetings master
  control" clip was two utterances plus a gap; measured whole it read 25% long,
  and per-utterance it read 1.005. Always check the envelope first.

**Two traps when judging a phone recording of this:**
- **Check the BACKGROUND spectrum first.** Room tone here carried energy to
  20 kHz, which proves the chain is not the thing limiting the speech. Without
  that control a dull-looking capture says nothing.
- **Do NOT treat MAME's above-4 kHz content as a target.** MAME has far MORE
  HF than we do (-14 dB at 6-10 kHz) purely because it applies no
  reconstruction filter; a real TMS5220 cannot produce anything up there. Only
  the 0.2-4 kHz bands are meaningful for comparison.

If it still sounds dull, shift 1 x2 is next, but at -16.6 dB image rejection
the 12 kHz imaging may become audible as edge — which is the "harsh" the
filter was originally added to fix.

**Capture path:** the MS2109/MiraBox dongle on this host is ALSA `hw:3,0` +
`/dev/video4`. It only locks to standard CEA modes — MiSTer's `video_mode=1`
(1024x768, a VESA mode) gives a black frame and silent audio. `video_mode=0`
(720p) is the setting to use for capture.

## REMAINING WORK — Discs of Tron (Environmental)

Speech is DONE and confirmed in-game (2026-08-01). What is left, in the order
worth doing it.

### 1. Speech FIDELITY — the only open functional issue

It speaks, and it sounds like speech, but it is not yet proven to match a real
cabinet. Measured so far:

| | ours | real cabinet |
|---|---|---|
| energy above 4 kHz | 9.0% | 3.8% |
| pitch, "GREETINGS" | 229 Hz (hw) / 216 Hz (sim) | 183 Hz |

**The 25% pitch gap is the suspicious number and it has never been measured on
the same phrase**, which is the whole problem — different phrases genuinely have
different pitch, so the comparison so far is not evidence of anything. That was
impossible before, because the game never issued a speech command we could
provoke. It is possible NOW: coin up over HTTP, play, and capture the audio.

Do these in order and stop when it matches:
1. **Same-phrase capture.** Record MiSTer audio through a known phrase and
   compare against `tron_greetings_arcadeyoutube.wav` (183 Hz). Until this is
   done, everything below is guesswork.
2. If pitch is genuinely high, suspect **`tms_cen`**. 160 kHz is taken from
   Mega99's `clkgen.v` comment (ROMCLK = 640 kHz / 4), never measured against
   hardware. Wrong here shifts pitch and rate together.
3. If only the top end is wrong, the **reconstruction lowpass is too gentle**.
   The 20-tap boxcar idea was right; it failed on a Verilog width bug
   (`tms_sum * 21'sd13` truncates to 21 bits). The corrected expression is
   written in `squawk_n_talk.sv`.
4. Cross-check the **chirp and energy tables** against MAME. Only the PITCH
   table was ever verified to be the genuine TMS5200 set.

**Today's CPU fix does NOT affect any of this.** The TMS5200 runs off its own
160 kHz enable, so changing `CPU_HZ` cannot move pitch or rate.

### 2. Release hygiene

- **Delete `releases/zzz Discs of Tron (Env, strap=Upright CONTROL).mra`.** It
  is not a real machine — it exists only as the falsification control for the
  bring-up probe, and that probe has served its purpose.
- **Decide the core name.** This ships as `MCR3SNT` deliberately, so a
  work-in-progress speech core could not become the core for Tapper, Timber,
  Journey and upright Discs of Tron. Now that it works, folding it back into
  `MCR3` gives one core for all five sets. That is a release decision, not a
  technical one.
- The bring-up probe (`status[8]`, "S&T Probe") is already default OFF and
  costs nothing; keep it.

### 3. Not implemented, probably WON'T BE

- **The lamp sequencer.** `edotlamp.u2` is loaded by the MRA and decoded
  (OP4 bit 5 latches bits 5..0; bits 6/7 are the backlight and flasher) but
  drives nothing. It is cabinet lighting — there is no hardware on a MiSTer to
  drive, so this is cosmetic-only and out of scope unless someone wants it for
  a real Environmental cabinet conversion.
- **`dotronep`**, the 8/9/83 prototype set. MAME documents it booting with
  "SOUND BOARD INTERFACE ERROR". Would be another `mod` variant; no demand.

### 4. THE ACTUAL GOAL — port to Tang

This whole repo is a prototyping detour. The target is
`mcr3_console60k`, then `mcr123s_console60k` at 116/118 BSRAM, where the 12 KB
S&T ROM (~6 blocks) has to come out of SDRAM alongside the SSIO sound ROM.

**Four things to check FIRST when porting** — every one of them presents as a
board that is demonstrably alive and silently says nothing, with no error, no
warning and no failed build:

| Trap | Wrong assumption |
|---|---|
| double-registered ROM read | that `dpram`'s output still needed latching |
| PIA output register w/o direction | that `pb_o` reflects the pin when `DDR=0` |
| pulsed data bus read as held | that `dq` stays valid after the read strobe |
| **6801 vs 6800 branch timing** | that jt680x's cycle counts match an MC6802 |

The fourth is new (2026-08-01) and **will reproduce identically on Gowin** —
same `jt680x`, same ROM, same 1255 us handshake. Carry `CPU_HZ = xtal * 5/6`
across with the comment, and run `sim/tb_time.v` after any clock change.

### 5. Stale claims in the PARENT repo to fix when this lands

- `docs/mcr_core_roadmap.md:203` — "Squawk & Talk = 6809 + TMS5200". It is a
  **6802**. (The 6809 is the Turbo Cheap Squeak, a different board.)
- `docs/mcr_core_roadmap.md:21` — "DoT speech absent upstream" reads as an
  upstream gap; it was absent from the emulated hardware too.
- `TODO.md:2157` — "DoT ships without speech". No longer true here; still true
  on Tang until the port lands.
