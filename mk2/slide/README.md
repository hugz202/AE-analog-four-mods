# slide (Analog Four MKII, OS 1.56)

303 slide, AE 0002, ported to the MKII as an elemod.

Put the slide trig on the note you glide *from*. That note is tied into the next
trig (its length is raised to reach it plus a quarter step) and the next note glides
in legato, with no LEN tweaking. Without the slide trig the notes are separate.

With [dist](../dist/README.md) in the build, it is per synth track: SLD on the DIST
page, kept with the kit. Without dist, every synth track slides this way (the MK1's
"always on" build).

## What changed from the MK1

- **The code** is the MKII image port's (branch `MK2-OS-1.56`, mods/0002-slide-303),
  with the MKII's LEN tick table (0x40218384); the two hooks are in the trig routine
  (0x4007a48c, after LEN is resolved, and 0x4007a7f2, the look-ahead's test).
- **SLD** was a byte in the kit's spare FX words, which dist kept. Here dist keeps it
  in core-a4's kit storage and publishes the four tracks' switches in `dist_sld`, a
  weak import: without dist it reads as zeros, and zeros mean "every track".

## Status

In rytm-emu's A4 build (24 Oct 2026), with dist, scale-lock and wave: a pattern
played with SLD on for track 1 and no fault. On an Analog Four MKII (24 Oct 2026): the slide heard working.
