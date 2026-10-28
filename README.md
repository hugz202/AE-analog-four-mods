# Analog Four / Analog Keys MK1 - OS 1.56 mods

Build pipeline that patches the official Analog Four / Analog Keys MK1 OS 1.56
firmware with extra features :

| mod | what it does |
|---|---|
| **0001 scale lock** | KEY SCALE in NOTE SETUP gains 35 scales; live notes, trig-key step entry and the TRIG page NOTE encoder stay in KEY NOTE + KEY SCALE (Digitone II style) |
| **0002 303 slide** | per track: put the slide trig on the note you glide *from*; it is tied into the next note, which glides in legato - no LEN tweaking |
| **0006 kit persistence** | lets the kit carry the extra per-track settings below through saves and power cycles (stock kits still load; stock simply ignores the extras) |
| **0007 digital path / distortion** | per track, swap the analog dry signal for the A4's own digitised copy and run it through drive (HARD / RAT / OD characters, or HARD only in the lighter `make hard` build), bit and sample-rate reduction - the distorted signal also feeds the delay, reverb and chorus |
| **0008 DIST page** | a second AMP page (press AMP twice) holding 0007's settings and 0002's slide switch |
| **0010 digital wave / chord oscillator** | per sound, the noise generator becomes a digital oscillator at OSC1's pitch: sine / triangle / saw / square morph, wavefolder, FM from a sine at OSC2's pitch - or a chord of it (13 types, including a Hendrix 7#9 and two 4-voice supersaws); the NOISE page is relabelled for it, and the setting is saved in the sound |

How to use them on the instrument: [docs/MANUAL.md](docs/MANUAL.md).
How to build a firmware with the mods you want: [BUILD.md](BUILD.md).
How to flash and get back to stock: [docs/FLASHING.md](docs/FLASHING.md).
**Read [docs/HAZARDS.md](docs/HAZARDS.md) before flashing.**

## MKII

Ports of these mods to the Analog Four **MKII**, OS 1.56, as elekloader elemods, are in
[mk2/](mk2/README.md). Everything else in this README is about the MK1.

## What you need

- An Analog Four or Analog Keys **MK1** (not the MKII), and the official **OS 1.56**
  `.syx` from Elektron's website. It is not included here: download it and put it in
  `stock/` (`stock/SHA256SUMS` lists the exact file the mods are built against).
- A machine that can run the build: Linux, macOS, or Windows with WSL (Ubuntu).
- Transfer (Elektron's app) or any SysEx tool to send the firmware.

## How it works

The stock firmware is unpacked, and each mod adds small ColdFire assembly routines
in unused space of the image plus a few "detours" - jumps from stock code into those
routines. Every patched location is listed in `registry/allocations.toml` with the
exact stock bytes it expects, and the build refuses to touch anything that does not
match. `make verify` then reads the finished `.syx` back and checks every changed
byte, the untouched bootstrap (the recovery menu), and each detour's return path.
The firmware stays version 1.56, so going back to stock is a normal reinstall.

## OS versions

Each OS has its own branch: **OS-1.56** (this one) and **OS-1.55**. The mods and how
they work are the same; the firmware addresses, the free space they use and the
stock file they are built from differ. Build the branch that matches the stock file
you have. A build is a complete OS, so flashing an OS-1.55 build onto a unit running
1.56 (or the reverse) changes its OS version - back up first.

On 1.56 the bootstrap image grew into one of the free areas 1.55 builds used, so part
of 0007 lives in routines the firmware contains but never calls (found by static
analysis and checked in emulator sessions; see docs/PORT-1.56.md and docs/HAZARDS.md).

## Layout

```
mods/<id>/         one folder per mod: mod.toml (what it is, what it needs),
                   stub.s (its code), design.md (how it was worked out, if any)
registry/          allocations.toml: every patched address, its expected bytes, owner
re/                symbols.toml: the firmware addresses the mods use, with evidence
tools/             build.py, verify.py, layout.py, symbols.py (+ dev tools)
docs/              MANUAL, FLASHING, HAZARDS, research notes
stock/             put the official OS 1.56 .syx here
```

## Status

On OS 1.56 the `make hard` build has run the whole first-flash checklist on an
Analog Four MK1; `make full` (the three drive characters) has been checked in an
emulator only. On OS 1.55 both have run on the instrument. Other combinations build
and verify, but have had less play time.

## Thanks

- [elektron-firmware-tool](https://github.com/mischa85/elektron-firmware-tool) by
  mischa85, which packs and unpacks the `.syx` (fetched by `make setup`).

## License

MIT - see [LICENSE](LICENSE). This covers the mods, tools and documentation here.
It does not cover Elektron's firmware, which you supply yourself, or the
elektron-firmware-tool that `make setup` downloads (MIT, its own licence).

## Disclaimer

This is unofficial, modified firmware. It is not made, endorsed or supported by
Elektron. You use it at your own risk; read HAZARDS.md first. The OS can always be
reinstalled from the stock `.syx`, including from the STARTUP menu if a build ever
fails to boot.
