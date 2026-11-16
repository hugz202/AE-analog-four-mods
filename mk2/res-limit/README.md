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

## 1.1: on core-a4mk2 0.8's events

1.1 needs core-a4mk2 0.8 (upstream in irpina/elekloader from 339680d, #397) and has no sites of its own. The scaling runs in core's
`ev_voice_params` (at 0x40103af6, the same point as 1.0's site), with `VP_F1_RES` /
`VP_F2_RES`. The row comes from core's `ev_sound_setup` and
`core_sound_setup_toggle` (at 0x400e62c8, after BOOST's row). The storage, the
scaling and the menu row are the same as 1.0's. 1.0 (res-limit.s, core 0.7) is
in git history.

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

## Emulator gate (1.1, 14 Nov 2026)

Gated in the A4 emulator (elkbench, PC) as R8L2, sha256 `00eb89e8…`: core-a4mk2 0.8
at 97a5ff0 (`dcfc8735…`, byte-identical to upstream 0.8 at 339680d), dist 2.1, scale-lock 1.1, slide 1.1, res-limit 1.1
(`b9d13afb…`) and the analoghealth 1.2 harness. Lockfile: AD21's plus `res_lim` at
kit bits 0..3. Both flashes passed (over stock 1.56 and back). Plan t-r8l2 passed
from the fresh, dirty and testslot-cleared starts. Voice 0 read:
- F1 and F2 RES 0x7f00 with the limit off
- 0x5000 and 0x4000 with it on, stopped and playing
- the limit on and F1 RES 0x5000 after a save and reload
- 0x7f00 again with it off
The checkbox redraws on YES.

## Unit run (T380, 16 Nov 2026)

R8L2 ran on an Analog Four MKII (OS 1.56) and passed. With the limit off, F1/F2 RES read 0x7f00. With it on, F1 read 0x5000 and F2 0x4000, stopped and playing. The setting was kept after a save and reload, and both were back to 0x7f00 when it was switched off. The checkbox redraws on YES. CPU was 79.1 % and DSP 75.1 %.

## Listening (16 Nov 2026)

The owner listened to R8L2 on the Analog Four MKII, T1 playing four notes a bar.

- Run t-r8l3 (filters at a new sound's default): with the limit off at RES 127, F1
  self-oscillated at about 22.5 kHz (-25 dBFS RMS) and held the note about 18 dB down.
  With the limit on, that tone fell to about -60 dBFS and the note came back at the
  plain level (-43 dBFS), heard as much louder.
- Run t-r8l4 (F1 FREQ 64, F2 FREQ 24, limit off): RES 64 resonance on both filters,
  RES 80 no self-oscillation, RES 96 maybe a little, RES 112 self-oscillation with
  clipping, RES 127 self-oscillation with more distortion. With the limit on at RES 127:
  no self-oscillation.

So on the MK2 self-oscillation starts between RES 80 and 96 at these settings, and the
MK1 caps (F1 80, F2 64) keep both filters below it. The owner kept the MK1 caps.

## Not checked

- Only T1 (voice 0) was read, and the wave build (AW + res-limit) was not gated.
- RESONANCE BOOST stayed off in the listening runs.
- Higher filter frequencies were not swept by ear.
