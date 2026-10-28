# Porting the mods to the Analog Four MKII, OS 1.56 (2026-10-21)

**Status: ported, hardware-tested.** This branch (MK2-OS-1.56) builds every target
for the Analog Four MKII OS 1.56 and verifies it (`make control scale slide full
hard`, PASS). The control, scale+slide and full builds passed all 14 steps of
docs/HWTEST-MK2.md on the owner's MKII (2026-10-21..22; results and hashes at the end
of that guide). The HARD build has not been flashed on an MKII. Evidence tags as in the rest of
the project: [measured] = static analysis of the stock image or tool output,
[emu] = the rytm-emu A4 emulator (dtboot), [hw] = an MKII unit, [inferred] = not
checked directly.

| mod | MKII state |
|---|---|
| 0001 scale lock | hardware-verified [hw 2026-10-21]; [emu] 35 scales + OFF in KEY SCALE, live keys snap, the NOTE encoder steps in-scale |
| 0002 303 slide | hardware-verified [hw 2026-10-21, after the LEN table fix]; [emu] hooks run during playback, no fault in a 10 G soak; the glide itself needs [hw] |
| 0006 kit FX persistence | hardware-verified [hw 2026-10-22, step 9]; [measured] same copiers and spare words as the MK1 |
| 0007 digital path | hardware-verified [hw 2026-10-22, steps 5-10]; [measured] every host traced by hand (see below); [emu] full/hard boot, "AMP (P 1/2)" then "DIST (P 2/2)" with its knobs, 12-30 G of playback with DIG on and settings changing, no fault |
| 0008 DIST page | hardware-verified [hw 2026-10-22]; [measured] MKII view size and map offset; [emu] the page opens and is edited by its knobs; [hw] CHR drew nothing until it moved to the PAN knob (see below) |
| 0010 wave oscillator | hardware-verified [hw 2026-10-22, steps 11-13; two sounding chord tracks is the comfortable maximum]; [measured] noise block, NCO words and chorus index traced; [emu] NOISE page OFF / WAV / CHD and the chord names, relabelling SHP FLD FM |

`make full` and `make hard` use the dead-code pools (cave2, cave4..cave7). An
emulator coverage run on stock showed none of them ever runs, and they were promoted
to "probably-verified" (2026-10-21; see "Code space"). The full build has since run
from them on an MKII (docs/HWTEST-MK2.md, 2026-10-22).

The emulator's A4 voice model muted a voice's effect send along with its closed VCA,
which made DIG-on tracks silent there; with the send taken before the VCA (an opt-in
emulator fix) a DIG-on track plays through the effects path, about 15 dB below DIG
off by the emulator's own (inferred) level scaling. Only the unit can settle the
level.

## The two images

| | MK1 1.56 | MKII 1.56 |
|---|---|---|
| CPU | ColdFire V4e (MCF5475 family) | ColdFire V4e (MCF5441x), assembled with `-mcpu=54455` (no FPU) |
| container | ELE2, one section (MAIN OS) | ELE3, sections 5, 2 (bootstrap), 1 (FPGA), 3 (MAIN OS), 8 (panel MCU) |
| MAIN OS | 2,372,584 B | 2,500,408 B, sha256 748fec15...a474c |
| load base / entry | 0x40000400 | 0x40000400 / 0x40001130 |
| bootstrap | embedded in MAIN OS, rewritten from it at boot | its own section 2; no build touches it |
| `__bss_start` | 0x40235000 | 0x40253000 |
| ACR0 (cached DDR) | 0x4003e020: 0x40000000..0x43ffffff | 0x4007e020: 0x40000000..0x47ffffff |

Both are the same Elektron code base. Addresses were mapped from the MK1 image
with AE's k-gram vote (`tools/xmatch.py`) and a listing comparison
(`re/mk2/map_mk2.py`): 135 addresses, 103 clean on the first pass, and every weak
match was then checked by hand against the MK1 listing. The `mk1 =` and `mk2 =`
fields of each entry in `re/symbols.toml` record the MK1 address and how the MKII
one was found.

The container is packed by the same tool. The MKII bootstrap depacks MAIN OS in
place from 0x40200000 to 0x40000400, over its own input, so `tools/verify.py` now
also checks the in-place gap stays positive (stock 540,191 B, our builds about
487,000 B) and that the container ends below the 0x300000 flash limit. The tool's
recompression of stock is not byte-identical on the MKII (its re-pack is), so
`make control` asserts "MAIN OS round-trips to stock and every other section is
stock" rather than file identity.

## What changed for each mod

### 0001, 0002, 0006

Every host function listing is identical [measured]: the scale tables and names,
the LEN tick table, the pattern offsets (93894, 93900, 453, 458, 945), the page and
lock vtable slots (0x54, 0x70), KEY_FUNC 0x80, the kit copiers and the spare FX
words. Only addresses moved.

### Project and kit layout

The project is 0x3df14 B (MK1 0x3de9c). The active kit pointer is at project + 364
(MK1 + 244), so `PROJECT_KIT_FX_STORAGE` is 4524 (MK1 4404) and 0007's
`PROJECT_FXSETUP` is 364 + 0x1030. The kit's own layout (FX setup at kit + 0x1030,
the live sounds at S - 1352 + 338 t, parameter word 103 at +226) is unchanged
[measured: the same converter, copier and FxSetup setter code].

### 0008 DIST page

- Page views are 0x1c4 B (MK1 0x260); the controller's view map is at + 444
  (MK1 + 436); the plain ParameterPageView vtable is 0x4018d650.
- The knob draw (0x400234c4) builds its frame with `lea -68(%sp),%sp; movem.l`
  instead of `link`, so the gate re-emits those 8 bytes.
- Page titles carry the page count: AMP's is "AMP (P 1/2)", so the stub's own
  strings are "AMP (P 1/2)" and "DIST (P 2/2)", and page 11's name pointer is
  patched to the new AMP title.
- The page table (44 B per page, base 0x401b31e8) holds the same parameter ids on
  every page as the MK1's [measured: all 48 entries compared], so the DIST page's
  ids (50 92 94 95 96 98 63) and 0010's NOISE ids are unchanged.
- **CHR is knob id 97 (AMP PAN) on the MKII, not 92 (AMP REL).** The knob draw
  (0x400234c4) hands each knob to its parameter record's draw function (vtable +0x84,
  0x4009eaaa: record + 36, records of 84 B from 0x41856c44). On the MKII ATK, DEC,
  SUS and REL are drawn together as the AMP page's envelope graph; REL's own draw
  (0x400f1d32) only places an envelope sprite, which shows nothing on its own: on the
  DIST page CHR had a label and no value [emu, hw 2026-10-21]. PAN's draw
  (0x400f2da4) is a centre-marked line with a marker at x + (v - 64) / 8, tall at 0,
  64 and 127, so `pgv_gate` now hands three-position knobs 0 / 64 / 127 and CHR shows
  HARD / RAT / OD as left / centre / right [measured]. The DIST page's ids are
  50 97 94 95 96 / 98 63; the MK1 keeps 92, which it draws as a dial.

### 0007 digital path

- **Labels.** The parameter sets' vtable lost three slots: the label formatter is
  +0x78 (MK1 +0x84) and the short-name getter +0x68 (MK1 +0x74). Their entry bytes
  and arguments are the MK1's [measured: the knob draw calls +0x78 with (set, id,
  x, char buffer) and +0x68 with (set, id)], so `lbl_gate` and `sname_gate` are
  unchanged.
- **Dry mute.** In track_levels the volume pointer is a3 and the left gain d7 (MK1
  a2, d5): the site is `movel %a3@,%d0; macl %d0,%d7,%acc0` at 0x400fa6c4, resume
  0x400fa6ca. d1 and a0 are dead there, d2 is the track [measured]. The dry VCA
  words go to 0x80003d6c + 26 t (MK1 0x800032b0).
- **FX block frames.** The send mix reads codec slots 2..7 of each 32-byte frame
  (MK1 0, 1, 2, 3, 6, 7): it starts 8 bytes in, and the gain registers are applied
  in the same order as on the MK1, where the first four are the voices [measured].
  So track t is slot 2 + t, and `fxin_gate` starts at frames + 8 (`VOICE0_SLOT`).
  To confirm on [hw]: a DIG-on track still feeds the delay/reverb.
- **Values while turned.** The knob draw shows the label formatter's text while a
  knob is turned and the short name otherwise; the formatter is handed the value
  page_get_value returned, which on the DIST page is ours. So `lbl_gate` now lets
  stock format DRV BIT SRR LEV (numbers, as the host AMP knobs) and DIG / SLD
  (switches: the graphic is the value, the label stays), and names CHR's value
  HRD / RAT / OD itself (`chr_name`) [emu]. The MK1 build keeps the names.
- **Idle chord tracks.** 0010 computed the oscillator for every voice whose sound
  had WAV or CHD on and a noise LEV above 0, whether or not a note sounded. On the
  MKII two such tracks made the encoders sluggish with no pattern running [hw
  2026-10-22], and pasting a chord sound to a third track once froze the unit [hw,
  not reproduced since]. wave_gate now skips a voice whose VCA word in the analog
  control frame (0x80003d82 + 26v, 0x7fff = closed: at rest, and again at the end
  of a release [emu]) is closed, and clears its three sources instead, so a note's
  first block is silent rather than stock noise. [emu]: four idle chord tracks cost
  nothing (idle time back to the stock 51 %, from 36 % with four 4-note chords
  held); the voices' output while a note sounds is unchanged. [hw] after the change: two
  chords held (16-step trigs) leave the UI responsive, three slow it. The owner chose
  to document that limit rather than trade sound for speed (half-rate chords).
- **DIG and WAV on one track: silent [hw 2026-10-24].** DIG zeroes the track's dry VCA
  word, which is the word wave_gate reads to skip an idle voice, so with DIG on the
  oscillator is skipped while notes play. The fix (compute every DIG track) needs about
  70 bytes and every pool here is full, so it stays a documented limit of this branch;
  the elemod port (`mk2/`, wave 1.1) has it.
- **LEV's level [hw 2026-10-24].** Measured over USB at C4, LEV 98: DIG on is about 1 dB
  under DIG off (the MK1 calibration holds); at E0 it is about 15 dB under, because the
  digitised copy carries little of the lowest notes.
- **Encoder steps.** The MKII's encoder handler is rewritten (per-parameter count
  scaling and acceleration) and hands param_apply_delta whole steps in 8.8: an
  8-count turn arrives as 0x200 [emu]. On the NOISE page's mode knob that jumped
  OFF to CHD past WAV [hw 2026-10-22]. One detent per position then felt touchy,
  so `step_of` counts the turns per knob and moves settings of 3..16 positions
  (CHR, the mode, the chord) one position per three turns, each turn counted as one
  plain step whatever its speed (two felt touchier than AMP SHP by about half
  [hw 2026-10-22]), starting over on another knob or a change of
  direction. That copies the encoder profile stock gives stepped parameters: the
  MKII's 0x417356f4 and the Rytm 1.74's BD HARD WAV profile 0x417e37ac read 6 counts
  a step with no acceleration, where our host knobs' profile (0x4173572c, as the
  Rytm's SNP) reads 3 counts with acceleration [emu, both read at boot]; switches toggle once per turn and dials
  take the delta as before. The running sum lives at 0x47be1100 (free DDR).
- **FX state.** fx_block_tail stores to 0x41864a74 (MK1 0x415c0008).
- **DDR.** The MK1's free DDR (0x4680xxxx, beside the effect RAM) is not known free
  on the MKII: no 32-bit word in the MKII image points at 0x46800000 or 0x46810000,
  so its effect RAM moved. The buffers go to 0x47be0000..0x47be02e0, inside
  0x47be0000..0x47bfffff, which nothing in the image refers to and which
  elekloader's DDR canary showed untouched on an MKII [hw, elekloader]. That DDR is
  cached on the MKII; the stub still copies its state to the stack per block.

### 0010 wave oscillator

The noise generator's code is the MK1's instruction for instruction; its SRAM block
moved [measured, aligned listings]:

| | MK1 | MKII |
|---|---|---|
| fade envelopes | 0x80001be8 | 0x80002be8 |
| the mix's sources (+140 v) | 0x80001d78 / 1fa8 / 21d8 | 0x80002d78 / 2fa8 / 31d8 |
| LEV / COL words | 0x800050e0 / 50e8 | 0x80005ba0 / 5ba8 |
| FAD / S&H words | 0x80005358 / 5360 | 0x80005e18 / 5e20 |
| voice -> track | 0x80005530 | 0x80005ff0 |
| OSC1 NCO (+8 v, +4 OSC2) | 0x80005f6c | 0x80006a2c |
| chorus index byte | 0x8000517e | 0x80005c3e |

The chorus's signed index scales into the table at 0x40215658, right above cave3,
so the clamp in `cho_gate` matters exactly as on the MK1. The oscillator's state
moved to 0x47be1010.. (see DDR above).

## Code space

| pool | MKII | size | status | used by |
|---|---|---|---|---|
| cave | 0x40252940..0x40253000 | 1,728 B | probably-verified | 0001, 0006, 0002, 0008, 0007 (.ui2), 0010 gates |
| cave2 | 0x40093bb2..0x40093ea8 | 758 B | probably-verified | 0007 (.text) |
| cave3 | 0x40215258..0x40215658 | 1,024 B | probably-verified | 0010 (.gap) |
| cave4 | 0x401845be..0x4018471e | 352 B | probably-verified | 0007 (.ui3) |
| cave5 | 0x40090754..0x400908ac | 344 B | probably-verified | 0007 (.ui4) |
| cave6 | 0x40056e14..0x40056f52 | 318 B | probably-verified | 0007 (.dsp2) |
| cave7 | 0x400d3a52..0x400d3b5e | 268 B | probably-verified | 0007 (.ui5, new) |

`cave` is 224 B smaller than the MK1's, so 0007's label lookup (`name_of` and its
names) moved out of it into a new section, `.ui5`, in cave7: the start of a
constructor nothing calls. After that `cave` is full to the byte.

The dead-code pools are the twins of the MK1's (cave7 is new) and pass the same
static scan (`re/mk2/deadscan_mk2.py`: no branch, call, pointer or switch-table case
reaches them). As on the MK1, emulator coverage then showed they never run: six
sessions on stock MKII 1.56, 108 G instructions (54 G executed), 34,677 distinct
16-byte code lines across the UI, sequencer, kits and menus (not USB, SysEx or the
test menus), with 0 hits in every pool; the same recorder shows them running in the
mod builds. They are "probably-verified" since (2026-10-21).

## Not ported

- 0004 (a measuring probe) is not part of this branch.
- The audio interrupt's body and exit (`audio_isr_body`, `audio_isr_exit`) are
  mapped but no mod uses them; on the MKII the interrupt keeps its frame in %fp, so
  a gate at the exit may use every register but %fp.
