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

- **The key hook is core's.** core-a4mk2 0.8's `ev_track_key` (TrackSelectionView's
  key virtual 0x400c8b90, the MK1's 0x400c4348) passes the view, the key and whether
  it is a press; core's helpers give the held track keys, the current track, its
  TrackPattern and the pop-up. In that handler YES (0x44) and LEFT (0x40) fall to the
  default case, as on the MK1, so stock gives TRACK + YES / LEFT no meaning there.
- **The addresses.** The stock routines the action calls were traced in the MKII 1.56
  image in Ghidra (MK1 addresses in brackets in `rand-track.s`): CLEAR TRACK
  0x400b9666, UNDO CLEAR 0x400b8656 (whose restore sequence the undo follows: memcpy
  0x40077fa0, step_lock_prep 0x400b528e, 945 data bytes, 0x3970 lock bytes, 228 per
  step), trig_flag_set 0x400b71aa (tp, step, mask, value), the seed read 0x41864b1c
  (fx_block's first read); KEY NOTE +0x1c8 and KEY SCALE +0x1c9.
- **The undo copy** (15.6 KB) is in this mod's `.bss` (core's mods' area) instead of
  free DDR at a fixed address.
- **One section.** The MK1 split the code over caves; here it is one `.text`.

## Resources (approved 2026-11-14)

No code sites; one `ev_track_key` handler (order 50) taking only presses of TRACK +
YES and TRACK + LEFT; core's track helpers; 1,072 B of code and 15,660 B of `.bss`.
No lock codes, destinations, storage, CCs, NRPNs, pages or settings.

## Status

**1.1** (core-a4mk2 0.8, not final yet): builds; lints against core 0.8; links in
AD23 (core 0.8 + dist + scale-lock + slide + rand-track) and AW23 (core 0.8 + wave +
scale-lock + slide + rand-track) with the AD21 / AW21 lockfiles, storage unchanged.
Not yet run in the emulator or on a unit. 1.0 (its own key-handler site, core 0.7)
was built and linked only, and is replaced by 1.1.

Worth checking in the emulator gate: YES and LEFT with a track key held on the main
screen and on a parameter page (another view could take them first); the pop-ups;
the undo after a random line and after a further edit; a track in per-track length
mode; the FX track (nothing happens); a scale-lock scale above MIN.
