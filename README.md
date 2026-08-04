# Midway MCR3 port for MiSTer

[Original readme](README_orig.txt) (mostly irrelevant to MiSTer)

# What's new in this build (2026-08-05)

Two additions, both specific to Discs of Tron. **Testing and feedback welcome.**

## Speech — Discs of Tron (Environmental)

The Environmental cabinet carries a Bally **Squawk & Talk** board (MC6802 +
2x PIA6821 + TMS5200 + AD558) that upstream has never implemented. It is
implemented here, and `Discs of Tron (Environmental).mra` is a new set.

Note this is a genuinely different ROM set, not a switch on the upright: the
upright `dotron`/`dotrona` PCBs have no speech hardware at all, so the upright
is silent because the real machine is.

Verified against MAME on matched phrases: pitch and rate within 2%, spectral
balance within ~2 dB from 1-4 kHz.

## Cabinet backdrop — both Discs of Tron sets

Discs of Tron puts a backlit painted cityscape behind a half-silvered mirror
and superimposes the monitor image on it. (That mirror is also why the game
renders mirrored -- it is correct, not a bug.) The core now shows that artwork
wherever the game pixel is black.

* OSD option **"Backdrop"**, default **On**.
* The artwork is **inline in the MRA**, so nothing extra to install.
* It follows screen flip and rotation, so rotated monitors are fine.
* On the **Environmental** set the backdrop is **backlit by the game** -- OP4
  bit 6 -- so it goes dark between games and lights when one starts, as the
  real cabinet does. On the **upright** it stays lit: that PCB never drives
  the lamp bits, and MAME's own artwork defaults it to lit there too.

### Artwork credits

The backdrop is community-scanned MAME artwork, used with thanks:

* Photographed backdrop provided and converted for MAME by **xiaou2**
* Layout file by **Mr. Do**

The full artwork package also credits CAG / BYOAC Artwork, Mr. Do, jcroach,
Ad_Enuff and hausjam for the bezels and widescreen graphics, which this core
does not use.

### Known limitations

* The backdrop is 512x240 in 9-bit colour, which is the core's own video depth
  -- `arcade_video` is 9-bit, so there are only 512 possible colours regardless.
* There is an **"S&T Probe"** OSD option, default off. It is a bring-up
  diagnostic that tints black pixels to show speech-board state. Harmless, and
  only active on the Environmental set.

```
# Games

### Timber
Up to 2 players. 
* Up/Down/Left/Right - movements 
* A - Chop Right 
* B - Chop Left

### Tapper
Up to 2 players.
* Up/Down/Left/Right - movements
* A - Fill
 
### Discs of Tron
Up to 2 players.
* Up/Down/Left/Right - movements
* A - Toss
* B - Deflect
* C - Aim Up
* D - Aim Down
Supports 2 control modes: Joystick/Spinner
Spinner - Rotate Right,Rotate Left

### Journey
Up to 2 players.
* Up/Down/Left/Right - movements
* A - Blast

Download a sound file from mame sounds ( https://samples.mameworld.info/ click current samples ) , and put journey.zip in:
_Arcade/sound/
 
 
# ROMs
```
                                *** Attention ***

ROMs are not included. In order to use this arcade, you need to provide the
correct ROMs.

To simplify the process .mra files are provided in the releases folder, that
specifies the required ROMs with checksums. The ROMs .zip filename refers to the
corresponding file of the M.A.M.E. project.

Please refer to https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms for
information on how to setup and use the environment.

Quickreference for folders and file placement:

/_Arcade/<game name>.mra
/_Arcade/cores/<game rbf>.rbf
/_Arcade/mame/<mame rom>.zip
/_Arcade/hbmame/<hbmame rom>.zip

```

Launch game using the appropriate .MRA
