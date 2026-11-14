# MKII ports (Analog Four MKII, OS 1.56)

The AE mods in `mods/` are for the Analog Four / Analog Keys **MK1**. This folder
holds their ports to the **MKII**, OS 1.56, as
[elekloader](https://github.com/irpina/elekloader) elemods: each folder has a
`mod.json` and its sources, built with elekloader's SDK and linked with core-a4mk2 0.7
(elekloader main, `mods/core-a4mk2`; from dist and wave 2.1 and scale-lock and slide 1.1,
which name core 0.7; the code is 2.0's and 1.0's). The pages go through core's page tables (`core_pages`,
`core_params`, `core_view_pages`) and the settings through its mod storage, so the
MK1's own copiers and page hooks (0006, most of 0008) have no counterpart here.

| folder | MK1 mods | what | status |
|---|---|---|---|
| [scale-lock](scale-lock/README.md) | 0001 | KEY SCALE with 35 scales; notes and the NOTE encoder kept in the scale | 1.0 hardware; 1.1 on core 0.7 not yet run |
| [slide](slide/README.md) | 0002 | 303 slide: the slide trig on the note you glide from | 1.0 hardware; 1.1 on core 0.7 not yet run |
| [dist](dist/README.md) | 0007, 0008 | DIST page behind AMP: a digital path with distortion per track; p-locks, and LFO/route/CC on DRV BIT SRR LEV (2.0) | 2.0 hardware (screens and values; not yet by ear); 2.1 on core 0.7 not yet run |
| [wave](wave/README.md) | 0010 | the noise generator as a wave or chord oscillator, on the NOISE page; mode and chord p-locks, chord as a stepped LFO/route target (2.0) | 2.0 hardware (screens and values; not yet by ear); 2.1 on core 0.7 not yet run |
| [rand-track](rand-track/README.md) | 0011 | hold a track key + YES: a random line in KEY NOTE + KEY SCALE with accents and slides; + LEFT undoes it | 1.0 built on core 0.7; not yet run |
| [res-limit](res-limit/README.md) | 0012 | RESONANCE LIMIT in SOUND SETUP: F1 RES plays as 0..80, F2 RES as 0..64, per synth track (kit) | 1.0 built on core 0.7; not yet run |

0006 (kit FX persistence) is core's mod storage here; dist and wave keep their
settings there, in the sound (from 2.0), which is what lets core (from core-a4 0.5) p-lock them.

"Hardware" means checked in rytm-emu's A4 build first, then on an Analog Four MKII (OS
1.56, core-a4 0.2, 24 Oct 2026): each README says what was checked and what was not.

## Building

With an elekloader checkout (main) and the stock OS 1.56 `.syx`:

```
python3 -m elekloader.sdk.build mods/core-a4mk2 --stock Analog-Four_MKII_OS1.56.syx
python3 -m elekloader.sdk.build mk2/dist --stock Analog-Four_MKII_OS1.56.syx
python3 -m elekloader.patch --stock Analog-Four_MKII_OS1.56.syx \
  --mod mods/core-a4mk2/out/core-0.7.elemod \
  --mod mk2/dist/out/dist-2.1.elemod \
  --out a4-ae.syx --version AD21 --lockfile a4-ae.lock.json
```

Keep the lockfile and pass it to every later build: it decides where dist's and
wave's settings sit in a kit and a sound, so a build made without it reads the
settings an earlier build saved as zeros (the defaults).

## What combines

- scale-lock and slide combine with either dist or wave.
- rand-track combines with every other mod (one key-handler site, no storage).
- res-limit combines with every other mod (two sites, 4 kit bits; no sound bits).
- **dist and wave do not combine** from 2.0: each keeps its settings in the sound
  (dist all 32 bits a sound keeps, wave 6), and each answers the knob-name getters.
  The patcher refuses the pair ("dist 2.0 site 0x4009e79e and wave 2.0 site
  0x4009e79e overlap"). Not every AE mod needs to fit in one build.
- slide's per-track switch is SLD on dist's page. Without dist, every synth track
  slides the 303 way.
- dist and wave take the sound's whole room between them, so neither can share a
  build with another mod that keeps sound fields beyond what is left (wave leaves 26
  bits, dist none).
- dist's page is page 50; the AE ports use no other page id. Mod knob ids: dist
  0x300..0x306, wave 0x310 and 0x311.

## Builds that cannot be made

- **dist with wave** (above).
- **dist or wave on core-a4 before 0.5**: they need its lockable parameters.
- **2.1 / 1.1 on core before 0.7**: they name core 0.7. Use dist and wave 2.0 and
  scale-lock and slide 1.0 for a core-a4 0.5 build (the code is the same).
- The MK1's `make hard` (HARD-only drive) has no elemod: dist always has the three
  characters.
