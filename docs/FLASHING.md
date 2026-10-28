# Flashing - Analog Four MKII

The A4 takes one format, a `.syx`, sent like any OS update. **Back up your projects
first** (Transfer, or C6), and keep the stock `stock/Analog-Four_MKII_OS1.56.syx`
at hand.

## Normal route (Transfer, USB)

1. Connect over USB, power on.
2. Transfer > CONNECTION: set MIDI IN and OUT to the Analog Four.
3. Transfer > DROP: drag the `.syx` on.
4. Confirm on the device if it asks.

The unit restarts by itself. This route runs inside the OS currently installed, so
it needs one that boots. **Do not power off during the first boot afterwards** (see
HAZARDS.md).

## Recovery route (STARTUP menu, DIN MIDI)

If a build ever fails to boot:

1. Hold `[FUNC]` while powering on.
2. Choose `4 ... OS UPGRADE` (`[TRIG 4]`).
3. In Transfer (or another SysEx tool), send the stock `.syx`. With Transfer:
   CONNECTION > "LEGACY OS UPGRADE mode", select the file, UPGRADE.

On the MKII the bootstrap is a section of its own in the `.syx`; our builds carry
Elektron's unchanged, and `make verify` checks that.

This is served by the bootstrap in flash, not by the OS, so it still comes up after
an OS that does not boot. It needs the DIN MIDI port (a MIDI interface into the A4's
MIDI IN), not USB.

## Suggested order for a first session

1. `build/A4MK2_OS1.56_control.syx` - optional, two minutes. Stock code, only repacked
   by the tool. If it boots and plays, the packer works on your unit, so any later
   problem is a mod, not the file format.
2. Your build (`make full`, or your own selection). On the MKII follow
   docs/HWTEST-MK2.md, which records what to look for on a first run.

## Back to stock

Builds carry version 1.56, the same as stock, so returning to stock is a same-version
reinstall of the official file by either route above.

Your data stays compatible both ways: kits and patterns saved on a modded OS load on
stock (the extra settings are ignored, and new scales read as KEY SCALE OFF).
