# scale-lock (Analog Four MKII, OS 1.56)

Scale lock, AE 0001, ported to the MKII as an elemod.

NOTES SETUP (FUNC + NOTE): KEY SCALE grows from OFF / MAJ / MIN to OFF and 35 scales:
MAJ, MIN, DOR, PHRY, LYD, MIXO, LOCR, then the rest of the firmware's own scale
library (which stock 1.56 links but never uses), up to LO37. Anything but OFF locks
the track to KEY NOTE + KEY SCALE:

- notes played on the trig keys, and everything that records them, snap to the
  nearest note in the scale;
- hold a trig and play a key: the step's note snaps the same way;
- the NOTE page's NOTE encoder steps from one note in the scale to the next, on the
  track's note and on held trigs' locks.

MAJ and MIN restrict too. The setting is the pattern's own KEY SCALE byte, saved with
the pattern; a pattern with a new scale opened on stock reads KEY SCALE OFF.

## What changed from the MK1

- **The code** is the MKII image port's (branch `MK2-OS-1.56`, mods/0001-scale-lock),
  where every host listing was identical to the MK1's apart from addresses.
- **The NOTE encoder's no-trig path.** core-a4 0.2 owns param_apply_delta's entry
  (0x400232e2) for its page tables and resumes the routine after its prologue, so
  this mod hooks the next two instructions instead (0x400232ea: `moveal %sp@(16),%a2;
  movel %sp@(28),%d3`), where the delta is still on the stack, and rewrites it there
  as the MK1 did at the entry.
- Everything else (played notes 0x400bce08, step entry 0x400afa38, held-trig locks
  0x4002388a and 0x40023faa, the KEY SCALE text 0x400dbc8a, and the five byte sites
  that widen KEY SCALE to 35 and give 3..35 the MAJ arm of the transposition) is the
  image port's.

## Status

In rytm-emu's A4 build (24 Oct 2026), core-a4 0.2 with dist, slide, wave and
analoghealth: KEY SCALE steps OFF, MAJ, MIN, DOR ... and stops at LO37 with each
name shown; with MAJ on C, the NOTE encoder went C6, F6, B6 (in the scale, several
steps a turn as turned). On an Analog Four MKII (24 Oct 2026): the same, KEY SCALE up to LO37 and the NOTE
encoder stepping in MAJ.
