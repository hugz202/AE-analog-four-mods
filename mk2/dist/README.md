# dist (Analog Four MKII, OS 1.56)

The digital path and its DIST page, AE 0007 and 0008, ported to the MKII as one
elemod.

On a synth track press AMP a second time for the DIST page (AMP's own page is then
titled "AMP (P 1/2)"):

| knob | setting | range | what | p-lock | LFO, routes, CC |
|---|---|---|---|---|---|
| A | DIG | off / on | the track's analog dry sound is muted and the A4's own digitised copy of it is processed instead, through a fixed 12 dB/oct low-cut first (-6 dB at 75 Hz, like filter 2 in HP2 at FRQ ~32, RES 0) so the low end doesn't swamp the drive (2.3) | yes | no |
| B | CHR | HARD / RAT / OD | the drive's character: a digital clipper; a treble lift, op-amp roll-off, hard clip and 4 kHz tone; a 720 Hz mid hump, soft clip and 2.5 kHz | yes | no |
| C | DRV | 0..127 | drive: more grit at about the same level | yes | yes |
| D | BIT | 0..127 | bit reduction, 0 off, then 13 down to 2 bits | yes | yes |
| E | SRR | 0..127 | sample-rate reduction (sample hold), 0 off | yes | yes |
| F | LEV | 0..127 | the processed signal's level; about 100 is level with the analog path | yes | yes |
| G | SLD | off / on | [slide](../slide/README.md)'s 303 mode for the track | no | no |

The processed signal also replaces the voice in the effect sends, so the delay,
reverb and chorus hear the distortion. From 2.3 the sends follow LEV like the dry
output (LEV 100 sends at about the clean voice's level); 2.2 and before trimmed them
by DRV instead (256 - DRV, Q8).

From 2.0 (core-a4 0.5) the settings are kept with the **sound**, not the kit, so they
travel with it through kits, the sound pool and copies. DIG, CHR, DRV, BIT, SRR and
LEV can be p-locked like a stock knob: hold a trig and turn, or turn in live
recording. DRV, BIT, SRR and LEV are also destinations of the LFOs, the Dest knobs,
the routes (velocity, bend, wheel, breath, aftertouch), the performance macros and
CONTROL IN, listed as DIST:Drive, DIST:Bit Reduction, DIST:Sample Rate and
DIST:Digital Level, and each has an NRPN (MSB 0, LSB its lock code) and a CC from the
build's lockfile. DIG and CHR are switches: they take locks (and an NRPN) only, and
jump at the trig with no smoothing, Param Slide or modulation. SLD is slide's
per-track mode, read by the sequencer, so it has no lock.

A sound with no dist data reads 0 in every setting, so LEV starts at 0: switching DIG on
with LEV at 0 sets LEV to 100. (core-a4mk2 0.6 added field inits, but an init on LEV
would XOR every saved LEV with it, so sounds saved by 2.0 would load with other levels;
2.1 keeps 2.0's layout.)

**dist and wave cannot share a build** from 2.0: dist takes all 32 bits of a sound's
room and both answer the knob-name getters. The patcher refuses the pair (the
name-getter sites overlap). A kit saved by dist 1.0 loads with its dist settings at 0:
they were kit fields, and 2.0's are sound fields.

## Knob looks (2.2)

From 2.2 the knobs look as 1.0's did: dist contributes `core_knob_looks` entries
(core-a4mk2 0.6), so DIG is drawn as OSC1 AM's switch, CHR as AMP PAN's marker over
its three positions, DRV, BIT, SRR and LEV as AMP CHO's dial, and SLD as OSC2 AM's
switch. 2.0 and 2.1 drew all seven as core's default dial. Only the drawing changes:
settings, locks, lock codes and CCs are 2.1's.

## What changed from the MK1

- **The page.** The MK1's view builder, slot patches and page_info patch are
  core-a4 0.2's page tables: the page is page 50 in `core_pages`, behind AMP on synth
  tracks through `core_view_pages`, and AMP is retitled through a `core_pages` entry
  for page 11.
- **The knobs** are seven mod ids the linker gives (`"knobs": 7`, from 0x200 up;
  0x300..0x306 before 2.4), which core-a4 0.5 draws and
  names from each parameter's `core_lock_param` (short name on the knob, long name
  in the header and with a trig held). 1.0 drew them on seven hidden parameter
  records (38, 39, 51, 52, 64, 65, 88) with byte sites on their range and a RAM
  record copy at the first tick; 2.0 needs none of that.
- **The names.** core-a4 0.5 calls the stock name getters (0x4009e79e short,
  0x4009e7c2 long) for every id it does not name, so dist's two sites there name only
  SLD, the one knob without a lock. 1.0 named all seven by checking the caller, which
  core 0.5's own name routines hide; the `ae_names` table is gone with it.
- **The settings** were bytes in the kit's spare FX words (kept by 0006). Here they
  are seven core-a4 sound fields (DIG 1, CHR 2, DRV 7, BIT 7, SRR 7, LEV 7, SLD 1
  bits: the sound's whole room). Each audio block `dist_render` (ev_render_out,
  after core's snapshot) writes what each track plays into `dist_set`, laid out as
  the MK1's kit bytes were: DRV, BIT, SRR and LEV from core's value read (the sound's
  value or the trig's lock, smoothed, Param Slide and every modulation), DIG and CHR
  the trig's lock or the sound's value. The UI tick keeps SLD for slide.
- **Audio.** The three audio hooks (the dry volume 0x400fa6c4, the FX block's entry
  0x400fe73c and its output 0x400feace) and their code are the image port's, reading
  `dist_set` instead of the kit, with their buffers in this mod's `.bss` instead of
  free DDR.
- **Encoder steps** for CHR keep the image port's three turns a position.

## Status

**2.4** (core-a4mk2 0.7, built with elekloader's knob ids by count): the knobs' ids
come from the linker (`"knobs": 7` in mod.json, `CORE_KNOB(0..6)` in dist.c) in place of
the fixed 0x300..0x306, so dist cannot collide with another mod's ids and a +Drive
mod's ids (0x4000 up) stay clear of it. The code tells the knobs apart by id -
CORE_KNOB(0). Settings, storage, lock codes, CCs and the knob looks are 2.3's; p-locks
saved by an earlier build on DIG..LEV no longer apply (decided 2026-11-16: the lock
names the old id), while the sound's settings load as before. Needs an elekloader with
the Analog Four MKII's knob ids (`param_ids` from 0x200; on branch drive-loader-a4mk2
from e9cf675). Not yet run in the emulator or on a unit.

**2.3** (core-a4mk2 0.7): the MK1's OS-1.56 0007 update (upstream commit ffcdc20,
26 Oct 2026, hardware-verified on an MK1) on 2.2 (the knob looks): the input low-cut (`hp2`, two
one-pole high-passes at 75 Hz, shifts and adds only, ahead of the drive and the
RAT/OD filters) and the sends' gain from LEV (`hp_set`). The DSP record per track
grows from 14 to 16 longs (the low-cut's two states, cleared when out of range). No
storage, site, lock or CC change: the lockfile from AD21 still applies. The audio code
was run first on 2.1 as a build of its own (dist "2.2" on branch mk2-dist-lowcut, build
DL22: core-a4mk2 0.8, analoghealth 1.2, scale-lock 1.1, slide 1.1; plans `t-dl22`):
emulator gate passed (14-15 Nov 2026), then on an Analog Four MKII (16 Nov 2026, hardware
test T382): flashes both ways, the DIST page and `dist_set` with DIG off and with DIG on,
HARD, DRV 64, BIT 0, SRR 0, LEV 100, and an A/B listening check by the owner on T1 (four
notes a bar): B as expected, with an occasional click on the attack of some notes only,
judged likely the free-running oscillators' phase at note start through the drive, not
an artefact (not proven). CPU on DL22 79 %. 2.3 itself (with 2.2's knob looks; build
DL23, the same modules with dist 2.3, plans `t-dl23`) passed the emulator gate and ran on the
unit on 16 Nov 2026 (hardware test T390): flashes both ways, the DIST settings read back
matching the emulator's, CPU 82.6-82.8 % before any key (heap flat), and the owner's
listens: DIG on with DRV 0 about the same as DIG off, DRV 127 HARD no artefacts, DRV 64
HARD with free-running oscillators intermittent attack clicks (every 5-7 notes), and the
same with oscillator retrig on no clicks. So the attack clicks are the oscillators' phase
at note start through the drive, not the low-cut.

**2.1** (core-a4mk2 0.7, build AD21 with scale-lock and slide): the same code as 2.0, built and linked with
core-a4mk2 0.7 (elekloader main, 14 Nov 2026) and the earlier build's lockfile, so the
storage layout, lock codes and CCs are unchanged and projects saved by the earlier
build keep their settings. Not yet run in the emulator or on a unit.

**2.0** (core-a4 0.5, build AD20 with scale-lock and slide; plans `t-ad20`): in rytm-emu's
A4 build and on an Analog Four MKII (7 Nov 2026): the DIST page and every knob; a DRV
p-lock of 0 on trig 1 plays on that trig only (the audio side's per-block values read
0 while it plays, 127 otherwise); LFO1 with Dest A on DIST:Drive moves the played DRV
(87..127 on the unit at depth -32); the DIST settings come back after SAVE PROJECT AS and
loading the project again. Not checked yet: the sound by ear, CCs and NRPNs, the other
destinations (routes, macros, CONTROL IN), locks on DIG, CHR, BIT, SRR and LEV.

**1.0**: In rytm-emu's A4 build (24 Oct 2026), core-a4 0.2 with scale-lock, slide, wave and
analoghealth (plan check5-ae56, PASS): AMP reads "AMP (P 1/2)", AMP again the DIST
page with DIG CHR DRV BIT SRR / LEV SLD, every knob turns and draws, the long names
show in the header; notes play with DIG on; the settings came back after a reboot,
and after SAVE PROJECT AS and loading the project again. On an Analog Four MKII (24 Oct 2026): the same screens and settings across a save and
reload. Measured over USB at
middle C (C4), LEV 98: DIG on is about 1 dB under DIG off, as calibrated on the MK1; at
E0 about 15 dB under, because the digitised copy carries little of the lowest notes.
