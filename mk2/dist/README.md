# dist (Analog Four MKII, OS 1.56)

The digital path and its DIST page, AE 0007 and 0008, ported to the MKII as one
elemod.

On a synth track press AMP a second time for the DIST page (AMP's own page is then
titled "AMP (P 1/2)"):

| knob | setting | range | what | p-lock | LFO, routes, CC |
|---|---|---|---|---|---|
| A | DIG | off / on | the track's analog dry sound is muted and the A4's own digitised copy of it is processed instead | yes | no |
| B | CHR | HARD / RAT / OD | the drive's character: a digital clipper; a treble lift, op-amp roll-off, hard clip and 4 kHz tone; a 720 Hz mid hump, soft clip and 2.5 kHz | yes | no |
| C | DRV | 0..127 | drive: more grit at about the same level | yes | yes |
| D | BIT | 0..127 | bit reduction, 0 off, then 13 down to 2 bits | yes | yes |
| E | SRR | 0..127 | sample-rate reduction (sample hold), 0 off | yes | yes |
| F | LEV | 0..127 | the processed signal's level; about 100 is level with the analog path | yes | yes |
| G | SLD | off / on | [slide](../slide/README.md)'s 303 mode for the track | no | no |

The processed signal also replaces the voice in the effect sends, so the delay,
reverb and chorus hear the distortion.

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

## What changed from the MK1

- **The page.** The MK1's view builder, slot patches and page_info patch are
  core-a4 0.2's page tables: the page is page 50 in `core_pages`, behind AMP on synth
  tracks through `core_view_pages`, and AMP is retitled through a `core_pages` entry
  for page 11.
- **The knobs** are mod ids above 0x126 (0x300..0x306), which core-a4 0.5 draws and
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
