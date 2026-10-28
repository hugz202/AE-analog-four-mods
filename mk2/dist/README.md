# dist (Analog Four MKII, OS 1.56)

The digital path and its DIST page, AE 0007 and 0008, ported to the MKII as one
elemod.

On a synth track press AMP a second time for the DIST page (AMP's own page is then
titled "AMP (P 1/2)"):

| knob | setting | range | what |
|---|---|---|---|
| A | DIG | off / on | the track's analog dry sound is muted and the A4's own digitised copy of it is processed instead |
| B | CHR | HARD / RAT / OD | the drive's character: a digital clipper; a treble lift, op-amp roll-off, hard clip and 4 kHz tone; a 720 Hz mid hump, soft clip and 2.5 kHz |
| C | DRV | 0..127 | drive: more grit at about the same level |
| D | BIT | 0..127 | bit reduction, 0 off, then 13 down to 2 bits |
| E | SRR | 0..127 | sample-rate reduction (sample hold), 0 off |
| F | LEV | 0..127 | the processed signal's level; about 100 is level with the analog path |
| G | SLD | off / on | [slide](../slide/README.md)'s 303 mode for the track |

The processed signal also replaces the voice in the effect sends, so the delay,
reverb and chorus hear the distortion. The settings are kept with the kit and cannot
be p-locked: a turn with a trig held changes the setting, not a lock. While a knob
turns the header shows its long name (DIGITAL PATH, CHARACTER, DRIVE ...) and the
knob its value.

## What changed from the MK1

- **The page.** The MK1's view builder, slot patches and page_info patch are
  core-a4 0.2's page tables: the page is page 50 in `core_pages`, behind AMP on synth
  tracks through `core_view_pages`, and AMP is retitled through a `core_pages` entry
  for page 11.
- **The knobs.** The MK1 drew its settings on stock AMP and OSC knobs and swapped
  their values in page_get_value, the encoder call and the label formatter, keyed by
  the view drawn. core-a4 answers those by parameter id (`core_params`), so the page
  uses seven parameter records no stock page shows: 38, 39, 51, 52, 64, 65 (the
  oscillators' Pitch and Freq Mod) and 88 (F1+F2 Freq), which exist only as LFO and
  envelope destinations with a fixed value of 64. Their range in the parameter
  table becomes 0..127 (seven byte sites: the encoder handler makes no turn of a
  one-value record). At the first tick their RAM records take AMP CHO's encoder feel
  and callbacks and a stock knob's dial art (OSC1 AM's switch for DIG, OSC2 AM's for
  SLD, AMP PAN's marker for CHR, CHO's bar for the rest), and are marked unlockable.
- **The names.** Two sites on the parameter sets' name getters (short 0x4009e79e,
  long 0x4009e7c2) name these knobs, but only when called from the knob draw and
  from the encoder handler's header: an LFO's destination list keeps PM1, FM1 ....
  Other mods name knobs through the `ae_names` table this mod declares
  ([ae_names.h](ae_names.h)); wave does.
- **The settings** were bytes in the kit's spare FX words (kept by 0006). Here they
  are core-a4 kit fields, one 32-bit field per synth track (DIG 1, CHR 2, DRV 7,
  BIT 7, SRR 7, LEV 7, SLD 1 bits; LEV kept XOR 64 so an empty kit reads 64). core-a4
  writes the current kit's fields through to the stored project, so they survive a
  power cycle without a save. The UI tick copies them into `dist_set`, laid out as
  the MK1's kit bytes were, for the audio interrupt; an edit does at once.
- **Audio.** The three audio hooks (the dry volume 0x400fa6c4, the FX block's entry
  0x400fe73c and its output 0x400feace) and their code are the image port's, reading
  `dist_set` instead of the kit, with their buffers in this mod's `.bss` instead of
  free DDR.
- **Encoder steps** for CHR keep the image port's three turns a position.

## Status

In rytm-emu's A4 build (24 Oct 2026), core-a4 0.2 with scale-lock, slide, wave and
analoghealth (plan check5-ae56, PASS): AMP reads "AMP (P 1/2)", AMP again the DIST
page with DIG CHR DRV BIT SRR / LEV SLD, every knob turns and draws, the long names
show in the header; notes play with DIG on; the settings came back after a reboot,
and after SAVE PROJECT AS and loading the project again. On an Analog Four MKII (24 Oct 2026): the same screens and settings across a save and
reload. Measured over USB at
middle C (C4), LEV 98: DIG on is about 1 dB under DIG off, as calibrated on the MK1; at
E0 about 15 dB under, because the digitised copy carries little of the lowest notes.
