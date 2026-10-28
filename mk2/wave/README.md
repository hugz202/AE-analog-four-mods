# wave (Analog Four MKII, OS 1.56)

The digital wave / chord oscillator, AE 0010, ported to the MKII as an elemod.

On a synth track, OSC1 pressed twice shows NOISE. Knob D turns the noise generator
into a digital oscillator at OSC1's pitch (note, tune, bend, slide, vibrato and LFOs
included): OFF, WAV, or CHD, a chord of it, chosen on knob F (OCT 5TH MAJ MIN SU2 SU4
MA7 MI7 DO7 MI9 HDX, and the supersaws SW1 SW2). Each of the two knobs is named by
its value. With WAV or CHD on the page reads:

| knob | was | now |
|---|---|---|
| A | S&H | SHP: the wave, 0 sine, 42 triangle, 85 saw, 127 square, morphing between |
| B | COL | FLD: a wavefolder, 0 clean, up to about 7x into the fold |
| C | FAD | FM: a sine at OSC2's pitch modulating the wave's phase, up to about two cycles |
| E | LEV | LEV: the level |

It plays through the noise path into the analog voice, so the filters, overdrive and
VCA shape it. SHP, FLD, FM and LEV are the stock noise parameters, so locks and LFOs
work on them; the mode and chord are kept with the sound and cannot be p-locked.
Saw and square are not band-limited. Two sounding chord tracks are the comfortable
maximum; a third slows the screen (the image port's measurement on an MKII). It also
plays on a track with dist's DIG on (1.1): DIG mutes the voice's dry VCA, which 1.0
(and the image port) read as an idle voice and silenced.

## What changed from the MK1

- **The page.** The MK1 patched the NOISE page's descriptor and drew its two knobs
  on AMP REL and CHO. Here wave answers page 7 through `core_pages` and puts two
  hidden parameter records on knobs D and F: 37 and 140, the synth's and the FX
  track's "None" records, which no page shows. At the first tick their RAM records
  take AMP PAN's (D, three positions) and AMP CHO's (F) whole record, and are marked
  unlockable. `core_params` answers for both.
- **The names** come through dist's `ae_names` table, so wave needs dist.
- **The setting** was the sound's unused parameter word 103 (with a converter hook to
  carry it from the pool's records). Here it is a 6-bit sound field in core-a4's mod
  storage (chord type << 2 | mode), so it travels with the sound with no hook. The UI
  tick copies each synth track's into `wave_trk` for the audio interrupt.
- **The oscillator** is the image port's code (the fade hook 0x400ffe04 and the mix
  hook 0x400ffe50), with its state in this mod's `.bss`. It ran from the chorus gap
  on the MK1, so a clamp on the chorus index guarded it; running from the mods' RAM
  it needs no clamp.

## Status

In rytm-emu's A4 build (24 Oct 2026), with dist, scale-lock, slide and analoghealth
(plan check5-ae56, PASS): the NOISE page shows the two knobs, OFF / WAV / CHD and the
chord names, SHP FLD FM while on, notes play with CHD on, and the setting came back
after SAVE PROJECT AS and loading the project again.

On an Analog Four MKII (24 Oct 2026): the same screens, and the setting came back after
a save and reload; the chord heard with DIG off, and with DIG on from 1.1.
