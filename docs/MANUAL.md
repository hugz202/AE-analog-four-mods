# Manual - Analog Four / Analog Keys MK1 mods (OS 1.56)

What each mod does on the instrument. Which mods are in your firmware depends on how
it was built (BUILD.md); `make full` and `make hard` have all of them.

## 0001 Scale lock

Restricts a track's notes to a key and scale, Digitone II style.

### Setting it

Open the track's NOTE SETUP menu (where TRK QUANTIZE, KEY NOTE and TRANSPOSABLE are)
and set:

- **KEY NOTE**: the root, C..B (stock setting, unchanged).
- **KEY SCALE**: OFF, or one of 35 scales:

  | value | scale | value | scale | value | scale |
  |---|---|---|---|---|---|
  | MAJ | Ionian (major) | BLUE | Blues | PHYD | Phrygian dominant |
  | MIN | Aeolian (minor) | COMB | Combo minor | WHDI | Whole-half dim. |
  | DOR | Dorian | PERS | Persian | HWDI | Half-whole dim. |
  | PHRY | Phrygian | IWAT | Iwato | SPAN | Spanish |
  | LYD | Lydian | INSN | In-Sen | MAJL | Major Locrian |
  | MIXO | Mixolydian | HIRJ | Hirajoshi | SPRL | Super Locrian |
  | LOCR | Locrian | PELG | Pelog | DOR2 | Dorian b2 |
  | PNMI | Pentatonic minor | MLMI | Melodic minor | LYAU | Lydian augmented |
  | PNMA | Pentatonic major | HRMI | Harmonic minor | LYDO | Lydian dominant |
  | WHTN | Whole tone | DBLH | Double harmonic major | LY26 | Lydian #2 #6 |
  | ULTR | Ultraphrygian | HUNG | Hungarian minor | ORIE | Oriental |
  | IO25 | Ionian #2 #5 | LO37 | Locrian bb3 bb7 | | |

Like the rest of NOTE SETUP, the setting belongs to the pattern's track and is saved
with the pattern.

### What it does

With KEY SCALE anything but OFF, on that track:

- **Playing** (trig keys in KEYBOARD mode, and everything that records what you play:
  live recording, hold a trig + play a key): every note snaps to the nearest in-scale
  note - the note itself if it is in the scale, else one or two semitones down or up
  (down first). Out-of-scale keys therefore repeat a neighbour.
- **NOTE encoder on the TRIG page** - the track's note, and the note of any trigs
  you hold: each click moves to the next in-scale note up or down. A note already
  out of the scale moves to the next in-scale note in the direction you turn.
- **Transposition** keeps following the key: the new scales transpose like MAJ.

MAJ and MIN restrict notes too (on stock they only steer transposition), so a
pattern that used MAJ or MIN on stock now has its notes snapped as you play. A
pattern saved with one of the new scales and opened on stock 1.56 reads KEY SCALE
OFF.

### Limits

- Notes already in a pattern are not rewritten when you change the scale; they snap
  only when you next turn the NOTE encoder over them.
- The lock follows the **active** track: notes reach it the way they reach the track
  you are playing. Notes arriving over MIDI for a different track's channel are not
  covered, and external MIDI notes have not been tested.

## The DIST page (0006 + 0007 + 0008)

On a synth track, press **AMP** once for the AMP page and **again** for **DIST**;
press it again to go back to AMP.

| knob | setting | values |
|---|---|---|
| 1 | DIG | switch: off = analog path, on = digital path |
| 2 | CHR | 3 positions: HARD (left), RAT (middle), OD (right) |
| 3 | DRV | drive into the clipper, 0 = clean |
| 4 | BIT | bit reduction, 0 = off |
| 5 | SRR | sample-rate reduction, 0 = off |
| 6 | LEV | level of the digital path, ~100 = level with the analog path |
| 7 | SLD | switch: off = stock slide, on = 303 slide (needs 0002) |

In the **HARD-only build** (`make hard`) there is no CHR knob: the page closes up to
DIG DRV BIT SRR LEV / SLD, and the drive is always HARD (it sounds exactly like HARD
in the full build). That build leaves more room and costs less CPU per digital
track.

The settings are per track and belong to the **kit**: they are saved with it and
survive a power cycle. Kits saved this way still load on the stock OS, which just
ignores the extra settings. There are no p-locks on this page: holding a trig and
turning a knob there does nothing.

### Digital path and distortion (0007)

The A4 digitises every voice to feed its effects. With **DIG** on, the track's analog
dry sound is muted and that digitised copy is processed instead:
low-cut -> DRV -> BIT -> SRR, then out to the main outputs at LEV (centred, a couple
of milliseconds behind the analog tracks) **and** into the effect sends, so the
delay, reverb and chorus hear the distorted sound.

- **Low-cut**: always on, a fixed 12 dB/oct high-pass ahead of the drive, so the low
  end of a bass or acid line doesn't swamp the distortion: -6 dB at 75 Hz, -3 dB at
  about 110 Hz, -16 dB at C1. It is roughly filter 2 in HP2 at FRQ 32, RES 0. It
  applies at DRV 0 too, so a clean DIG track is a little thinner in the bass than the
  analog path.

- **CHR** (full build only) picks the drive's character:
  - **HARD**: a plain digital clipper (Machinedrum / Monomachine style).
  - **RAT**: ProCo RAT style - a mild treble lift, a low-pass that darkens as DRV
    rises (the RAT's op-amp losing bandwidth at high gain), hard clipping, then a
    4 kHz tone filter.
  - **OD**: Tube Screamer style - a mid hump around 720 Hz, soft clipping, then a
    darker 2.5 kHz tone filter. It adds a little warmth even at DRV 0.
- **DRV** is gain into the clipper: 0 = clean, +6 dB every 16 steps, up to +48 dB.
  The first ~9.5 dB is taken back off after the clipper, so more DRV means more grit
  at about the same level.
- **BIT** 0 = off; 1..127 = from 13 bits down to 2, rounded (no DC offset, no level
  jump).
- **SRR** holds each sample for 1 + SRR/4 samples (0 = off).
- **LEV** only trims the digital track against the analog ones: about 100 matches
  the same sound on the analog path, 127 is about +2 dB above that.
- The effect sends follow **LEV**, as the dry output does: once LEV puts the digital
  track level with the clean sound, its delay, reverb and chorus sends are level with
  it too (at DRV 0 and LEV 100 they match the analog path's).

The AMP page's own VOL still sets how hard the voice hits the digital path, so it
works as an input gain.

### 303 slide (0002)

With **SLD** on (or on every synth track, in a slide build without the DIST page -
`make slide`), a track slides the 303 way:

- Put the slide trig on the note you glide **from**. That note is held until the
  next trig (plus a quarter step), and the next note glides into it **legato** - no
  envelope retrigger - at the sound's slide time (SLI). No LEN tweaking needed.
- A slide trig with no other trig on the track does nothing.
- Notes already holding a long LEN keep it unless they carry a slide trig.

With SLD off the track has the stock A4 slide ("slide to": the slide trig goes on
the note you glide *into*, and the notes must overlap for it to be legato). A
pattern written for one style sounds odd in the other - check SLD if slides behave
strangely.

## 0010 Digital wave / chord oscillator

On a synth track, press **OSC1** twice for the **NOISE** page. Its 4th knob is a
3-position dial, labelled with its setting: **OFF** (the stock noise), **WAV** (a
digital oscillator) or **CHD** (a chord of that oscillator). The oscillator plays
instead of the noise, at **OSC1's pitch** (note, TUN, FIN, bend, slide, vibrato and
LFOs on OSC1's pitch all follow), and goes through the voice's analog filters and VCA
as the noise does. With WAV or CHD on, the page is relabelled:

| NOISE knob | OFF | WAV | CHD |
|---|---|---|---|
| 1 | SNH | SHP: the wave: 0 sine, 42 triangle, 85 saw, 127 square, morphing in between | SHP |
| 2 | COL | FLD: wavefolder, 0 = clean, 127 = about 7x into the fold | **the chord**, labelled with its name (see below) |
| 3 | FAD | FM: FM depth: a sine at **OSC2's pitch** modulates the wave; 0 = none, 127 = deep (about two cycles of phase) | FM |
| 4 | OFF | WAV | CHD (the mode) |
| 5 | LEV | LEV: level; 0 = silent, so turn it up | LEV |
| 6 | --- | --- | **FLD**: the chord's wavefolder, 0 = clean, 127 = about 7x |

### Chords

In CHD, knob 2 picks the chord: its range is split into 13 zones of about 10 values
(0-9 OCT, 10-19 5TH, 20-29 MAJ, 30-39 MIN, 40-49 SU2, 50-59 SU4, 60-68 MA7, 69-78
MI7, 79-88 DO7, 89-98 MI9, 99-108 HDX, 109-118 SW1, 119-127 SW2). It is the stock
noise COL parameter underneath, so the chord can be **p-locked** (grid record, hold a
trig, turn knob 2: the label shows the locked chord), moved by an **LFO** (it steps
through the chords) or set by a **scene**. On a long release the chord can fall back
to the knob's chord during the tail, when the A4 gives the voice back its unlocked
value.

| name | notes (semitones above OSC1's note) |
|---|---|
| OCT | 0 12 |
| 5TH | 0 7 12 |
| MAJ / MIN | 0 4 7 / 0 3 7 |
| SU2 / SU4 | 0 2 7 / 0 5 7 |
| MA7 / MI7 / DO7 | 0 4 7 11 / 0 3 7 10 / 0 4 7 10 |
| MI9 | 0 3 10 14 |
| HDX | 0 4 10 15 - the "Hendrix" 7#9 |
| SW1 | supersaw: four copies at -12 -4 +4 +12 cents |
| SW2 | wide supersaw: four copies at -25 -8 +8 +25 cents |

Every note plays the same wave (SHP), shares the FM, and the chord is folded as one
signal (FLD). The notes are mixed at 1/n each, so chords sit a little quieter than a
single wave: raise LEV to taste. SW1 and SW2 follow SHP like the chords: at saw they
are the classic supersaw, elsewhere a super-square, super-sine and so on. When the
oscillator restarts (osc retrig), the supersaws' copies start spread through their
cycle, so there is no flanging swirl at the start of the note.

### Good to know

- **The mode and CHD's FLD are saved in the sound**, not the kit (in two parameter
  words the stock OS leaves unused): they follow the sound into kits, the sound pool
  and copies. Sounds made on the stock OS load with it OFF. Neither can be p-locked:
  holding a trig and turning knob 4 or 6 does nothing.
- SHP, COL (FLD in WAV, the chord in CHD), FM and LEV are the stock noise
  parameters, so p-locks, LFOs and saved sounds work on them; OFF gives the noise
  back with the same knob positions.
- Sounds saved in CHD with an earlier version of this mod (where knob 6 was the
  chord) come back with a different chord and no fold: set both again and save.
- FM: OSC2's TUN / FIN set the modulator's pitch (OSC2's LEV can stay at 0: only its
  pitch is used). With WAV / CHD on, the wave is never faded: FAD only sets the FM
  depth. A sound's FAD is usually 64, so FM starts at half depth when you first turn
  the oscillator on.
- The filter page's overdrive does not drive it: the noise path, which the
  oscillator uses, joins the voice where the overdrive doesn't reach (the stock noise
  behaves the same way).
- Osc retrig restarts the wave too.
- The sine is pure (harmonics at -83 dB). Saw and square are not band-limited, so
  they alias on high notes. Folding a square only changes its level (it is flat):
  use the folder on sine and triangle.
- CPU, per track playing it: WAV about 1-2 % of the audio budget, a 3-note chord
  2-3 %, a 4-note chord or supersaw 3-6 % (sine and a high FLD cost the most). A
  track whose noise LEV is 0 costs almost nothing: the oscillator is skipped while
  silent. Several chord tracks together with the digital path run fine, but four
  heavy chord tracks on top of a busy kit can reach the limit.

## 0012 Resonance limit

**FUNC + OSC1** (SOUND SETUP) has a new checkbox under F1 RESONANCE BOOST: **RESONANCE
LIMIT**. Tick it (YES, or turn the encoder) and that sound's filter resonances are
scaled down so they can be swept without self-oscillating: F1 RES 0..127 plays as
0..80, F2 RES as 0..64. The whole knob travel stays usable, and the scaling applies
after the knob, p-locks, LFOs and envelopes are combined, so nothing pushes past the
ceiling. It is saved with the sound and follows it through kits, the sound pool and
copies.

## 0011 Random track

Hold a **track key** and press **YES**: that track is cleared and filled with a random
line over its length (the pattern's, or the track's own in per-track mode):

- trigs on about 62 % of the steps, the first step always;
- each with a note in **KEY NOTE + KEY SCALE** (NOTE SETUP; pentatonic minor when KEY
  SCALE is OFF), around the track's default note: mostly the root, some octaves and
  fifths, the rest any scale note from an octave below to just under an octave above;
- about a quarter of the trigs accented and a sixth slid (with the 303 slide on, a
  slide glides from that note into the next).

Press YES again (track key held) for another line. Hold the track key and press
**LEFT** to undo: the track comes back exactly as it was before the last random line,
p-locks included. The pop-up says RANDOM TRACK / RANDOM UNDONE. The FX track is left
alone; the CV track works like the synth tracks. TRACK + UP / DOWN are still stock's
transpose.

## First-flash checklist

1. It boots and plays a pattern normally.
2. NOTE SETUP: KEY SCALE scrolls OFF, MAJ, MIN, DOR ... LO37 and shows each name.
3. KEY NOTE = C, KEY SCALE = MAJ, KEYBOARD mode: black-key trig keys repeat a
   neighbouring white note; with OFF they play chromatically again.
4. TRIG page NOTE encoder steps C D E F G A B C for MAJ.
5. AMP twice shows DIST with DIG CHR DRV BIT SRR / LEV SLD (`make hard`: DIG DRV
   BIT SRR LEV / SLD); AMP again goes back.
6. DIG on a track: same sound, now through the digital path; DRV/CHR change it.
7. Save the kit, power-cycle, reload: the DIST settings are kept.
8. OSC1 twice shows NOISE with SNH COL FAD OFF LEV. Knob 4 to WAV: SHP FLD FM WAV
   LEV, and with NOISE LEV up (OSC1 / OSC2 LEV at 0) a pitched tone that follows
   notes, TUN and bend. SHP sweeps sine -> triangle -> saw -> square.
9. Knob 4 to CHD: knob 2 names the chord (OCT ... SW2) as it turns and the chord
   plays; knob 6 is FLD and folds it. Grid record, hold a trig, turn knob 2: the
   label shows the locked chord, and in playback that step plays it.
10. Save the sound to the pool and load it on another track: the oscillator setting
    (and CHD's FLD) comes with it. A sound from before the mods loads with it OFF.
11. FUNC + OSC1: RESONANCE LIMIT under F1 RESONANCE BOOST. A sound that
    self-oscillates at RES 127: tick it and it stops short; untick, it screams again.
12. Track key + YES: a random line in the key and scale; track key + LEFT: the track
    as it was.
