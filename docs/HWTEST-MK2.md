# First run on an Analog Four MKII

A step list for the first time these builds go onto an MKII. Each step names what
it proves, so a failure points at one place. Back up first (Transfer, or a project
save to +Drive and a SysEx dump), keep the stock `.syx` at hand and a DIN MIDI
interface ready for the recovery route (docs/FLASHING.md). Note the result of every
step, including "as expected".

## Round 1: the container, the scale lock, the slide

1. **Control.** Flash `build/A4MK2_OS1.56_control.syx`. It must boot and play a
   pattern like stock. Proves our packer's MAIN OS and the untouched bootstrap,
   FPGA and panel sections install and boot on the MKII. Stop here if it fails and
   go back to stock.
2. **Scale lock.** Flash `build/A4MK2_OS1.56_scale-slide.syx` (scale lock + 303
   slide on every synth track; `make custom MODS="0001-scale-lock 0002-slide-303"
   PARAMS="0002-slide-303:always_on=1" TAG=scale-slide`).
   - NOTES SETUP (FUNC + NOTE): KEY SCALE steps OFF, MAJ, MIN, DOR ... LO37 and
     shows each name; it stops at LO37.
   - KEY NOTE = C, KEY SCALE = MAJ, KEYBOARD mode: black keys play a neighbouring
     white note; with OFF they are chromatic again.
   - TRIG page NOTE encoder steps C D E F G A B C for MAJ.
   - Save the pattern, power-cycle, reload: KEY SCALE is kept.
3. **303 slide.** On track 1, a pattern with notes on steps 1 and 5, a slide trig
   on step 1 (the note you glide *from*). Play: step 1's note is held into step 5,
   which glides in. Without the slide trig the notes are separate.

## Round 2: the full build (after the dead-code pools are promoted)

Flash `build/A4MK2_OS1.56_full.syx` (or `make hard` for the HARD-only drive).

4. **Boot and play** a pattern as stock. Then work a few minutes across pages and
   menus: this is the first time code runs from the dead-code pools on an MKII.
   Any freeze, reboot or garbage on screen: note what you did last, go back to
   stock.
5. **DIST page.** Track 1, AMP: the title reads "AMP (P 1/2)"; AMP again: "DIST
   (P 2/2)" with DIG CHR DRV BIT SRR / LEV SLD (HARD build: DIG DRV BIT SRR LEV /
   SLD), edited by turning the knobs (no FUNC). AMP again returns to AMP. CHR
   draws a short line with a marker: left = HARD, centre = RAT, right = OD (the
   first build drew nothing there; fixed 2026-10-21), and while turned its label
   reads HRD / RAT / OD. It should take about as much turning per position as
   AMP SHP takes per shape.
6. **The right track goes digital.** Play tracks 1..4 together. DIG on track 1
   only: track 1's analog dry sound is replaced by its digitised copy, the other
   three are unchanged. Repeat for track 4. *This is the MKII-specific check of
   the codec slot mapping (docs/PORT-MK2.md, "FX block frames"): if DIG on track 1
   mutes track 1 but processes another track, or the external input, stop and
   report which.*
7. **Distortion and effects.** DIG on, DRV up: grit rises at about the same level;
   CHR HARD / RAT / OD differ; BIT and SRR crush. Turn up the delay or reverb send:
   the effects hear the distorted sound.
8. **Level.** DIG on, LEV around 100 sounds about as loud as DIG off. (The
   emulator measured DIG on about 15 dB lower, but its level scaling is a guess;
   only the unit can say.)
9. **Persistence.** Save the kit, power-cycle, reload the kit: the DIST settings
   are kept. Load a kit saved on stock: DIG is off everywhere.
10. **Slide switch.** SLD on the DIST page turns the 303 slide on for that track
    (in the full build the slide is per track, not always on).
11. **Oscillator.** OSC1 page pressed twice shows NOISE ("NOISE (P 2/2)"). Knob 4
    to WAV: labels SHP FLD FM WAV LEV; with NOISE LEV up and OSC1/OSC2 LEV at 0 a
    pitched tone follows notes, TUN and bend (proves the MKII NCO words); SHP sweeps
    sine -> triangle -> saw -> square; FM adds sidebands at OSC2's pitch.
12. **Chords.** Knob 4 to CHD: knob 6 names the chord (OCT ... SW2) and the chord
    plays. Save the sound to the pool, load it on another track: the setting comes
    along. Two chord tracks held together keep the UI responsive; a third slows
    it (the documented limit).
13. **Chorus.** Chorus send up with its HPF swept by an LFO: no clicks or bursts.
14. **Back to stock** by Transfer: the unit returns to stock 1.56 and the projects
    load.

Record the results (with the build's sha256 from `build/manifest_<tag>.json`) in
the project notes; only then can a mod's status move to `hardware-verified`.

## Results: the owner's MKII, 2026-10-21..22

All 14 steps passed [hw]. Builds as flashed (`syx_sha256` from the manifests):

| step | build | result |
|---|---|---|
| 1 | control `249f53b0...` | boots and plays like stock |
| 2-3 | scale-slide `89131c76...` (after bb512fb) | scale lock as listed; the slide glides. The first scale-slide build cut the slide-from note short: 0002 used the MK1's LEN tick table (fixed in bb512fb) |
| 4-11 | full, builds of 839c0d6 .. 2c4fd66 | pools run without fault; DIST page, digital path, distortion, level, persistence, slide switch, oscillator. Fixed on the way: CHR drew nothing on AMP REL (moved to PAN, 839c0d6); the stepped knobs skipped and then felt touchy (a3e097c .. 5556bb0); the DIST values now show while turned (2c4fd66). Odd DIST values on a "new" kit were leftover data from another firmware's kit store on the unit; a new project or a cleared kit gives the defaults |
| 12-13 | full `4ea405a0...` (524920b) | chord sounds survive the pool, a load and a paste; two held chord tracks keep the UI responsive, a third slows it (the documented limit). Before 524920b idle chord tracks used CPU too: two made the encoders sluggish, and one paste to a third track froze the unit once (not reproduced since). Chorus with its HPF swept by sine, square and random LFOs at full depth: edge clicks only, no bursts |
| 14 | stock 1.56 by Transfer | returns to stock; projects load |

The HARD build (`7b8eab9d...`, the full build with HARD distortion only) was not
flashed. Earlier silence after a pool load or a paste (step 12, first try) did not
reproduce on the unit or in the emulator.
