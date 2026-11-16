        | Mod 0010 - digital wave / chord oscillator in the noise path. See mod.toml.
        |
        | The noise generator (0x400f9912, audio interrupt, 32 samples a block)
        | builds three filtered noises per voice and crossfades them by COL into
        | the voice's noise DAC buffer, scaled by the noise level and its fade
        | envelope. For each voice whose sound has WAV or CHD on:
        |   - fad_gate (after the fade envelopes are updated, before the
        |     levels are taken from them, 0x400f9c00) sets the voice's envelope
        |     to full, so the wave is never faded and FAD is free to be the FM
        |     depth (the engine writes the FAD word only when it changes, so it
        |     is read, never overwritten), and notes the voice's mode;
        |   - wave_gate (the start of the final mix, 0x400f9c4c) overwrites
        |     all three sources with the oscillator, so the stock mix applies
        |     LEV to it unchanged (COL's crossfade weights sum to 1). A voice
        |     whose level is 0 in this block and the last is skipped.
        |
        | The mode is stored in the sound: its unused parameter word 103 =
        | 0x57xx, xx = mode (0 off, 1 WAV, 2 CHD; bit 7 0012's); any other
        | value is off (sounds converted from older OSes can carry leftovers
        | there). The track's live sound is in the 338-byte storage format at
        | S - 1352 + 338 t (S = the kit FX pointer 0006/0007 use), the word at
        | +226; banked sounds are 350-byte records with it at +234. Loading a
        | sound or kit copies 338 -> 350 with a block copy that carries it; the
        | reverse (0x40008530) copies field by field, so conv_gate carries it
        | there. The NOISE page's WAV and CHD knobs set it (0007's knob gates).
        | CHD (2026-10-26): the chord is the COL knob's live value (13 zones over
        | 0..127, so it p-locks and follows LFOs), the fold the sound's word 102
        | = 0x46xx (unused by the OS: the engine's index table sends words 101
        | and up to one dump slot, and no page writes it; emulator watch,
        | 2026-10-26), carried with word 103.
        |
        |   pitch  OSC1's NCO word for the voice (0x80005f6c + 8v, written by
        |          the FX block: note, tune, bend, slide, vibrato, LFOs, all in),
        |          a 32-bit increment at 24.576 MHz, so << 9 at 48 kHz. Its bit
        |          31 (the oscillator retrig) restarts our cycles too.
        |   SHP    the S&H knob (its modulated 8.8 word, 0x80005360 + 2v):
        |          0 sine, 42 triangle, 85 saw, 127 square, crossfaded between
        |   FLD    the COL knob (0x800050e8 + 2v), in CHD word 102 (VFOLD): a
        |          triangle wavefolder, gain 1 (0, clean) to about 7 (127)
        |   FM     the FAD knob (0x80005358 + 2v): phase modulation by a sine at
        |          OSC2's pitch (0x80005f70 + 8v), depth^2 scaled, up to about
        |          two cycles (index ~12.6) at 127; 0 = none
        |   CHD    a chord of 2..4 notes of the same wave over OSC1's pitch (one
        |          phase each, the same FM offset), summed and scaled by 1/n
        |          before the folder. WAV is the one-note chord.
        |
        | The sines are a 5th-order polynomial of the triangle (harmonics at -83
        | dB). All four waves are odd about phase 0 (the triangle is taken a
        | quarter turn on), so every blend, folded or not, has no DC. Output
        | peaks at 0.75 of full scale. Not band-limited: saw, square, the folds
        | and deep FM alias at the top.
        |
        | The oscillator runs from the chorus gap (section .gap, cave3); the
        | gates the stock code jumps to stay in `cave`. cho_gate keeps the
        | chorus's signed table index >= 0, so no index can reach the gap.
        |
        | Calls follow the stock ABI: d0/d1/a0/a1 are scratch, the rest is saved.

        .include "symbols.inc"

        .equ    SND_SIZE,     338                 | the live sounds, from S:
        .equ    SND0_FROM_S,  1352                | S - 1352 + 338 t
        .equ    SND_WAV,      226                 | parameter word 103
        .equ    WAV_SIG,      0x57                | its high byte when set
        .equ    FOLD_SIG,     0x46                | word 102's (CHD's FLD), 0x46xx
        .equ    BANK_WAV,     SND_WAV + 8         | in the 350-byte records
        .equ    NCHORDS,      13
        .equ    SW_FIRST,     11                  | the first supersaw type
        .equ    OSC1_NCO,     0x80005f6c          | + 8v: OSC1's NCO word (+4: OSC2)
        .equ    NOISE_FAD,    0x80005358          | + 2v: the fade word -> FM
        .equ    NOISE_SNH,    0x80005360          | + 2v: the S&H word -> SHP
        .equ    NOISE_COL,    0x800050e8          | + 2v: the colour word -> FLD
        .equ    NOISE_LEV,    0x800050e0          | + 2v: the level word (modulated)
        .equ    FADE_ENV,     0x80001be8          | + 4v: the fade envelopes
        .equ    VOICE_TRACK,  0x80005530          | + 4v: the voice's track
        .equ    BUF0,         0x80001d78          | + 140v: the mix's three sources,
        .equ    BUF1,         0x80001fa8          | 32 longs each after a 12-byte
        .equ    BUF2,         0x800021d8          | filter history
        .equ    VSTRIDE,      140
        .equ    FRAMES,       32
        .equ    S1,           25728               | sin(pi/2 x) ~ x (S1 + x^2 (S3 +
        .equ    S3,           -10520              | x^2 S5)), Q14, x the triangle
        .equ    S5,           1177
        | State in free DDR, in the gap below 0007's buffers (any start value
        | is valid; WMASK and VMODE are written before they are read in every
        | block). That DDR is not cached (ACR0 covers only 0x40000000 ..
        | 0x43ffffff), so every access is a bus round trip: it is touched only
        | once a block, and voice() works in a frame on the (cached) stack.
        .equ    PMPH,         0x46803010          | 4 longs: the modulators' phases
        .equ    WMASK,        0x46803028          | byte: bit v = voice v is on
        .equ    SILENT,       0x46803029          | byte: bit v = v's level was 0
                                                  | last block
        .equ    VMODE,        0x4680302c          | 4 bytes: the voices' mode bytes
        .equ    VFOLD,        0x46803030          | 4 bytes: CHD voices' FLD (word 102)
        .equ    NPH,          0x46803080          | 4 x 4 longs: the notes' phases
                                                  | voice()'s frame (a6, on the
        .equ    P_GAIN,       0                   | stack): fold gain, 0 = none
        .equ    P_K,          4                   | FM depth
        .equ    P_MSTEP,      8                   | the modulator's step
        .equ    P_SUM,        12                  | the notes' sum (per sample)
        .equ    P_MOFF,       16                  | the FM offset (per sample)
        .equ    P_SCALE,      20                  | 1/n, Q15
        .equ    P_NBASE,      24                  | &P_PH
        .equ    P_N,          28                  | n
        .equ    P_STEPS,      32                  | the notes' steps, 4 longs
        .equ    P_PH,         48                  | the notes' phases (NPH[v])
        .equ    P_V,          64                  | the saved d6 (v), d7
        .equ    P_SIZE,       72

        .text

        | ------------------------------------------------------------------
        | The final noise mix, at `lea 0x800050e8,%a1` (its first instruction;
        | nothing is live in registers here, the mix loads all it needs).
        | ------------------------------------------------------------------
        .align  2
wave_gate:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        mvz.b   WMASK,%d7                         | from fad_gate, this block
        mvz.b   SILENT,%d5
        moveq   #0,%d6                            | voice
1:      btst    %d6,%d7
        beq.s   2f
        move.l  %d6,%d0                           | level 0 now and in the last
        add.l   %d0,%d0                           | block: the mix's gain is 0
        lea     NOISE_LEV,%a0                     | all through, so skip it
        tst.w   (%a0,%d0.l)
        bne.s   3f
        btst    %d6,%d5
        bset    %d6,%d5
        bne.s   2f
        bra.s   4f
3:      bclr    %d6,%d5
4:      move.l  %d5,-(%sp)
        jsr     voice                             | (in the chorus gap)
        move.l  (%sp)+,%d5
2:      addq.l  #1,%d6
        moveq   #4,%d0
        cmp.l   %d0,%d6
        bne.s   1b
        move.b  %d5,SILENT
        movem.l (%sp),%d2-%d7/%a2-%a6
        lea     44(%sp),%sp
        lea     NOISE_COL,%a1                     | displaced
        jmp     noise_mix_resume

        | ------------------------------------------------------------------
        | The sound converter 0x40008530 (dst, src): a 350-byte record (bank,
        | pool) into the 338-byte storage format (the live kit), field by
        | field, which skips words 102..103. At its entry: carry them across.
        | ------------------------------------------------------------------
        .align  2
conv_gate:
        movem.l 4(%sp),%a0-%a1                    | dst, src
        move.l  %a0,%d0
        beq.s   1f
        move.l  %a1,%d0
        beq.s   1f
        moveq   #6,%d0                            | v6 records only: in older
        cmp.l   4(%a1),%d0                        | ones (5) these bytes are
        bne.s   1f                                | something else, and stock
        move.l  BANK_WAV-2(%a1),SND_WAV-2(%a0)    | rejects them here anyway
                                                  | (words 102 and 103: CHD's FLD
                                                  | and the mode)
1:      lea     -28(%sp),%sp                      | displaced
        movem.l %d2-%d3/%a2-%a6,(%sp)             | displaced
        jmp     sound_conv_body

        | ==================================================================
        | In the chorus gap
        | ==================================================================
        .section .gap,"ax"

        | ------------------------------------------------------------------
        | After the fade envelopes are updated, before the levels are taken
        | from them (`lea 0x80001be8,%a0`, re-emitted): find the voices whose
        | sound has WAV or CHD on (WMASK, their mode bytes in VMODE) and set
        | their envelopes to full.
        | ------------------------------------------------------------------

        | ------------------------------------------------------------------
        | The chorus's index load `mvsb 0x8000517e,%d0` (HPF's modulated
        | value, signed bytes x 4 into tables 0x401ee978 and down): kept >= 0.
        | The engine clamps it to 0..127 already (emulator: LFO1 at full
        | depth on HPF, 2026-10-15); this makes the gap unreachable by
        | construction.
        | ------------------------------------------------------------------
        .align  2
cho_gate:
        mvs.b   0x8000517e,%d0                    | displaced
        bpl.s   1f
        moveq   #0,%d0
1:      jmp     cho_index_resume

        | c127(d0) -> d0 clamped to 0..127.
        .align  2
c127:
        tst.l   %d0
        bpl.s   1f
        moveq   #0,%d0
1:      moveq   #127,%d1
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
2:      rts

        | knob(a0 = an 8.8 word array, d4 = 2v) -> d0 = 0..127.
        .align  2
knob:
        mvs.w   (%a0,%d4.l),%d0
        asr.l   #8,%d0
        bra.s   c127

        | ------------------------------------------------------------------
        | voice(d6 = v): one block of the oscillator into v's three sources.
        | d6 and d7 kept.
        |
        | Per block: the chord's notes and their steps (OSC1's step x 2^(s /
        | 12)); SHP x 387 = segment << 14 | f, and the segment's snippet (a4)
        | for wave(). Per sample: the FM offset, then each note's wave at its
        | phase + the offset, summed, x 1/n, then the folder (FLD 0 skips it:
        | gain 1 is the identity on -1..1). Output = 0.75 of full scale.
        | ------------------------------------------------------------------
        .align  2
voice:
        lea     -P_SIZE(%sp),%sp
        movem.l %d6-%d7,P_V(%sp)
        move.l  %sp,%a6
        move.l  %d6,%d0
        lsl.l   #3,%d0
        lea     OSC1_NCO,%a0
        move.l  4(%a0,%d0.l),%d2                  | OSC2's NCO word: the modulator
        move.l  (%a0,%d0.l),%d3                   | OSC1's; bit 31: retrig
        lea     P_PH(%a6),%a1
        move.l  %a1,P_NBASE(%a6)                  | a1 = the phases, in the frame
        move.l  %d6,%d0
        lsl.l   #4,%d0
        addi.l  #NPH,%d0
        move.l  %d0,%a0                           | from NPH[v]
        tst.l   %d3
        bpl.s   1f
        moveq   #0,%d0                            | retrig: every cycle restarts
        lea     PMPH,%a0
        move.l  %d6,%d1
        lsl.l   #2,%d1
        move.l  %d0,(%a0,%d1.l)
        move.l  %d0,%d1                           | the notes at 0; a supersaw's
        mvz.b   VMODE-PMPH(%a0,%d6.l),%d4         | spread by golden-ratio turns,
                                                  | so they don't start in phase
        moveq   #SW_FIRST << 2,%d5
        cmp.l   %d5,%d4
        bcs.s   13f
        move.l  #0x9e3779b9,%d1
13:     move.l  %d0,(%a1)+
        add.l   %d1,%d0
        move.l  %d0,(%a1)+
        add.l   %d1,%d0
        move.l  %d0,(%a1)+
        add.l   %d1,%d0
        move.l  %d0,(%a1)
        bra.s   12f
1:      move.l  (%a0)+,(%a1)+
        move.l  (%a0)+,(%a1)+
        move.l  (%a0)+,(%a1)+
        move.l  (%a0),(%a1)
12:     moveq   #9,%d0
        andi.l  #0x3fffff,%d3
        lsl.l   %d0,%d3                           | OSC1's step at 48 kHz
        andi.l  #0x3fffff,%d2
        lsl.l   %d0,%d2
        move.l  %d2,P_MSTEP(%a6)                  | the modulator's

        lea     VMODE,%a0                         | the chord: WAV = one note
        mvz.b   (%a0,%d6.l),%d0
        lea     chords,%a0                        | (CHD 1st entry: one note)
        btst    #1,%d0
        beq.s   2f
        lsr.l   #2,%d0                            | the chord type
        moveq   #NCHORDS-1,%d1
        cmp.l   %d1,%d0
        bls.s   3f
        move.l  %d1,%d0
3:      addq.l  #1,%d0
        lsl.l   #2,%d0
        add.l   %d0,%a0
2:      lea     P_STEPS(%a6),%a2
        moveq   #0,%d5                            | n
5:      mvz.b   (%a0)+,%d0                        | a ratio's index; 0xff ends
        cmpi.l  #0xff,%d0
        beq.s   6f
        lea     ratios,%a3                        | step x the ratio, Q14:
        add.l   %d0,%d0
        mvz.w   (%a3,%d0.l),%d1                   | (hi x r) << 2 + (lo x r) >> 14
        move.l  %d3,%d0
        swap    %d0
        mulu.w  %d1,%d0
        lsl.l   #2,%d0
        move.l  %d3,%d2
        mulu.w  %d1,%d2                           | (mulu.w takes the low word)
        moveq   #14,%d1
        lsr.l   %d1,%d2
        add.l   %d2,%d0
        move.l  %d0,(%a2)+
        addq.l  #1,%d5
        moveq   #4,%d0
        cmp.l   %d0,%d5
        bne.s   5b
6:      move.l  %d5,P_N(%a6)
        lea     scales-2,%a0
        add.l   %d5,%d5
        mvz.w   (%a0,%d5.l),%d0
        move.l  %d0,P_SCALE(%a6)

        move.l  %d6,%d4                           | the knobs, 8.8 -> 0..127
        add.l   %d4,%d4
        lea     NOISE_FAD,%a0
        bsr.w   knob                              | FM: K = depth^2 x 16
        mulu.w  %d0,%d0
        lsl.l   #4,%d0
        move.l  %d0,P_K(%a6)
        lea     VMODE,%a0                         | FLD: WAV the COL knob, CHD
        mvz.b   (%a0,%d6.l),%d0                   | the sound's (VFOLD); 0..127
        btst    #1,%d0
        beq.s   7f
        lea     VFOLD,%a0
        mvz.b   (%a0,%d6.l),%d0
        bra.s   8f
7:      lea     NOISE_COL,%a0
        bsr.w   knob
8:                                                | gain (8.8):
        mulu.w  #12,%d0                           | 1 + FLD x 12 / 256,
        beq.s   2f                                | 0 = no folder
        addi.l  #256,%d0
2:      move.l  %d0,P_GAIN(%a6)
        lea     NOISE_SNH,%a0
        bsr.w   knob                              | SHP
        mulu.w  #387,%d0
        move.l  %d0,%d6
        andi.l  #0x3fff,%d6                       | f, Q14
        moveq   #14,%d4
        lsr.l   %d4,%d0                           | segment 0..2
        lea     snippets,%a4
        move.l  (%a4,%d0.l*4),%a4

        move.l  P_V(%a6),%d0                      | v
        lea     PMPH,%a0
        lsl.l   #2,%d0
        move.l  (%a0,%d0.l),%a0                   | a0 = the modulator's phase
        move.l  P_V(%a6),%d0
        mulu.w  #VSTRIDE,%d0
        addi.l  #BUF0,%d0
        move.l  %d0,%a3
        lea     FRAMES*4(%a3),%a5                 | the end
        moveq   #15,%d7
        move.l  P_NBASE(%a6),%a1                  | one note: its phase and step
        move.l  (%a1),%d5                         | in registers for the block
        move.l  P_STEPS(%a6),%a2

7:      moveq   #0,%d1                            | the FM offset
        tst.l   P_K(%a6)
        beq.s   8f
        adda.l  P_MSTEP(%a6),%a0
        move.l  %a0,%d1
        bsr.w   sine
        muls.l  P_K(%a6),%d1                      | x K (mod 2^32: the phase wraps)
8:      moveq   #1,%d0                            | one note (WAV): no sum, no
        cmp.l   P_N(%a6),%d0                      | 1/n
        bne.s   10f
        add.l   %a2,%d5
        move.l  %d5,%d3
        add.l   %d1,%d3
        bsr.w   wave                              | m, Q15
        bra.s   11f
10:     move.l  %d1,P_MOFF(%a6)
        clr.l   P_SUM(%a6)
        move.l  P_NBASE(%a6),%a1
        lea     P_STEPS(%a6),%a2
        move.l  P_N(%a6),%d5
9:      move.l  (%a1),%d3                         | each note: its phase
        add.l   (%a2)+,%d3
        move.l  %d3,(%a1)+
        add.l   P_MOFF(%a6),%d3
        bsr.w   wave
        add.l   %d0,P_SUM(%a6)
        subq.l  #1,%d5
        bne.s   9b
        move.l  P_SUM(%a6),%d0                    | x 1/n
        muls.l  P_SCALE(%a6),%d0
        asr.l   %d7,%d0                           | m, Q15
11:     tst.l   P_GAIN(%a6)
        beq.s   6f
        muls.l  P_GAIN(%a6),%d0                   | v = m x gain, 1.0 = 2^23
        addi.l  #0x00800000,%d0                   | fold: 1 - |((v + 1) mod 4) - 2|
        andi.l  #0x01ffffff,%d0
        subi.l  #0x01000000,%d0
        bpl.s   5f
        neg.l   %d0
5:      move.l  #0x00800000,%d1
        sub.l   %d0,%d1
        move.l  %d1,%d0
        bra.s   4f
6:      lsl.l   #8,%d0                            | (no folder) 1.0 = 2^23
4:      move.l  %d0,%d1                           | x 192: 0.75 of full scale
        lsl.l   #7,%d0
        lsl.l   #6,%d1
        add.l   %d1,%d0
        move.l  %d0,(%a3)
        move.l  %d0,BUF1-BUF0(%a3)
        move.l  %d0,BUF2-BUF0(%a3)
        addq.l  #4,%a3
        cmpa.l  %a5,%a3
        bne.w   7b
        moveq   #1,%d0
        cmp.l   P_N(%a6),%d0
        bne.s   1f
        move.l  %d5,P_PH(%a6)                     | (one note: its phase back)
1:      move.l  P_V(%a6),%d0                      | the modulator's phase back
        lsl.l   #2,%d0
        lea     PMPH,%a1
        move.l  %a0,(%a1,%d0.l)
        move.l  P_V(%a6),%d0                      | the phases back to NPH[v]
        lsl.l   #4,%d0
        addi.l  #NPH,%d0
        move.l  %d0,%a1
        lea     P_PH(%a6),%a0
        move.l  (%a0)+,(%a1)+
        move.l  (%a0)+,(%a1)+
        move.l  (%a0)+,(%a1)+
        move.l  (%a0),(%a1)
        movem.l P_V(%sp),%d6-%d7
        lea     P_SIZE(%sp),%sp
        rts

        | wave(d3 = the phase) -> d0 = the morphed wave, Q15: the saw (d0)
        | and the triangle (d1), then the segment's snippet (a4) picks the
        | pair a (d1), b (d0): sine -> tri, tri -> saw, saw -> square; then
        | m = a + (b - a) f. d1-d3 used.
        .align  2
wave:
        move.l  %d3,%d0
        swap    %d0
        ext.l   %d0                               | saw, -32768..32767
        move.l  %d3,%d1
        addi.l  #0x40000000,%d1
        swap    %d1
        ext.l   %d1
        bpl.s   1f
        neg.l   %d1
1:      add.l   %d1,%d1
        subi.l  #32768,%d1                        | triangle, in phase with the saw
        jmp     (%a4)
w_sine: move.l  %d1,%d0                           | b = tri
        bsr.s   sine_t                            | a = sine
        bra.s   mix
w_sq:   move.l  %d0,%d1                           | a = saw
        moveq   #31,%d2                           | b = square, +-32767
        asr.l   %d2,%d0
        eori.l  #32767,%d0
mix:    sub.l   %d1,%d0                           | (tri -> saw: a = tri, b = saw)
        muls.l  %d6,%d0
        asr.l   %d4,%d0
        add.l   %d1,%d0
        rts

        | sine(d1 = a phase) -> d1 = its sine, Q15; sine_t(d1 = a triangle,
        | Q15) -> the same from the triangle. d2/d3 used.
        .align  2
sine:
        addi.l  #0x40000000,%d1
        swap    %d1
        ext.l   %d1
        bpl.s   1f
        neg.l   %d1
1:      add.l   %d1,%d1
        subi.l  #32768,%d1
sine_t: move.l  %d1,%d2
        muls.l  %d2,%d2
        asr.l   %d7,%d2                           | tri^2
        move.l  #S5,%d3
        muls.l  %d2,%d3
        asr.l   %d7,%d3
        addi.l  #S3,%d3
        muls.l  %d2,%d3
        asr.l   %d7,%d3
        addi.l  #S1,%d3
        muls.l  %d3,%d1
        asr.l   %d4,%d1
        rts

        | Pitch ratios, Q14 (up to 2.38): the chords' semitones 0, 2, 3, 4, 5, 7, 10, 11, 12, 14, 15
        | (2^(s / 12)), then the supersaws' detunes -12, -4, 4, 12, -25, -8, 8, 25 cents
ratios: .short  16384, 18390, 19484, 20643, 21870, 24548, 29193, 30929, 32768, 36781, 38968
        .short  16271, 16346, 16422, 16498, 16149, 16308, 16460, 16622

        | Chords: up to four indices into `ratios`, 0xff ends. The first is
        | WAV's single note; then CHD's types 0..12 (0007's names). Types from
        | SW_FIRST on are supersaws: their notes start spread on a retrig.
chords: .byte   0, 0xff, 0xff, 0xff   | WAV 0
        .byte   0, 8, 0xff, 0xff      | OCT 0+12
        .byte   0, 5, 8, 0xff         | 5TH 0+7+12
        .byte   0, 3, 5, 0xff         | MAJ 0+4+7
        .byte   0, 2, 5, 0xff         | MIN 0+3+7
        .byte   0, 1, 5, 0xff         | SU2 0+2+7
        .byte   0, 4, 5, 0xff         | SU4 0+5+7
        .byte   0, 3, 5, 7            | MA7 0+4+7+11
        .byte   0, 2, 5, 6            | MI7 0+3+7+10
        .byte   0, 3, 5, 6            | DO7 0+4+7+10
        .byte   0, 2, 6, 9            | MI9 0+3+10+14
        .byte   0, 3, 6, 10           | HDX 0+4+10+15
        .byte   11, 12, 13, 14        | SW1 -12 -4 +4 +12 cents
        .byte   15, 16, 17, 18        | SW2 -25 -8 +8 +25 cents

        | (In `cave`: the chorus gap is full.)
        .text
        .align  2
snippets:
        .long   w_sine, mix, w_sq                 | per segment

        | 1/n, Q15, n = 1..4
scales: .short  32767, 16384, 10923, 8192

        | ==================================================================
        | In cave8 (the shelved inputs build's space)
        | ==================================================================
        .section .wv2,"ax"

        | ------------------------------------------------------------------
        | After the fade envelopes are updated, before the levels are taken
        | from them (`lea 0x80001be8,%a0`, re-emitted): find the voices whose
        | sound has WAV or CHD on (WMASK, their mode bytes in VMODE) and set
        | their envelopes to full. A CHD voice's chord comes from the COL knob
        | (so it locks), its FLD from the sound's word 102 (VFOLD).
        | ------------------------------------------------------------------
        .align  2
fad_gate:
        lea     -16(%sp),%sp
        movem.l %d2-%d4/%a2,(%sp)
        moveq   #0,%d3                            | the mask
        move.l  project_ptr,%d0
        jeq     9f
        move.l  %d0,%a0
        move.l  PROJECT_KIT_FX_STORAGE(%a0),%d0
        jeq     9f
        move.l  %d0,%a2
        lea     SND_WAV-SND0_FROM_S(%a2),%a2      | a2 = track 0's live WAV word
        moveq   #0,%d2                            | voice
1:      lea     VOICE_TRACK,%a0
        move.l  %d2,%d0
        lsl.l   #2,%d0
        move.l  (%a0,%d0.l),%d1
        moveq   #3,%d0
        cmp.l   %d0,%d1
        jhi     2f                                | not on a synth track
        mulu.w  #SND_SIZE,%d1
        move.l  %d1,%d4                           | the sound, from track 0's
        mvz.w   (%a2,%d1.l),%d1                   | its sound's word 103
        move.l  %d1,%d0
        lsr.l   #8,%d0
        cmpi.l  #WAV_SIG,%d0
        jne     2f
        moveq   #3,%d0
        and.l   %d1,%d0                           | mode 1 or 2
        jeq     2f
        subq.l  #3,%d0
        jeq     2f
        bclr    #7,%d1                            | bit 7 is 0012's RES LIMIT
        btst    #1,%d1
        jeq     5f
        lea     NOISE_COL,%a0                     | CHD: the chord is COL's live
        move.l  %d2,%d0                           | value (locks, LFOs, scenes):
        add.l   %d0,%d0                           | 13 zones over 0..127
        mvs.w   (%a0,%d0.l),%d0
        asr.l   #8,%d0
        jsr     c127
        mulu.w  #NCHORDS,%d0
        lsr.l   #7,%d0
        lsl.l   #2,%d0
        addq.l  #2,%d0
        move.l  %d0,%d1                           | the mode byte: chord << 2 | 2
        mvz.w   -2(%a2,%d4.l),%d4                 | and FLD, the sound's word 102
        move.l  %d4,%d0                           | (0x46xx, else 0)
        lsr.l   #8,%d0
        cmpi.l  #FOLD_SIG,%d0
        jeq     6f
        moveq   #0,%d4
6:      moveq   #0x7f,%d0
        and.l   %d0,%d4
        lea     VFOLD,%a0
        move.b  %d4,(%a0,%d2.l)
5:      lea     VMODE,%a0
        move.b  %d1,(%a0,%d2.l)
        bset    %d2,%d3
        move.l  %d2,%d0
        lsl.l   #2,%d0
        lea     FADE_ENV,%a0
        moveq   #-1,%d1
        lsr.l   #2,%d1                            | 0x3fffffff
        move.l  %d1,(%a0,%d0.l)                   | no fade
2:      addq.l  #1,%d2
        moveq   #4,%d0
        cmp.l   %d0,%d2
        jne     1b
9:      move.b  %d3,WMASK
        movem.l (%sp),%d2-%d4/%a2
        lea     16(%sp),%sp
        lea     FADE_ENV,%a0                      | displaced
        jmp     fade_level_resume

