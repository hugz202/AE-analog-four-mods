# MKII ports (Analog Four MKII, OS 1.56)

The AE mods in `mods/` are for the Analog Four / Analog Keys **MK1**. This folder
holds their ports to the **MKII**, OS 1.56, as
[elekloader](https://github.com/irpina/elekloader) elemods: each folder has a
`mod.json` and its sources, built with elekloader's SDK and linked with core-a4 0.2
(elekloader main). The pages go through core-a4's page tables (`core_pages`,
`core_params`, `core_view_pages`) and the settings through its mod storage, so the
MK1's own copiers and page hooks (0006, most of 0008) have no counterpart here.

| folder | MK1 mods | what | status |
|---|---|---|---|
| [scale-lock](scale-lock/README.md) | 0001 | KEY SCALE with 35 scales; notes and the NOTE encoder kept in the scale | hardware |
| [slide](slide/README.md) | 0002 | 303 slide: the slide trig on the note you glide from | hardware |
| [dist](dist/README.md) | 0007, 0008 | DIST page behind AMP: a digital path with distortion per track | hardware |
| [wave](wave/README.md) | 0010 | the noise generator as a wave or chord oscillator, on the NOISE page | hardware |

0006 (kit FX persistence) is core-a4's mod storage here; dist and wave keep their
settings there.

"Hardware" means checked in rytm-emu's A4 build first, then on an Analog Four MKII (OS
1.56, core-a4 0.2, 24 Oct 2026): each README says what was checked and what was not.

## Building

With an elekloader checkout (main) and the stock OS 1.56 `.syx`:

```
python3 -m elekloader.sdk.build mods/core-a4 --stock Analog-Four_MKII_OS1.56.syx
python3 -m elekloader.sdk.build mk2/dist --stock Analog-Four_MKII_OS1.56.syx
python3 -m elekloader.patch --stock Analog-Four_MKII_OS1.56.syx \
  --mod mods/core-a4/out/core-0.2.elemod \
  --mod mk2/dist/out/dist-1.0.elemod \
  --out a4-ae.syx --lockfile a4-ae.lock.json
```

Keep the lockfile and pass it to every later build: it decides where dist's and
wave's settings sit in a kit and a sound, so a build made without it reads the
settings an earlier build saved as zeros (the defaults).

## What combines

- scale-lock, slide and dist each link on their own; wave needs dist (dist owns the
  knob-name hooks, `ae_names`, that wave names its knobs through).
- slide's per-track switch is SLD on dist's page. Without dist, every synth track
  slides the 303 way.
- dist takes all 128 bits of core-a4's kit storage, so it cannot share a build with
  another mod that keeps kit fields (elekloader's `store-check-a4`, for one). The
  patcher refuses that build (with store-check-a4: "the mods need 192 bits of kit
  storage; the analog-four-mk2 has 128").
- dist's page is page 50; the AE ports use no other page id.

## Builds that cannot be made

- **dist with another mod using kit storage** (above).
- **wave without dist**: the patcher refuses it ("wave 1.0 requires dist").
- The MK1's `make hard` (HARD-only drive) has no elemod: dist always has the three
  characters.
