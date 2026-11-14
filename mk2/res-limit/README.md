# res-limit (Analog Four MKII, OS 1.56)

Resonance limit, AE 0012, ported to the MKII as an elemod.

FUNC + OSC1 (SOUND SETUP) gets a third checkbox after OSCILLATOR DRIFT and F1
RESONANCE BOOST: **RESONANCE LIMIT**. With it on, the track's filter resonances are
scaled, F1 RES 0..127 playing as 0..80 and F2 RES as 0..64, after the knob, p-locks,
LFOs and envelopes are added. That keeps the whole knob travel usable and stops the
filters from self-oscillating. YES toggles it; the encoder turns it on or off.

## Storage (decided 2026-11-14)

One kit field, `res_lim`, 4 bits (bit t for synth track t), in core-a4mk2's kit
storage: in the AD21 and AW21 lockfiles it sits at kit bits 0..3 of 128. It takes no
lock codes, no LFO or modulation destination, and no CC or NRPN.

So the setting is per synth track and kept with the kit, and it combines with dist
(which fills the sound's 32 bits) and with wave. Unlike the MK1 (bit 7 of the sound's
word 103) it does not follow a sound into the sound pool or a copy, and it takes no
locks. The FX and CV tracks show no checkbox.

## What changed from the MK1

- **The addresses**, traced in the MKII 1.56 image in Ghidra (MK1 in brackets in
  `res-limit.s`):
  - The voice parameter words are 0x80005af0 + 8p + 2v. The audio interrupt rebuilds
    them every block and adds the modulation in place, clamped to 0..0x7fff
    (0x401032d2..0x40103432).
  - 0x400ff74e builds the filter words of the analog frame from them. F1 RES is
    0x80005bb8 + 2v (frame word 7, with RESONANCE BOOST's flag 0x800042e6 + v) and
    F2 RES is 0x80005bd8 + 2v (frame word 10), 0x20 apart as on the MK1.
  - The voice's track is 0x80005ff0 + 4v.
- **The engine hook** is the interrupt's call just before the frame builders
  (`jsr 0x400fa2b0.l` at 0x40103af6). The mod scales the two RES words of each voice
  whose track has the switch, makes the call and rejoins.
- **Not `ev_analog_frame`.** The frame words carry per-voice calibration offsets, and
  F1's word also depends on RESONANCE BOOST and F1 FREQ, so scaling the frame would
  not scale the resonance. Scaling the parameter word, as the MK1 does, is exact.
- **The SOUND SETUP item** is added after BOOST's in the builder 0x400e5f54 (site
  0x400e62c8). It is built from BOOST's four callback managers (0x400e43b8 + 0x52 k),
  op_new 0x400653b8 and menu_toggle_item 0x4005c7c4, as on the MK1. core 0.7 has no
  hook for this menu.
- **The setting** is read and written through `core_store_get` / `core_store_set`.
  The UI tick and each project load copy the current kit's four bits into `res_on`,
  which the audio interrupt reads.

Neither site is one of core-a4mk2 0.7's or another MKII AE mod's.

## Checked

Built and linked in the cloud with core-a4mk2 0.7 (sha256 `03d8677a…`) against the
AD21 and AW21 lockfiles: ADR1 (core, dist 2.1, scale-lock 1.1, slide 1.1, res-limit
1.0) and AWR1 (the same with wave 2.1). The lockfiles gained only `res_lim`.

## Not checked

- Anything in the emulator or on a unit. The RES words are read from the code
  [Ghidra]; the gate's first job is to show that the switch scales F1 and F2 RES.
- The sound by ear (a draft until the owner's listening check).
