# Building a firmware

The output is a normal OS update file, `build/A4MK2_OS1.56_<name>.syx`, that you send to
the Analog Four MKII like any OS update (see docs/FLASHING.md).

## 1. One-time setup

You need `make`, `gcc`, `git`, Python **3.11 or newer**, and the m68k binutils.

**Linux (Debian / Ubuntu):**

```sh
sudo apt install make gcc git python3 binutils-m68k-linux-gnu
```

**macOS (Homebrew):**

```sh
brew install make git python m68k-elf-binutils
```

**Windows:** use WSL with Ubuntu 24.04 (it ships Python 3.12). In PowerShell:

```powershell
wsl --install -d Ubuntu-24.04
```

then, inside Ubuntu, the Linux line above. Run every command below from an Ubuntu
shell, in this folder (your Windows drives are under `/mnt/c/...`), or from
PowerShell as `wsl -d Ubuntu-24.04 --cd <this folder as a /mnt/... path> -- make full`.

**Then, in this folder:**

1. Download the official Analog Four MKII **OS 1.56** from Elektron and copy the
   `.syx` into `stock/` as `stock/Analog-Four_MKII_OS1.56.syx`.
   The build checks it against `stock/SHA256SUMS` and stops if it is a different
   file.
2. Fetch and build the container tool (once):

   ```sh
   make setup
   ```

3. Optional, but a good first step: prove the pipeline on your machine.

   ```sh
   make control
   ```

   This builds `build/A4MK2_OS1.56_control.syx` from the stock code with no mod at
   all, and checks that its MAIN OS reads back as stock and that every other section
   (bootstrap, FPGA, panel MCU) is the stock one.

## 2. Build

| command | builds | file |
|---|---|---|
| `make full` | all the mods in this release | `build/A4MK2_OS1.56_full.syx` |
| `make hard` | the same, with the drive in HARD only (no CHR knob, lighter on the CPU) | `build/A4MK2_OS1.56_hard.syx` |
| `make scale` | the scale lock only | `build/A4MK2_OS1.56_scale.syx` |
| `make slide` | the 303 slide only, on for every synth track | `build/A4MK2_OS1.56_slide.syx` |
| `make custom MODS="..." TAG=name` | your own selection | `build/A4MK2_OS1.56_name.syx` |

Each one ends by verifying the file it built and prints `PASS`. If it prints `FAIL`
or stops with an error, don't flash that file.

### Choosing mods

`MODS` is a space-separated list of mod folder names from `mods/`:

| mod | needs | gives |
|---|---|---|
| `0001-scale-lock` | - | scales in NOTE SETUP > KEY SCALE |
| `0006-fx-slot` | - | kit persistence for the settings below (does nothing alone) |
| `0007-digital-path` | 0006, 0008 | digital path + distortion, on the DIST page |
| `0008-pages` | 0007 | the DIST page (AMP pressed twice) |
| `0002-slide-303` | - (see below) | 303 slide |
| `0010-wave-osc` | 0006, 0007, 0008 | the digital wave / chord oscillator on the NOISE page |

Rules of thumb:

- The scale lock is independent: add it or not.
- The distortion is the three of them together: `0006-fx-slot 0007-digital-path
  0008-pages`.
- The wave / chord oscillator (0010) builds on those three: its knob and labels use
  their page machinery, so add it to them, not on its own.
- For the HARD-only drive, add `PARAMS="0007-digital-path:chr=0"` (what `make hard`
  does).
- The 303 slide works two ways:
  - **with** the distortion mods, it is switched per track on the DIST page (SLD);
  - **without** them there is no switch, so build it with the option
    `PARAMS="0002-slide-303:always_on=1"`, which puts every synth track on the 303
    slide (that is what `make slide` does). Without that option, and without the
    DIST page, it would do nothing.

The build checks the dependencies it can (0007 without 0008 stops with "require the
shared runtime ... no enabled mod provides it").

Examples:

```sh
# scale lock + distortion, no 303 slide
make custom MODS="0001-scale-lock 0006-fx-slot 0007-digital-path 0008-pages" TAG=scale-dist

# distortion and 303 slide, no scale lock
make custom MODS="0002-slide-303 0006-fx-slot 0007-digital-path 0008-pages" TAG=dist-slide

# the oscillator with the HARD-only distortion, no scale lock or 303 slide
make custom MODS="0006-fx-slot 0007-digital-path 0008-pages 0010-wave-osc" PARAMS="0007-digital-path:chr=0" TAG=wave

# scale lock + 303 slide on every track, no distortion
make custom MODS="0001-scale-lock 0002-slide-303" PARAMS="0002-slide-303:always_on=1" TAG=scale-slide
```

`make` alone (or `make verify`) builds the mods marked `enabled = true` in their
`mod.toml` (out of the box: the scale lock), as `build/A4MK2_OS1.56_0001.syx`.

## 3. Other targets

| command | what for |
|---|---|
| `make clean` | delete `build/` |
| `make disasm` | whole-image disassembly to `build/mainos.dis` (mod development) |
| `make cavescan` | list candidate free space in the image (mod development) |

## Writing a mod (short version)

A mod is `mods/<id>/mod.toml` + `stub.s`. It claims space and patch sites in
`registry/allocations.toml`: a `[[cave]]` for its code, a `[[detour]]` for each stock
instruction it diverts (with the exact stock bytes in `expect`), and `[[patch]]`es
for byte edits. Firmware addresses it uses go in `re/symbols.toml` (with the
evidence for each). The existing mods, their `design.md` files and
`docs/research/` show the method. The build and verify steps refuse overlapping
claims, wrong expected bytes, and detours that don't return where they should - but
only hardware testing tells you a mod is right.
