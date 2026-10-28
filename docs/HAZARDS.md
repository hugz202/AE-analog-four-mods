# Hazards - Analog Four / Analog Keys MK1

Read before flashing, and before writing a mod. (The same platform - ColdFire, MAIN
OS with an embedded bootstrap - is used by the Analog Rytm MK1; the same rules hold
there.)

## The bootstrap lives INSIDE MAIN OS - never write into it

The `.syx` has one section, MAIN OS, and the bootstrap (the STARTUP menu and the
DIN-MIDI OS UPGRADE that survive a bad OS) is carried inside it:

- `0x40226958` holds the embedded bootstrap's version words, `0x40226960..0x40233a30`
  its image (53,456 B).
- At every boot the startup code (`0x40000e6a`) compares that version with the one in
  flash at `0xfff8`. If the embedded one is newer, `0x401006dc` erases the bootstrap
  sectors and writes the embedded image into them.

So a mod byte anywhere in that range could one day be written into the recovery path.
Hence:

- No pool may overlap `0x40226958..0x40233a30`. The nearest, `cave2`, starts 16 bytes
  past its end.
- `tools/build.py` refuses to write a build whose embedded image differs from stock,
  and `tools/verify.py` checks it again on the `.syx` it reads back
  ("embedded bootstrap image unchanged"). Keep both checks.
- Do not power off during the first boot after flashing. If your unit was on an OS
  older than 1.55, that boot may be a genuine bootstrap upgrade (with our builds it is
  the manufacturer's own, unmodified image that gets written).

## Where the mod code lives

`registry/allocations.toml` explains both code pools. `cave` is the padding between
the C++ constructor table and `__bss_start`; `cave2` is the padding right after the
embedded bootstrap image. The case for both is static - nothing points into them,
nothing reads them as a table, they are below the `.bss` clear and the SRAM copies -
and both have since run the mods on hardware. On OS 1.56 the embedded bootstrap grew 1,424 B and fills what was
`cave2` on 1.55, so on this branch `cave2`, `cave4`, `cave5` and `cave6` are DEAD
CODE: four runs of routines the firmware contains but never calls (stock = "code" in
the registry; the build checks a hash of their stock bytes before writing there).
The case for them is static - no call, branch, pointer, vtable entry or switch-table
case reaches them - plus emulator coverage: they never ran in seven long sessions
that reached 540 KB of code. The first hardware run (2026-10-17, `make hard`) went
through the whole checklist cleanly. The mods added since (0010's chord labels, 0011,
0012) use more of these dead-code runs, `cave7` .. `cave28`, found and guarded the
same way; those builds have run on the instrument too. A third, `cave3`, is a 1 KB gap
between the chorus's lookup tables that no index can reach (0010 lives there, and
its detour on the chorus clamps the one index that could). There is almost no room
left: a new mod has to find space (`make cavescan` lists candidates, most of which
turn out to be the ends of tables still in use) or share it.

## DDR above 0x44000000 is not cached

The boot code caches only 0x40000000..0x43ffffff (ACR0 `0x4003e020`; the default
mode is cache-inhibited). The effect delay lines, and the mods' own state in the
free DDR beside them (0x4680xxxx), are therefore uncached: every access is a full
bus round trip. Code in the audio interrupt must not touch that memory per sample.
Copy the state to the stack (cached) once per block, work there, and write it back.
An early version of 0010 kept its working state there and made about 1,000 such
accesses per block on each chord voice: the UI slowed down and the unit could crash.

## Assembler target: ColdFire V4e, EMAC, NO FPU

`-mcpu=5475 -mno-float` (from re/symbols.toml [meta]). With -mno-float an FPU
instruction in a stub is an assembly error instead of a crash on the unit.

## Verify before flashing, every time

`make verify` asserts:

- stock `.syx` rebuilds byte-identically (null repack)
- MAIN OS is unchanged in size and round-trips out of our `.syx`
- the embedded bootstrap image is stock, and the `.syx` carries MAIN OS only
- every byte that differs from stock lies inside a registry claim
- every detour jumps to its resolved entry, inside its own cave, and rejoins stock
  past exactly what it displaced
- no stub's movem overruns its stack frame

## Status means what it says

`built` means the image assembled and verified. Only `hardware-verified` counts, and
only for the exact image flashed.
