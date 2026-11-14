# wave (Analog Four MKII, OS 1.56)

The digital wave / chord oscillator, AE 0010, ported to the MKII as an elemod.

On a synth track, OSC1 pressed twice shows NOISE. Knob D turns the noise generator
into a digital oscillator at OSC1's pitch (note, tune, bend, slide, vibrato and LFOs
included): OFF, WAV, or CHD, a chord of it, chosen on knob F (OCT 5TH MAJ MIN SU2 SU4
MA7 MI7 DO7 MI9 HDX, and the supersaws SW1 SW2). The mode knob is named by its value,
the chord knob CHRD (2.0; its value shows while it turns). With WAV or CHD on the page reads:

| knob | was | now |
|---|---|---|
| A | S&H | SHP: the wave, 0 sine, 42 triangle, 85 saw, 127 square, morphing between |
| B | COL | FLD: a wavefolder, 0 clean, up to about 7x into the fold |
| C | FAD | FM: a sine at OSC2's pitch modulating the wave's phase, up to about two cycles |
| E | LEV | LEV: the level |

It plays through the noise path into the analog voice, so the filters, overdrive and
VCA shape it. SHP, FLD, FM and LEV are the stock noise parameters, so locks and LFOs
work on them. The mode and chord are kept with the sound and, from 2.0 (core-a4 0.5),
can be p-locked: hold a trig and turn D or F (or turn in live recording) and that trig
plays its own mode or chord, so a pattern can step through chords. The chord is also a
destination of the LFOs, the Dest knobs, the routes, the macros and CONTROL IN
(WAVE:Wave Chord), with a CC and an NRPN; it has no smoothing, so a change lands at
once, and modulation and Param Slide step through the chord list (OCT, 5TH, MAJ ...
SW2) one whole chord at a time. The mode is a choice and takes locks (and an NRPN)
only, landing at the trig.
Saw and square are not band-limited. Two sounding chord tracks are the comfortable
maximum; a third slows the screen (the image port's measurement on an MKII). It also
played on a track with dist's DIG on from 1.1; from 2.0 wave and dist cannot share a
build (both keep their settings in the sound's 32 bits, and both answer the knob-name
getters), so wave stands on its own.

## What changed from the MK1

- **The page.** The MK1 patched the NOISE page's descriptor and drew its two knobs
  on AMP REL and CHO. Here wave answers page 7 through `core_pages` with two mod
  knobs, D (0x310, the mode) and F (0x311, the chord), mod ids above 0x126 that
  core-a4 0.5 draws, turns and locks. `core_params` answers for both. (1.x drew them
  on the hidden records 37 and 140.)
- **The names.** wave owns two sites on the parameter sets' name getters (short
  0x4009e79e, long 0x4009e7c2), which core-a4 0.5 calls for every id it does not name:
  the mode knob is named by its value (its lock param carries no short name, so core
  asks the getters); the chord knob is CHRD, its short name, which is also what a
  Dest knob shows when it points at the chord, and S&H, COL and FAD read SHP, FLD and FM while the active
  track's sound has WAV or CHD on. Core 0.5's own name routines hide who asks, so
  these names also show in lists (an LFO's Dest list) while the active track has the
  oscillator on. 1.x named them through dist's `ae_names` and needed dist.
- **The setting** was the sound's unused parameter word 103 (with a converter hook to
  carry it from the pool's records). Here it is two lockable core-a4 sound fields,
  `wave_mode` (2 bits) and `wave_chord` (4 bits, `"mod"`, `"cc"`, `"smooth": false`),
  so it travels with the sound with no hook. Each audio block `wave_render`
  (ev_render_out) writes each synth track's mode (its trig's lock in its place) and
  chord (core's value read, rounded to a whole chord) into `wave_trk`. A sound saved
  by wave 1.x loads with the oscillator off (1.x kept one 6-bit field).
- **The oscillator** is the image port's code (the fade hook 0x400ffe04 and the mix
  hook 0x400ffe50), with its state in this mod's `.bss`. It ran from the chorus gap
  on the MK1, so a clamp on the chorus index guarded it; running from the mods' RAM
  it needs no clamp.

## Status

**2.1** (core-a4mk2 0.7, build AW21 with scale-lock and slide): the same code as 2.0, built and linked with
core-a4mk2 0.7 (elekloader main, 14 Nov 2026) and the earlier build's lockfile, so the
storage layout, lock codes and CCs are unchanged and projects saved by the earlier
build keep their settings. Not yet run in the emulator or on a unit.

**2.0** (core-a4 0.5, build AW20 with scale-lock and slide, no dist; plans `t-aw20`): in
rytm-emu's A4 build and on an Analog Four MKII (7 Nov 2026): the NOISE page (mode by its
value, CHRD), a chord p-lock of OCT on trig 1 plays on that trig only (the oscillator's
per-block setting reads OCT while it plays, the sound's MA7 otherwise); LFO1 with Dest A on
WAVE:Wave Chord steps the played chord one whole chord at a time; KEY SCALE and the NOTE
encoder as before; the settings come back after SAVE PROJECT AS and loading the project
again. Not checked yet: the chords by ear under the LFO, the CC and NRPNs, mode locks,
Param Slide on the chord.

**1.x**: In rytm-emu's A4 build (24 Oct 2026), with dist, scale-lock, slide and analoghealth
(plan check5-ae56, PASS): the NOISE page shows the two knobs, OFF / WAV / CHD and the
chord names, SHP FLD FM while on, notes play with CHD on, and the setting came back
after SAVE PROJECT AS and loading the project again.

On an Analog Four MKII (24 Oct 2026): the same screens, and the setting came back after
a save and reload; the chord heard with DIG off, and with DIG on from 1.1.
