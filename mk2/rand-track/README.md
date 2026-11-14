# rand-track (Analog Four MKII, OS 1.56)

Random track, AE 0011, ported to the MKII as an elemod.

- **Hold a track key and press YES:** the track is copied (for the undo), cleared
  (stock CLEAR TRACK) and filled over its length with a random line. Trigs land on
  about 62 % of the steps (the first always); each gets a note in KEY NOTE + KEY SCALE
  (pentatonic minor when KEY SCALE is OFF) around the track's default note (the root
  5/16, its octave 2/16, the fifth when the scale has it 2/16, any scale note within
  -12 .. +11 the rest); about a quarter are accented and a sixth slid. Press it again
  for another. A pop-up reads RANDOM TRACK.
- **Hold the track key and press LEFT:** the track comes back as it was before the
  last random line, p-locks included (restored as stock's UNDO CLEAR restores its own
  copy). A pop-up reads RANDOM UNDONE. Only the last track randomized has a copy.
- The FX track is left alone. The CV track takes notes like a synth track. No settings,
  no storage.

With [scale-lock](../scale-lock/README.md), every KEY SCALE scale it adds is used;
without it KEY SCALE stops at MIN. With [slide](../slide/README.md), the slide trigs
play the 303 way (with dist, on the tracks whose SLD is on).

## What changed from the MK1

- **The addresses.** Every stock routine and site was traced in the MKII 1.56 image in
  Ghidra (MK1 addresses in brackets in `rand-track.s`): the panel key handler is
  0x400c8b90 and its key-code read 0x400c8ba2 (the hook); held_tracks 0x40022014;
  CLEAR TRACK 0x400b9666, UNDO CLEAR 0x400b8656 (whose restore sequence the undo
  follows: memcpy 0x40077fa0, step_lock_prep 0x400b528e, 945 data bytes, 0x3970 lock
  bytes, 228 per step); trig_flag_set 0x400b71aa (tp, step, mask, value); the pop-up
  calls of the grid handler 0x40027f78; the seed read 0x41864b1c (fx_block's first
  read). The handler, the CLEAR TRACK grid handler and the track's layout (KEY NOTE
  +0x1c8, KEY SCALE +0x1c9) read as the MK1's apart from addresses.
- **TRACK + YES / LEFT are free:** in the MKII handler YES (0x44) and LEFT (0x40) fall
  to the default case, as on the MK1; stock gives them no meaning with a track held.
- **The undo copy** (15.6 KB) is in this mod's `.bss` (core's mods' area) instead of
  free DDR at a fixed address.
- **One section.** The MK1 split the code over caves; here it is one `.text`.
- The hook is the mod's own site, not core's `ev_key`: the action needs the view
  (the current track and the pop-up) and stock's held-track mask, which `ev_key`
  does not pass.

## Status

**1.0** (core-a4mk2 0.7): builds; lints against core 0.7; links in AD22 (core + dist +
scale-lock + slide + rand-track) and AW22 (core + wave + scale-lock + slide +
rand-track) with the AD21 / AW21 lockfiles, storage unchanged. Not yet run in the
emulator or on a unit.

Worth checking in the emulator gate: YES and LEFT with a track key held on the main
screen and on a parameter page (another view could take them first); the pop-ups;
the undo after a random line and after a further edit; a track in per-track length
mode; the FX track (nothing happens); a scale-lock scale above MIN.
