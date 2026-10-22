# Hazards - Analog Four MKII

Read before flashing, and before writing a mod. (The MK1 branches have their own
version of this file; the MKII differs in the bootstrap, the code pools and the
cache.)

## The bootstrap is its own section - never touch it

The MKII `.syx` (ELE3) has five sections: 5 (metadata), 2 (the bootstrap: the
STARTUP menu and the DIN-MIDI OS UPGRADE that survive a bad OS), 1 (the FPGA image),
3 (MAIN OS) and 8 (the panel MCU image). The mods change MAIN OS only.
`tools/build.py` refuses a build whose other sections differ from the stock file's,
and `tools/verify.py` reads them back out of the finished `.syx` and compares them
again. Keep both checks. Unlike the MK1, MAIN OS carries no copy of the bootstrap,
so no pool needs to stay clear of one.

## MAIN OS unpacks over itself

The MKII bootstrap copies the packed MAIN OS to 0x40200000 and unpacks it to
0x40000400, over its own input. That only works while the unpacked output stays
behind the input still to be read. `tools/verify.py` simulates it and prints the
margin ("depacks in place with N B to spare": stock 540,191 B, our builds about
487,000 B); a build with no margin left must not be flashed. It also checks the file
ends below the 0x300000 flash limit.

## Where the mod code lives

`registry/allocations.toml` explains every pool. `cave` is the padding between the
C++ constructor table and `__bss_start` (0x40253000), `cave3` a 1 KB gap between
the chorus's lookup tables that no index can reach (0010 lives there, and its detour
on the chorus clamps the one index that could). `cave2` and `cave4`..`cave7` are DEAD
CODE: runs of routines the firmware contains but never calls (stock = "code" in the
registry; the build checks a hash of their stock bytes before writing there). The
case for them is static - no call, branch, pointer, vtable entry or switch-table case
reaches them. On the MK1 their twins were also shown never to run in long emulator
sessions and have since run the mods on hardware. On the MKII the same coverage check
(108 G instructions, 0 hits in every pool) promoted them to "probably-verified", and
the full build has since run from them through the MKII hardware test (2026-10-22). A new pool starts as "candidate", and `tools/layout.py`
refuses to let a feature mod use it until such a check is recorded in its note.
There is no room left in `cave`.

## Free DDR: 0x47be0000..0x47bfffff

0007 and 0010 keep their buffers and state in DDR at 0x47be0000..0x47be10c0. Nothing
in the MKII image refers to that range, and elekloader's DDR canary found it
untouched on an MKII. The MK1's choice, 0x4680xxxx beside the effect RAM, is not
known to be free on the MKII (its effect RAM moved). On the MKII the boot code caches
0x40000000..0x47ffffff (ACR0 `0x4007e020`), so this DDR is cached; the stubs still
copy state to the stack once per block and work there, as on the MK1, where the same
memory was uncached and per-sample access made the unit crash.

## Assembler target: ColdFire V4e, EMAC, NO FPU

`-mcpu=54455` (MCF5441x, which has no FPU at all; from re/symbols.toml [meta]), so
an FPU instruction in a stub is an assembly error instead of a crash on the unit.

## Verify before flashing, every time

`make verify` asserts:

- the stock `.syx` re-packs byte-identically (null repack)
- MAIN OS is unchanged in size and round-trips out of our `.syx`
- every other section (bootstrap, FPGA, panel MCU, metadata) is stock
- MAIN OS still unpacks in place with a margin, and the file fits in flash
- every byte that differs from stock lies inside a registry claim
- every detour jumps to its resolved entry, inside its own cave, and rejoins stock
  past exactly what it displaced
- no stub's movem overruns its stack frame

## Status means what it says

`built` means the image assembled and verified. Only `hardware-verified` counts, and
only for the exact image flashed.
