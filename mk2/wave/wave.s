        | SPDX-License-Identifier: MIT
        | wave - AE 0010 (digital wave / chord oscillator) for the Analog Four
        | MKII, OS 1.56, as an elekloader elemod on core-a4 0.2. This file is
        | the audio side; wave.c is the NOISE page's two knobs.
        |
        | The noise generator (audio interrupt, 32 samples a block) builds three
        | filtered noises per voice and crossfades them by COL into the voice's
        | noise DAC buffer, scaled by the noise level and its fade envelope. For
        | each voice whose sound has WAV or CHD on:
        |   - wave_fad (after the fade envelopes are updated, before the
        |     levels are taken from them, 0x400ffe04) sets the voice's envelope
        |     to full, so the wave is never faded and FAD is free to be the FM
        |     depth, and notes the voice's mode;
        |   - wave_mix (the start of the final mix, 0x400ffe50) overwrites all
        |     three sources with the oscillator, so the stock mix applies LEV to
        |     it unchanged (COL's crossfade weights sum to 1). A voice whose VCA
        |     is closed (no note sounding) is not computed: its sources are
        |     cleared instead, so idle tracks cost almost no CPU.
        |
        | The mode is a sound field in core-a4's mod storage (wave.c); the UI
        | tick copies each synth track's into wave_trk (chord type << 2 | mode:
        | 0 off, 1 WAV, 2 CHD), which the audio reads.
        |
        |   pitch  OSC1's NCO word for the voice (0x80006a2c + 8v: note, tune,
        |          bend, slide, vibrato, LFOs, all in), a 32-bit increment at
        |          24.576 MHz, so << 9 at 48 kHz. Its bit 31 (the oscillator
        |          retrig) restarts our cycles too.
        |   SHP    the S&H knob (its modulated 8.8 word, 0x80005e20 + 2v):
        |          0 sine, 42 triangle, 85 saw, 127 square, crossfaded between
        |   FLD    the COL knob (0x80005ba8 + 2v): a triangle wavefolder, gain
        |          1 (COL 0, clean) to about 7 (COL 127)
        |   FM     the FAD knob (0x80005e18 + 2v): phase modulation by a sine at
        |          OSC2's pitch (0x80006a30 + 8v), depth^2 scaled, up to about
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
        | The code is the image port's (MK2-OS-1.56, mods/0010-wave-osc), with
        | its state in this mod's .bss instead of free DDR, and the mode read
        | from wave_trk instead of the sound's word 103.
        |
        | Calls follow the stock ABI: d0/d1/a0/a1 are scratch, the rest is saved.

        | OS 1.56 addresses (re/symbols.toml on the MK2-OS-1.56 branch)
        .equ    noise_mix_resume,  0x400ffe56
        .equ    fade_level_resume, 0x400ffe0a

        .equ    NCHORDS,      13
        .equ    SW_FIRST,     11                  | the first supersaw type
        .equ    OSC1_NCO,     0x80006a2c          | + 8v: OSC1's NCO word (+4: OSC2)
        .equ    NOISE_FAD,    0x80005e18          | + 2v: the fade word -> FM
        .equ    NOISE_SNH,    0x80005e20          | + 2v: the S&H word -> SHP
        .equ    NOISE_COL,    0x80005ba8          | + 2v: the colour word -> FLD
        .equ    VCA,          0x80003d82          | + 26v: the voice's VCA word in
        .equ    VCA_STRIDE,   26                  | the analog control frame,
                                                  | 0x7fff = closed
        .equ    FADE_ENV,     0x80002be8          | + 4v: the fade envelopes
        .equ    VOICE_TRACK,  0x80005ff0          | + 4v: the voice's track
        .equ    BUF0,         0x80002d78          | + 140v: the mix's three sources,
        .equ    BUF1,         0x80002fa8          | 32 longs each after a 12-byte
        .equ    BUF2,         0x800031d8          | filter history
        .equ    VSTRIDE,      140
        .equ    FRAMES,       32
        .equ    S1,           25728               | sin(pi/2 x) ~ x (S1 + x^2 (S3 +
        .equ    S3,           -10520              | x^2 S5)), Q14, x the triangle
        .equ    S5,           1177
        | State in wave_state (.bss; any start value is valid, and WMASK and
        | VMODE are written before they are read in every block):
        .equ    PMPH,         wave_state          | 4 longs: the modulators' phases
        .equ    WMASK,        wave_state+0x18     | byte: bit v = voice v is on
        .equ    VMODE,        wave_state+0x1c     | 4 bytes: the voices' mode bytes
        .equ    NPH,          wave_state+0x70     | 4 x 4 longs: the notes' phases
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
        .globl  wave_mix, wave_fad

        | ------------------------------------------------------------------
        | The final noise mix, at `lea 0x80005ba8,%a1` (its first instruction;
        | nothing is live in registers here, the mix loads all it needs).
        | ------------------------------------------------------------------
        .align  2
wave_mix:
        lea     -44(%sp),%sp
        movem.l %d2-%d7/%a2-%a6,(%sp)
        mvz.b   WMASK,%d7                         | from wave_fad, this block
        moveq   #0,%d6                            | voice
1:      btst    %d6,%d7
        beq.s   2f
        lea     VOICE_TRACK,%a0                   | a track on dist's digital path
        move.l  %d6,%d0                           | has its dry VCA word zeroed
        lsl.l   #2,%d0                            | (DIG mutes the analog dry
        move.l  (%a0,%d0.l),%d0                   | sound), so the word says
        lea     dist_set,%a0                      | nothing there: always compute
        mulu.w  #6,%d0                            | (wave_fad took only voices on
        tst.b   (%a0,%d0.l)                       | tracks 0..3)
        bne.s   3f
        move.l  %d6,%d0                           | its VCA closed: nothing can
        mulu.w  #VCA_STRIDE,%d0                   | be heard, so the sources are
        lea     VCA,%a0                           | cleared instead (a block's
        move.w  (%a0,%d0.l),%d0                   | lag at a note's start is
        cmpi.w  #0x7fff,%d0                       | silent, never stock noise)
        bne.s   3f
        move.l  %d6,%d0
        mulu.w  #VSTRIDE,%d0
        lea     BUF0,%a0
        add.l   %d0,%a0
        moveq   #FRAMES,%d1
4:      clr.l   BUF1-BUF0(%a0)
        clr.l   BUF2-BUF0(%a0)
        clr.l   (%a0)+
        subq.l  #1,%d1
        bne.s   4b
        bra.s   2f
3:      jsr     voice
2:      addq.l  #1,%d6
        moveq   #4,%d0
        cmp.l   %d0,%d6
        bne.s   1b
        movem.l (%sp),%d2-%d7/%a2-%a6
        lea     44(%sp),%sp
        lea     NOISE_COL,%a1                     | displaced
        jmp     noise_mix_resume

        | ------------------------------------------------------------------
        | After the fade envelopes are updated, before the levels are taken
        | from them (`lea 0x80002be8,%a0`, re-emitted): find the voices whose
        | track has WAV or CHD on (WMASK, their mode bytes in VMODE) and set
        | their envelopes to full.
        | ------------------------------------------------------------------
        .align  2
wave_fad:
        lea     -12(%sp),%sp
        movem.l %d2-%d3/%a2,(%sp)
        moveq   #0,%d3                            | the mask
        lea     wave_trk,%a2                      | each synth track's mode byte
        moveq   #0,%d2                            | voice
1:      lea     VOICE_TRACK,%a0
        move.l  %d2,%d0
        lsl.l   #2,%d0
        move.l  (%a0,%d0.l),%d1
        moveq   #3,%d0
        cmp.l   %d0,%d1
        bhi.s   2f                                | not on a synth track
        mvz.b   (%a2,%d1.l),%d1                   | its mode byte
        moveq   #3,%d0
        and.l   %d1,%d0                           | mode 1 or 2
        beq.s   2f
        subq.l  #3,%d0
        beq.s   2f
        lea     VMODE,%a0
        move.b  %d1,(%a0,%d2.l)
        bset    %d2,%d3
        move.l  %d2,%d0
        lsl.l   #2,%d0
        lea     FADE_ENV,%a0
        move.l  #0x3fffffff,%d1
        move.l  %d1,(%a0,%d0.l)                   | no fade
2:      addq.l  #1,%d2
        moveq   #4,%d0
        cmp.l   %d0,%d2
        bne.s   1b
        move.b  %d3,WMASK
        movem.l (%sp),%d2-%d3/%a2
        lea     12(%sp),%sp
        lea     FADE_ENV,%a0                      | displaced
        jmp     fade_level_resume

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
        lea     NOISE_COL,%a0
        bsr.w   knob                              | FLD: gain (8.8)
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

        .align  2
snippets:
        .long   w_sine, mix, w_sq                 | per segment

        | 1/n, Q15, n = 1..4
scales: .short  32767, 16384, 10923, 8192

        | Pitch ratios, Q14 (up to 2.38): the chords' semitones 0, 2, 3, 4, 5, 7, 10, 11, 12, 14, 15
        | (2^(s / 12)), then the supersaws' detunes -12, -4, 4, 12, -25, -8, 8, 25 cents
ratios: .short  16384, 18390, 19484, 20643, 21870, 24548, 29193, 30929, 32768, 36781, 38968
        .short  16271, 16346, 16422, 16498, 16149, 16308, 16460, 16622

        | Chords: up to four indices into `ratios`, 0xff ends. The first is
        | WAV's single note; then CHD's types 0..12 (wave.c's names). Types from
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

        .data
        .globl  wave_trk
        .align  2
wave_trk:   .space  4                             | each synth track's mode byte (wave.c)

        .bss
        .align  2
wave_state: .space  0xb0
