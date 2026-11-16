        | Mod 0007 - digital path: per-track "snatch" + distortion, and the gates
        | that put its settings on 0008's DIST page. See mod.toml.
        |
        | Settings are bytes in the kit's spare FX words (persisted by 0006's
        | copy_gate), at the storage S = *(project + PROJECT_KIT_FX_STORAGE):
        |   S+24              free (0010's WAV moved into the sound)
        |   S+50+t            CHR   drive character for track t
        |   S+26+6t+0..5      DIG DRV BIT SRR LEV SLD for track t (0..3)
        | LEV is stored XOR 64, so a stock kit's 0 reads as 64 (default).
        | SLD (303 slide mode) is read by 0002.
        |
        | Calls follow the stock ABI: d0/d1/a0/a1 are scratch, the rest is saved.

        .include "symbols.inc"
        .include "shared.inc"                     | 0008: shared_view_page, the view drawn

        .equ    TRK_BASE,   26
        .equ    TRK_SIZE,   6
        .equ    F_DIG,      0
        .equ    F_DRV,      1
        .equ    F_BIT,      2
        .equ    F_SRR,      3
        .equ    F_LEV,      4
        .equ    F_SLD,      5
        .equ    FRAMES,     32
        .equ    FRAME_SIZE, 32                    | 8 codec slots of 32 bits
        .equ    FX_STATE4,  0x415c0008            | what fx_block_tail stores
        .equ    CAP,        0x46804000            | captured tracks, 4 x 32 longs,
        .equ    HOLD,       0x4680c200            | and their DSP state: free DDR
                                                  | (unreferenced by stock). Not
                                                  | cached (ACR0 covers only
                                                  | 0x40000000..0x43ffffff), so
                                                  | each access costs a bus round
                                                  | trip: the per-sample loop works
                                                  | on a copy on the stack.
        .equ    PROJECT_FXSETUP, 244 + 0x1030

        .text

        | ==================================================================
        | Audio side (the audio interrupt)
        | ==================================================================

        | ------------------------------------------------------------------
        | track_levels, at `movel %a2@,%d0; macl %d0,%d5,%acc0`: the volume
        | loaded for the analog dry VCA words only (the send gain is already
        | written). d2 = track, d1 dead. A track on the digital path gets a dry
        | volume of 0 - what stock computes for VOL 0 - and keeps its capture.
        | ------------------------------------------------------------------
        .align  2
dry_gate:
        move.l  project_ptr,%d0
        beq.s   1f
        move.l  %d0,%a0
        move.l  PROJECT_KIT_FX_STORAGE(%a0),%d0
        beq.s   1f
        move.l  %d0,%a0
        move.l  %d2,%d1
        mulu.w  #TRK_SIZE,%d1
        tst.b   TRK_BASE+F_DIG(%a0,%d1.l)
        beq.s   1f
        moveq   #0,%d0
        bra.s   2f
1:      move.l  (%a2),%d0                         | displaced
2:      mac.l   %d0,%d5,%acc0                     | displaced
        jmp     dry_volume_resume

        | ------------------------------------------------------------------
        | fx_block, at its entry. The prologue is re-emitted first (all
        | registers are then saved and restored by stock at the exit), so the
        | registers are free here. frames = 144(%sp) after the prologue.
        |
        | Each track on the digital path is distorted here, before the send mix:
        | the result replaces the voice's slot in the codec frames - so delay,
        | reverb and chorus take the distorted voice - and is kept in CAP for
        | fxout_gate, because the block writes its output over the start of the
        | same frames. Worked in x = slot >> 8 (a voice peaks near 2^20 there):
        |   drive  y = clip(x * g, +-CLIP), g = (16 + DRV % 16) / 16 << DRV / 16
        |          (DRV 0 = unity, +6 dB per 16, up to +48 dB). The clip level
        |          sits a little above a normal voice, so DRV changes the grit,
        |          not the level: a fully driven voice comes out about as loud
        |          as a clean one at peak (a few dB more by RMS).
        |   bits   BIT 1..127: y rounded to steps of 2^(9..20) - 13 down to 2
        |          bits over +-CLIP; rounding, so no DC and no level jump
        |   makeup y = y / min(g, 3): the drive gain is taken back off up to
        |          +9.5 dB, so a voice below the clip keeps its level as DRV
        |          rises, and a driven one comes out near a clean voice's peak
        |          (hardware: the plain drive still added audible gain)
        |   rate   hold y for 1 + SRR / 4 samples
        | The slot gets y << 8 back (same scale as the clean voice).
        |
        | CHR picks the drive's character (0..42 HARD, 43..85 RAT, 86..127 OD).
        | RAT and OD add one-pole filters, run in z = x >> 5 with Q11
        | coefficients a = 1 - exp(-2 pi fc / 48 kHz), lp += (in - lp) * a:
        |   RAT  e = z + HP(z, 1.5 kHz) / 2   a mild treble lift (the RAT's
        |        e = LP(e, 5.2 kHz -> 2.1 kHz as DRV rises)   op-amp running out
        |        of bandwidth at high gain), drive, hard clip (its diodes),
        |        then LP 4 kHz (the FILTER knob around noon)
        |   OD   e = z + HP(z, 720 Hz)        the Tube Screamer's mid hump,
        |        drive, soft clip y = (3u - u^3) / 2 (u normalised to SOFT_CLIP;
        |        unity at small signals once makeup takes the 3/2 off), then
        |        LP 2.5 kHz (its dark TONE)
        | ------------------------------------------------------------------
        .equ    CLIP,       0x180000
        .equ    SOFT_CLIP,  0x200000              | 2^21: u >> 6 is Q15
        .equ    MAKEUP_MAX, 3
        .equ    CHR_OFF,    50                    | S + 50 + t: per-track CHR
        | 0010's WAV switch lives in each sound: the track's live sound is in
        | the 338-byte storage format at S - 1352 + 338 t, and the oscillator's
        | mode is its unused parameter word 103 (+226), set only when its high
        | byte is WAV_SIG (sounds from older OSes can carry other values there).
        | Since 2026-10-26 a CHD sound's chord is its COL knob (13 zones, so it
        | locks; named from the value each knob draw shows) and its FLD is the
        | unused word 102 (+224, FOLD_SIG): 0010 reads both the same way.
        .equ    SND_SIZE,   338
        .equ    SND0_FROM_S, 1352
        .equ    SND_WAV,    226
        .equ    FOLD_SIG,   0x46                  | word 102 = 0x46xx: CHD's FLD
        .equ    F_FOLD,     8                     | (a layer entry's E_OFF for it)
        .equ    LASTCOL,    0x46803034            | COL's value as last drawn (8.8,
                                                  | 0010's free DDR)
        .equ    WAV_SIG,    0x57                  | word 103 = 0x57xx when set:
                                                  | xx = mode (bits 2..6, the old
                                                  | chord type, are no longer read)
        .equ    NCHORDS,    13
        .equ    PAGE_DIST,  17
        .equ    PAGE_NOISE, 7
        .equ    ID_SNH,     74
        .equ    ID_COL,     75
        .equ    ID_FAD,     76
        | Per-track DSP state off HOLD, a REC-byte record per track (a5 steps
        | by REC), copied to the stack around the track's sample loop:
        .equ    FS,         4
        .equ    REC,        16*FS
        .equ    HV,         0*FS                  | the held sample
        .equ    CNT,        1*FS                  | the hold count
        .equ    MAKEUP,     2*FS                  | makeup, Q8
        .equ    HLEN,       3*FS                  | hold length
        .equ    TYPE,       4*FS                  | 0 HARD, 1 RAT, 2 OD
        .equ    A1,         5*FS                  | emphasis HP corner
        .equ    A2,         6*FS                  | pre-clip LP
        .equ    A3,         7*FS                  | tone LP
        .equ    LP1,        8*FS                  | the filters' states
        .equ    LP2,        9*FS
        .equ    LP3,        10*FS
        .equ    ESH,        11*FS                 | emphasis: hp >> ESH
        .equ    LTYPE,      12*FS                 | TYPE | STATE_TAG the states are for
        .equ    STATE_TAG,  0x5a5a00
        .equ    SENDK,      13*FS                 | the sends' gain, Q8 (from LEV)
        .equ    H1,         14*FS                 | the input HP's two states (hp2)
        .equ    H2,         15*FS
        .align  2
fxin_gate:
        lea     -140(%sp),%sp                     | displaced
        movem.l %d2-%d7/%a2-%a6,(%sp)             | displaced
        move.l  project_ptr,%d0
        beq.w   99f
        move.l  %d0,%a0
        move.l  PROJECT_KIT_FX_STORAGE(%a0),%d0
        beq.w   99f
        move.l  %d0,%a2
        lea     TRK_BASE(%a2),%a2                 | track 0's settings
        move.l  144(%sp),%a3                      | track 0's slot in the frames
        move.l  #CAP,%a1
        move.l  #HOLD,%a5                         | &hold[0]
        moveq   #4,%d7                            | tracks left

1:      tst.b   F_DIG(%a2)
        beq.w   8f
        move.l  %a5,-(%sp)                        | the track's state onto the
        lea     -REC(%sp),%sp                     | (cached) stack for the block
        move.l  %sp,%a0
        moveq   #REC/4,%d1
21:     move.l  (%a5)+,(%a0)+
        subq.l  #1,%d1
        bne.s   21b
        move.l  %sp,%a5
        .if     P_CHR                             | the characters: CHR, filter states, coefficients
        move.l  %d7,%d1                           | CHR: S + 50 + t = a2 + 4 + 5 * d7
        mulu.w  #5,%d1                            | (a2 = S + 26 + 6t, d7 = 4 - t)
        addq.l  #4,%d1
        mvz.b   (%a2,%d1.l),%d1
        moveq   #0,%d0                            | CHR 0 HARD, 1 RAT, 2+ OD
        tst.l   %d1                               | (the DIST page sets 0..2;
        beq.s   12f                               | older kits held 0..127)
        moveq   #1,%d0
        subq.l  #1,%d1
        beq.s   12f
        moveq   #2,%d0
12:     move.l  %d0,TYPE(%a5)
        | Filter states: this DDR is never cleared, and from a large junk value
        | the 32-bit (in - lp) * a wraps and the filter locks onto it - a
        | pinned DC output, i.e. silence and clicks (hardware, 2026-10-11).
        | So: clear them when the character changes (or on the first block,
        | the tag being junk too), and clear any state out of +-2^20 (a real
        | one stays under 2^18; past 2^20 the multiply could wrap).
        ori.l   #STATE_TAG,%d0
        cmp.l   LTYPE(%a5),%d0
        beq.s   16f
        move.l  %d0,LTYPE(%a5)
        clr.l   LP1(%a5)
        clr.l   LP2(%a5)
        clr.l   LP3(%a5)
16:     lea     LP1(%a5),%a6                      | a6 is set again below
        moveq   #3,%d1
17:     move.l  (%a6),%d0
        addi.l  #0x100000,%d0
        cmpi.l  #0x200000,%d0
        bcs.s   18f
        clr.l   (%a6)
18:     lea     FS(%a6),%a6
        subq.l  #1,%d1
        bne.s   17b
        move.l  TYPE(%a5),%d0
        cmpi.l  #1,%d0
        bne.s   13f
        move.l  #364,%d1                          | RAT: HP 1.5 kHz, half
        move.l  %d1,A1(%a5)
        moveq   #1,%d1
        move.l  %d1,ESH(%a5)
        mvz.b   F_DRV(%a2),%d1                    | LP 5.2 -> 2.1 kHz
        lsl.l   #2,%d1
        neg.l   %d1
        addi.l  #1000,%d1
        move.l  %d1,A2(%a5)
        move.l  #836,%d1                          | tone 4 kHz
        move.l  %d1,A3(%a5)
        bra.s   14f
13:     move.l  #184,%d1                          | OD: HP 720 Hz, whole
        move.l  %d1,A1(%a5)
        clr.l   ESH(%a5)
        move.l  #2048,%d1                         | no pre-clip LP
        move.l  %d1,A2(%a5)
        move.l  #572,%d1                          | tone 2.5 kHz
        move.l  %d1,A3(%a5)
        .endif
14:     mvz.b   F_DRV(%a2),%d0
        moveq   #15,%d3
        and.l   %d0,%d3
        addi.l  #16,%d3                           | d3 = 16 + DRV % 16
        move.l  %d0,%d6
        lsr.l   #4,%d6                            | d6 = DRV / 16
        move.l  #CLIP << 4,%d0
        move.l  #4096,%d5                         | makeup numerator
        .if     P_CHR                             | OD: the soft clip's level
        moveq   #2,%d1
        cmp.l   TYPE(%a5),%d1
        bne.s   15f
        move.l  #SOFT_CLIP << 4,%d0
        move.l  #2731,%d5                         | and the soft clip's 3/2
        .endif
15:     asr.l   %d6,%d0
        move.l  %d0,%a4                           | a4 = the clip before << d6 >> 4
        move.l  %d3,%d1                           | makeup = 256 / min(g, MAKEUP_MAX)
        lsl.l   %d6,%d1                           | g * 16
        moveq   #MAKEUP_MAX * 16,%d0
        cmp.l   %d0,%d1
        ble.s   10f
        move.l  %d0,%d1
10:     move.l  %d5,%d0
        divu.l  %d1,%d0
        move.l  %d0,MAKEUP(%a5)
        jsr     hp_set                            | SENDK, the HP's states (.dp3)
        moveq   #-1,%d4                           | BIT 0: mask -1, half 0
        sub.l   %a6,%a6
        mvz.b   F_BIT(%a2),%d0
        beq.s   11f
        mulu.w  #3,%d0
        lsr.l   #5,%d0
        addi.l  #9,%d0                            | step 2^9 .. 2^20
        lsl.l   %d0,%d4                           | mask
        moveq   #1,%d1
        subq.l  #1,%d0
        lsl.l   %d0,%d1
        move.l  %d1,%a6                           | half a step
11:     mvz.b   F_SRR(%a2),%d0
        lsr.l   #2,%d0
        addq.l  #1,%d0
        move.l  %d0,HLEN(%a5)                     | hold length
        move.l  %a3,%a0
        moveq   #FRAMES,%d2

2:      move.l  (%a0),%d0                         | x
        asr.l   #8,%d0
        jsr     hp2                               | the input HP (.dp3)
        .if     P_CHR                             | RAT/OD: emphasis and pre-clip LP
        tst.l   TYPE(%a5)
        beq.s   20f
        asr.l   #5,%d0                            | z
        move.l  %d0,%d5                           | emphasis: lp1 += (z - lp1) a1
        sub.l   LP1(%a5),%d5
        muls.l  A1(%a5),%d5
        moveq   #11,%d1
        asr.l   %d1,%d5
        add.l   LP1(%a5),%d5
        move.l  %d5,LP1(%a5)
        sub.l   %d5,%d0                           | hp = z - lp1
        add.l   %d0,%d5                           | z
        move.l  ESH(%a5),%d1
        asr.l   %d1,%d0
        add.l   %d5,%d0                           | e = z + hp >> ESH
        move.l  %d0,%d5                           | pre-clip LP
        sub.l   LP2(%a5),%d5
        muls.l  A2(%a5),%d5
        moveq   #11,%d1
        asr.l   %d1,%d5
        add.l   LP2(%a5),%d5
        move.l  %d5,LP2(%a5)
        move.l  %d5,%d0
        lsl.l   #5,%d0                            | back to x
        .endif
20:     muls.l  %d3,%d0
        cmp.l   %a4,%d0
        ble.s   3f
        move.l  %a4,%d0
3:      move.l  %a4,%d1
        neg.l   %d1
        cmp.l   %d1,%d0
        bge.s   4f
        move.l  %d1,%d0
4:      lsl.l   %d6,%d0
        asr.l   #4,%d0                            | u, within the clip
        .if     P_CHR                             | OD's soft clip, the tone LP
        move.l  TYPE(%a5),%d1
        beq.s   23f
        moveq   #2,%d5
        cmp.l   %d1,%d5
        bne.s   22f
        asr.l   #6,%d0                            | OD: t = u / SOFT_CLIP, Q15
        move.l  %d0,%d1
        muls.l  %d0,%d1
        moveq   #15,%d5
        asr.l   %d5,%d1
        muls.l  %d0,%d1
        asr.l   %d5,%d1                           | t^3
        move.l  %d0,%d5
        add.l   %d0,%d0
        add.l   %d5,%d0
        sub.l   %d1,%d0                           | 3t - t^3
        lsl.l   #5,%d0                            | / 2, back to x
22:     asr.l   #5,%d0                            | tone LP, in z
        move.l  %d0,%d5
        sub.l   LP3(%a5),%d5
        muls.l  A3(%a5),%d5
        moveq   #11,%d1
        asr.l   %d1,%d5
        add.l   LP3(%a5),%d5
        move.l  %d5,LP3(%a5)
        move.l  %d5,%d0
        lsl.l   #5,%d0
        .endif
23:     add.l   %a6,%d0
        and.l   %d4,%d0                           | bits
        muls.l  MAKEUP(%a5),%d0
        asr.l   #8,%d0                            | makeup
        move.l  CNT(%a5),%d1                      | rate: count
        addq.l  #1,%d1
        cmp.l   HLEN(%a5),%d1
        bcs.s   5f
        moveq   #0,%d1
        move.l  %d0,HV(%a5)                       | a new held sample
5:      move.l  %d1,CNT(%a5)
        move.l  HV(%a5),%d0
        move.l  %d0,(%a1)+                        | for fxout_gate
        muls.l  SENDK(%a5),%d0                    | << 8 back to slot scale, trimmed
        move.l  %d0,(%a0)                         | for the sends
        lea     FRAME_SIZE(%a0),%a0
        subq.l  #1,%d2
        bne.w   2b
        move.l  REC(%sp),%a0                      | the state back
        moveq   #REC/4,%d1
22:     move.l  (%a5)+,(%a0)+
        subq.l  #1,%d1
        bne.s   22b
        move.l  REC(%sp),%a5
        lea     REC+4(%sp),%sp
        bra.s   9f

8:      lea     FRAMES*4(%a1),%a1
9:      lea     TRK_SIZE(%a2),%a2
        addq.l  #4,%a3                            | the next voice's slot
        lea     REC(%a5),%a5
        subq.l  #1,%d7
        bne.w   1b
99:
        jmp     fx_block_body

        | ------------------------------------------------------------------
        | fx_block, after its output loop (a4 just past the 32 output pairs):
        | each track on the digital path adds its processed voice from CAP to
        | both output channels (centre), at
        |   out += (y >> 2) * LEV * 13 / 32   (y = the x-scale sample from
        | fxin_gate). Calibrated on hardware: with plain y * LEV, LEV 10 matched
        | the same sound on the analog path; asked for that at LEV ~100, so the
        | gain is LEV * 13 / 128 (LEV 100 = 10.2), 127 = +2 dB over it.
        | The displaced store goes first; a0 and d1 must survive (stock stores
        | them next).

        .section .dp3,"ax"
        | ------------------------------------------------------------------
        | The input HP, ahead of everything on the digital path (the drive is
        | otherwise most sensitive to an acid line's low end): two one-pole
        | high-passes in x, lp += (x - lp) * 5 / 512, hp = x - lp, each 75 Hz
        | (-ln(1 - 5/512) x 48 kHz / 2 pi): 12 dB/oct, -6 dB at 75 Hz, the
        | emulator's model of filter 2 in HP2 at RES 0 (k = 2: two equal poles)
        | at FRQ ~32. Shifts and adds only, no multiply to wrap: d0 = x in and
        | out, d1 and d5 clobbered (free at the sample loop's top).
        | ------------------------------------------------------------------
        .align  2
hp2:    move.l  %d0,%d5
        sub.l   H1(%a5),%d5                       | x - lp1
        move.l  %d5,%d1
        asr.l   #7,%d5
        asr.l   #8,%d1
        asr.l   #1,%d1
        add.l   %d1,%d5                           | (x - lp1) * 5 / 512
        add.l   H1(%a5),%d5
        move.l  %d5,H1(%a5)
        sub.l   %d5,%d0                           | hp1
        move.l  %d0,%d5
        sub.l   H2(%a5),%d5
        move.l  %d5,%d1
        asr.l   #7,%d5
        asr.l   #8,%d1
        asr.l   #1,%d1
        add.l   %d1,%d5
        add.l   H2(%a5),%d5
        move.l  %d5,H2(%a5)
        sub.l   %d5,%d0                           | hp2
        rts

        | Per block, from fxin_gate: the sends follow LEV as the dry output
        | does (Q8 LEV x 2.5, so LEV 100, the analog path's level, is unity, as
        | the slot was clean); then the HP's states, cleared when out of
        | +-2^24 (this DDR is never cleared; a real state stays under 2^23).
        | a0, d0, d1 free.
hp_set: mvz.b   F_LEV(%a2),%d0
        eori.l  #64,%d0
        mulu.w  #10,%d0
        lsr.l   #2,%d0
        move.l  %d0,SENDK(%a5)
        lea     H1(%a5),%a0
        moveq   #2,%d1
1:      move.l  (%a0),%d0
        addi.l  #0x1000000,%d0
        cmpi.l  #0x2000000,%d0
        bcs.s   2f
        clr.l   (%a0)
2:      addq.l  #4,%a0
        subq.l  #1,%d1
        bne.s   1b
        rts

        .section .dsp2,"ax"
        | ------------------------------------------------------------------
        .align  2
fxout_gate:
        move.l  %d0,FX_STATE4                     | displaced
        lea     -32(%sp),%sp
        movem.l %d1-%d4/%a0-%a3,(%sp)
        move.l  project_ptr,%d0
        beq.w   99f
        move.l  %d0,%a0
        move.l  PROJECT_KIT_FX_STORAGE(%a0),%d0
        beq.w   99f
        move.l  %d0,%a2
        lea     TRK_BASE(%a2),%a2
        move.l  #CAP,%a1
        moveq   #4,%d4                            | tracks left

1:      tst.b   F_DIG(%a2)
        beq.s   8f
        mvz.b   F_LEV(%a2),%d3
        eori.l  #64,%d3                           | level
        mulu.w  #13,%d3
        lea     -FRAMES*8(%a4),%a3                | the output pairs
        moveq   #FRAMES,%d2
2:      move.l  (%a1)+,%d0
        asr.l   #2,%d0
        muls.l  %d3,%d0
        asr.l   #5,%d0
        move.l  (%a3),%d1
        add.l   %d0,%d1
        sats.l  %d1
        move.l  %d1,(%a3)+
        move.l  (%a3),%d1
        add.l   %d0,%d1
        sats.l  %d1
        move.l  %d1,(%a3)+
        subq.l  #1,%d2
        bne.s   2b
        bra.s   9f
8:      lea     FRAMES*4(%a1),%a1
9:      lea     TRK_SIZE(%a2),%a2
        subq.l  #1,%d4
        bne.s   1b
99:     movem.l (%sp),%d1-%d4/%a0-%a3
        lea     32(%sp),%sp
        jmp     fx_block_tail_resume

        | ==================================================================
        | UI side: the FUNC layer
        | ==================================================================

        | fx_S() -> a0 = d0 = the active kit's FX storage, 0 if none (flags set).
        .align  2
fx_S:
        sub.l   %a0,%a0
        move.l  project_ptr,%d0
        beq.s   1f
        move.l  %d0,%a0
        move.l  PROJECT_KIT_FX_STORAGE(%a0),%a0
1:      move.l  %a0,%d0
        rts

        | find(d0 = id) -> a1 = its entry in layer_table, or Z if not ours.
        .align  2
find:
        lea     layer_table,%a1
1:      tst.w   (%a1)
        beq.s   9f
        cmp.w   (%a1),%d0
        beq.s   8f
        lea     ENTRY(%a1),%a1
        bra.s   1b
8:      move.l  %a1,%d1                           | Z clear
        rts
9:      moveq   #0,%d1                            | Z set
        rts

        | key_find(d0 = page, d2 = id) -> find(page << 9 | id).
        .align  2
key_find:
        lsl.l   #8,%d0
        add.l   %d0,%d0
        or.l    %d2,%d0
        bra.s   find

        | slot_of(a0 = view, d0 = id) -> d0 = the setting's byte offset from S
        | (negative for a sound's WAV byte), d1 = XOR, a1 = its entry; or d0 = 0
        | if the knob is not ours on this view's page. Per-track and sound
        | entries use the view's track and refuse the FX track.

        .section .ui3,"ax"
        .align  2
slot_of:
        lea     -8(%sp),%sp
        movem.l %d2/%a2,(%sp)
        move.l  %a0,%a2
        move.l  %d0,%d2
        jsr     shared_view_page                  | (0008)
        jbsr   key_find
        beq.s   8f
        move.l  %a1,-(%sp)
        tst.b   E_TRACK(%a1)
        beq.s   3f
        move.l  116(%a2),-(%sp)
        jsr     track_index_of
        addq.l  #4,%sp
        moveq   #3,%d1
        cmp.l   %d1,%d0
        bhi.s   7f
        move.l  (%sp),%a1
        mvz.b   E_TRACK(%a1),%d1                  | the entry's track stride,
        cmpi.l  #SOUND,%d1                        | or SOUND: the track's live
        bne.s   5f                                | sound's WAV byte
        mulu.w  #SND_SIZE,%d0
        subi.l  #SND0_FROM_S-SND_WAV,%d0
        moveq   #0,%d1
        move.l  (%sp)+,%a1
        bra.s   9f
5:      mulu.w  %d1,%d0
        move.l  %d0,%d1
        bra.s   4f
3:      moveq   #0,%d1
4:      move.l  (%sp)+,%a1
        mvz.b   E_OFF(%a1),%d0
        add.l   %d1,%d0
        mvz.b   E_XOR(%a1),%d1
        bra.s   9f
7:      addq.l  #4,%sp
8:      moveq   #0,%d0
9:      movem.l (%sp),%d2/%a2
        lea     8(%sp),%sp
        rts

        | ------------------------------------------------------------------
        | page_get_value(view, id, lock), at its entry: while FUNC is held,
        | our knobs read our setting (8.8), which is what the dials draw.
        | ------------------------------------------------------------------
        .align  2
pgv_gate:
        move.l  4(%sp),%a0                        | the view
        move.l  8(%sp),%d0
        jbsr   slot_of
        tst.l   %d0
        beq.s   9f
        move.l  %d2,-(%sp)
        move.l  %d0,%d2                           | offset
        move.l  %d1,-(%sp)                        | XOR
        jbsr   fx_S
        move.l  (%sp)+,%d1
        move.l  %a0,%d0
        beq.s   8f
        jbsr   slot_rd
        eor.l   %d1,%d0
        mvz.b   E_MAX(%a1),%d1                    | a1 = the entry (slot_of)
        cmp.l   %d1,%d0
        ble.s   1f
        move.l  %d1,%d0                           | clamp (older, wider values)
1:      subq.l  #2,%d1                            | 3 positions: drawn as 0/63/127
        bne.s   2f                                | on the dial; switches (max 1)
        mulu.w  #127,%d0                          | as 0/1 (their max is 0x100)
        lsr.l   #1,%d0
2:      lsl.l   #8,%d0
        move.l  (%sp)+,%d2
        rts
8:      move.l  (%sp)+,%d2
9:      lea     -12(%sp),%sp                      | displaced
        movem.l %d2-%d3/%a2,(%sp)                 | displaced
        jmp     page_get_value_body

        | ------------------------------------------------------------------
        | The encoder handler's call of param_apply_delta, with (view, id,
        | delta, FUNC, &flag) pushed and a0 = the view's vtable. While FUNC is
        | held our knobs change our setting by the delta's whole steps (at least
        | one), the kit is marked edited, and the handler exits without stock's
        | value popup (which would show the stock parameter).
        | ------------------------------------------------------------------
        .align  2
enc_gate:
        move.l  %a0,-(%sp)                        | the vtable, for stock's path
        move.l  4(%sp),%a0                        | view
        move.l  8(%sp),%d0                        | id
        jbsr   slot_of
        tst.l   %d0
        beq.w   8f
        lea     -12(%sp),%sp                      | +12: delta at 8 + 4 + 12 = 24
        movem.l %d2-%d4,(%sp)
        move.l  %d0,%d2                           | offset
        move.l  %d1,%d3                           | XOR
        jbsr   fx_S
        beq.s   7f
        jbsr   slot_rd
        eor.l   %d3,%d0                           | the value as shown
        mvz.b   E_MAX(%a1),%d4                    | a1 = the entry (slot_of)
        cmp.l   %d4,%d0
        ble.s   4f
        move.l  %d4,%d0
4:      move.l  24(%sp),%d1
        asr.l   #8,%d1
        bne.s   1f
        moveq   #1,%d1
        tst.l   24(%sp)
        bpl.s   1f
        moveq   #-1,%d1
1:      add.l   %d1,%d0
        bpl.s   2f
        moveq   #0,%d0
2:      cmp.l   %d4,%d0                           | up to the entry's max
        ble.s   3f
        move.l  %d4,%d0
3:      eor.l   %d3,%d0
        jbsr   slot_wr
        jbsr   kit_notify
7:      movem.l (%sp),%d2-%d4
        lea     16(%sp),%sp                       | the saved registers and the vtable
        lea     20(%sp),%sp                       | the call's arguments
        jmp     encoder_exit
8:      move.l  (%sp)+,%a0                        | the vtable
        moveal  88(%a0),%a0                       | displaced
        jsr     (%a0)                             | displaced
        jmp     encoder_apply_resume

        | ------------------------------------------------------------------
        | param_label(set, id, x, out), at its entry: while FUNC is held our
        | knobs are labelled with our names.
        |
        | out is a plain character buffer, not a string object: the page draw
        | passes &fp@(-16) and builds its own string from it afterwards
        | (0x400231b4). So the name is copied in, NUL and all. (The first build
        | constructed a string object there, and the page printed its pointer
        | bytes - the garbled labels seen on hardware, 2026-10-10.)

        .section .ui4,"ax"
        | ------------------------------------------------------------------
        .align  2
lbl_gate:
        move.l  8(%sp),%d0
        moveq   #ID_COL,%d1                       | COL: note the value this draw
        cmp.l   %d1,%d0                           | shows (x, 8.8: a held trig's
        bne.s   2f                                | lock included), which names
        move.l  12(%sp),%d1                       | a CHD sound's chord
        move.l  %d1,LASTCOL
2:      jbsr   name_of
        beq.s   9f
        move.l  %d0,%a0
        move.l  16(%sp),%a1                       | out
1:      move.b  (%a0)+,%d0
        move.b  %d0,(%a1)+
        bne.s   1b
        rts
9:      move.l  %d3,-(%sp)                        | displaced
        move.l  %d2,-(%sp)                        | displaced
        move.l  20(%sp),%d2                       | displaced
        jmp     param_label_body

        | ------------------------------------------------------------------
        | The parameter sets' short-name getter (vtable +0x74, shared):
        | (set, id) -> the record's short name (record + 0x30), which the knob
        | draw prints under each dial. On the DIST page our knobs get our names.
        | (A swap of the record during the dial draw did not work: the name is
        | fetched after the dial is drawn.)
        | ------------------------------------------------------------------
        .align  2
sname_gate:
        move.l  8(%sp),%d0
        jbsr   name_of
        beq.s   1f
        rts
1:      move.l  8(%sp),%d0                        | displaced
        cmpi.l  #295,%d0                          | displaced
        jmp     short_name_resume

        | kit_notify(): mark the active kit's FX as edited, as stock's FxSetup
        | setters do (vtable +0x10 with a change record {vt, -1, 1, 1}).
        .align  2
kit_notify:
        move.l  project_ptr,%d0
        beq.s   9f
        add.l   #PROJECT_FXSETUP,%d0
        move.l  %d0,%a0                           | the FxSetup
        lea     -12(%sp),%sp
        move.l  #fx_change_info_vt,(%sp)
        moveq   #-1,%d0
        move.l  %d0,4(%sp)
        moveq   #1,%d0
        move.b  %d0,8(%sp)
        move.b  %d0,9(%sp)
        move.l  %sp,%d0
        move.l  %d0,-(%sp)
        move.l  %a0,-(%sp)
        move.l  (%a0),%a0
        move.l  VT_FX_NOTIFY(%a0),%a0
        jsr     (%a0)
        lea     20(%sp),%sp
9:      rts

        | ==================================================================
        | Data
        | ==================================================================

        | The DIST page's knobs (0008's page 17 descriptor lists these ids):
        | {page << 9 | id .w, offset.b, XOR.b, track stride.b (0 = not per
        | track, SOUND = a field of the track's live sound's word 103, offset =
        | its shift; offset F_FOLD = word 102, CHD's FLD), max.b, name.l}.
        | The id picks how the A4 draws the knob: 50, 63 and 43 (OSC AM1 / AM2
        | / TRK) are on/off switches, the AMP ids are 0..127 dials.
        .equ    E_OFF,   2
        .equ    E_XOR,   3
        .equ    E_TRACK, 4
        .equ    E_MAX,   5
        .equ    E_NAME,  6
        .equ    ENTRY,   10
        .equ    SOUND,   254
        .equ    P17,     PAGE_DIST << 9
        .align  2
layer_table:
        .short  P17+50                              | OSC AM1 switch -> DIG
        .byte   TRK_BASE+F_DIG, 0, TRK_SIZE, 1
        .long   s_dig
        .if     P_CHR
        .short  P17+92                              | AMP REL dial -> CHR, 3 steps
        .byte   CHR_OFF, 0, 1, 2
        .long   s_chr
        .endif
        .short  P17+94                              | AMP CHO -> DRV
        .byte   TRK_BASE+F_DRV, 0, TRK_SIZE, 127
        .long   s_drv
        .short  P17+95                              | AMP DEL -> BIT
        .byte   TRK_BASE+F_BIT, 0, TRK_SIZE, 127
        .long   s_bit
        .short  P17+96                              | AMP REV -> SRR
        .byte   TRK_BASE+F_SRR, 0, TRK_SIZE, 127
        .long   s_srr
        .short  P17+98                              | AMP VOL -> LEV
        .byte   TRK_BASE+F_LEV, 64, TRK_SIZE, 127
        .long   s_lev
        .short  P17+63                              | OSC AM2 switch -> SLD (0002)
        .byte   TRK_BASE+F_SLD, 0, TRK_SIZE, 1
        .long   s_sld
        .short  PAGE_NOISE << 9 + 92              | NOISE page, AMP REL dial, 3
        .byte   0, 0, SOUND, 2                    | positions: OFF WAV CHD (0010)
        .long   s_wav                             | (offset = the field's shift)
        .short  PAGE_NOISE << 9 + 94              | NOISE page, AMP CHO dial:
        .byte   F_FOLD, 0, SOUND, 127             | CHD's FLD (the sound's word
        .long   s_fld                             | 102; the chord is on COL)
        .short  0

s_dig:  .asciz  "DIG"
        .if     P_CHR
s_chr:  .asciz  "CHR"
        .endif
s_drv:  .asciz  "DRV"
s_bit:  .asciz  "BIT"
s_srr:  .asciz  "SRR"
s_lev:  .asciz  "LEV"
s_sld:  .asciz  "SLD"
s_wav:  .asciz  "WAV"

        | ==================================================================
        | In `cave` (cave2 is full): the knob labels
        | ==================================================================
        .section .ui2,"ax"

s_shp:  .asciz  "SHP"                         | the NOISE page with WAV on
s_fld:  .asciz  "FLD"
s_fm:   .asciz  "FM"

        | snd_word(a0 = view) -> d0 = the view's track's live word 103, 0 if
        | none. d0/d1/a0/a1.
        .align  2
snd_word:
        move.l  116(%a0),-(%sp)
        jsr     track_index_of
        addq.l  #4,%sp
        moveq   #3,%d1
        cmp.l   %d1,%d0
        bhi.s   8f
        mulu.w  #SND_SIZE,%d0
        move.l  %d0,%d1
        jbsr   fx_S
        beq.s   8f
        add.l   %d1,%a0
        mvz.w   SND_WAV-SND0_FROM_S(%a0),%d0
        rts
8:      moveq   #0,%d0
        rts

        | Names, 4 bytes each: the oscillator's modes and 0010's chords.
        .align  2
m_names: .asciz "OFF", "WAV", "CHD", "OFF"         | (3 letters + NUL each)
c_names: .asciz "OCT", "5TH", "MAJ", "MIN", "SU2"
        .asciz  "SU4", "MA7", "MI7", "DO7", "MI9"
        .asciz  "HDX", "SW1", "SW2"

        | ==================================================================
        | In cave9 / cave10 (the shelved inputs build's space)
        | ==================================================================
        .section .ui6,"ax"

        | name_of(d0 = id) -> d0 = our label for that knob of the view drawn
        | last (0008's shared_draw_view), Z clear; or Z set. Settings get
        | their names; the oscillator's two dials name their value (OFF WAV
        | CHD, the chord); with the oscillator on, S&H, COL and FAD become
        | SHP, FLD and FM. d2/d3 kept.
        .align  2
name_of:
        lea     -12(%sp),%sp
        movem.l %d2-%d3/%a2,(%sp)
        move.l  %d0,%d2                           | id
        move.l  shared_draw_view,%d0
        jeq     8f
        move.l  %d0,%a2
        move.l  %d0,%a0
        jsr     shared_view_page
        move.l  %d0,%d3                           | page
        jbsr   key_find
        jeq     1f
        mvz.b   E_TRACK(%a1),%d0
        cmpi.l  #SOUND,%d0
        jeq     3f
        move.l  E_NAME(%a1),%d0
        jra     9f
3:      move.l  %a1,-(%sp)                        | a sound field: its value
        move.l  %a2,%a0
        jbsr   snd_word
        move.l  (%sp)+,%a1
        mvz.b   E_OFF(%a1),%d1
        moveq   #F_FOLD,%d2
        cmp.l   %d2,%d1
        jeq     5f
        jbsr   sfield                            | the mode dial: its value
        lea     m_names,%a0
4:      lsl.l   #2,%d0
        add.l   %d0,%a0
        move.l  %a0,%d0
        jra     9f
1:      moveq   #PAGE_NOISE,%d0                   | the NOISE page with the
        cmp.l   %d3,%d0                           | oscillator on
        jne     8f
        lea     s_shp,%a1
        moveq   #ID_SNH,%d0
        cmp.l   %d2,%d0
        jeq     2f
        lea     s_fld,%a1
        moveq   #ID_COL,%d0
        cmp.l   %d2,%d0
        jeq     2f
        lea     s_fm,%a1
        moveq   #ID_FAD,%d0
        cmp.l   %d2,%d0
        jne     8f
2:      move.l  %a1,%d3
        move.l  %a2,%a0
        jbsr   snd_word
        move.l  %d0,%d1
        lsr.l   #8,%d1
        cmpi.l  #WAV_SIG,%d1
        jne     8f
        moveq   #3,%d1
        and.l   %d1,%d0
        jeq     8f
        jsr     osc_name                          | (.ui8) COL in CHD: the chord
        jra     9f
5:      jsr     fold_name                         | (.ui8) the FLD dial
        jra     9f
8:      moveq   #0,%d0
9:      movem.l (%sp),%d2-%d3/%a2
        lea     12(%sp),%sp
        rts


        .section .ui2,"ax"                        | (back beside the names: room)

        | slot_rd(a0 = S, d2 = slot_of's offset, a1 = the entry) -> d0 = the
        | setting: the kit byte there, or (a negative offset) the entry's field
        | of the sound's word 103. slot_wr(a0, d2, d0, a1): the inverse,
        | setting the word's signature. d1 kept.
        .align  2
slot_rd:
        tst.l   %d2
        bmi.s   1f
        mvz.b   (%a0,%d2.l),%d0
        rts
1:      move.l  %d1,-(%sp)
        mvz.b   E_OFF(%a1),%d1
        moveq   #F_FOLD,%d0
        cmp.l   %d0,%d1
        bne.s   2f
        mvz.w   -2(%a0,%d2.l),%d0                 | CHD's FLD: word 102, 0x46xx
        move.l  %d0,%d1
        lsr.l   #8,%d1
        cmpi.l  #FOLD_SIG,%d1
        beq.s   3f
        moveq   #0,%d0                            | (not set: 0)
3:      moveq   #0x7f,%d1
        and.l   %d1,%d0
        bra.s   4f
2:      mvz.w   (%a0,%d2.l),%d0
        jbsr   sfield
4:      move.l  (%sp)+,%d1
        rts

        | sfield(d0 = a word 103, a1 = the entry) -> d0 = the entry's field
        | (0 if the word is not set). d1 used.
        .align  2
sfield:
        move.l  %d0,%d1
        lsr.l   #8,%d1
        cmpi.l  #WAV_SIG,%d1
        beq.s   1f
        moveq   #0,%d0
1:      mvz.b   E_OFF(%a1),%d1
        lsr.l   %d1,%d0
        moveq   #3,%d1                            | the mode: 2 bits
        tst.b   E_OFF(%a1)
        beq.s   2f
        moveq   #0x1f,%d1                         | the chord type: 5
2:      and.l   %d1,%d0
        rts

        .align  2
slot_wr:
        tst.l   %d2
        bmi.s   1f
        move.b  %d0,(%a0,%d2.l)
        rts
1:      lea     -12(%sp),%sp
        movem.l %d1/%d3-%d4,(%sp)
        mvz.b   E_OFF(%a1),%d1
        moveq   #F_FOLD,%d3
        cmp.l   %d3,%d1
        bne.s   4f
        moveq   #0x7f,%d1                         | CHD's FLD: word 102 = 0x46xx
        and.l   %d1,%d0
        ori.l   #FOLD_SIG << 8,%d0
        move.w  %d0,-2(%a0,%d2.l)
        bra.s   5f
4:      mvz.w   (%a0,%d2.l),%d3
        move.l  %d3,%d1
        lsr.l   #8,%d1
        cmpi.l  #WAV_SIG,%d1
        beq.s   2f
        move.l  #WAV_SIG << 8,%d3                 | not set yet: all fields 0
2:      mvz.b   E_OFF(%a1),%d1                    | the shift
        moveq   #3,%d4
        tst.l   %d1
        beq.s   3f
        moveq   #0x1f,%d4
3:      and.l   %d4,%d0
        lsl.l   %d1,%d4
        not.l   %d4
        and.l   %d4,%d3                           | the field cleared
        lsl.l   %d1,%d0
        or.l    %d0,%d3
        move.w  %d3,(%a0,%d2.l)
5:      movem.l (%sp),%d1/%d3-%d4
        lea     12(%sp),%sp
        rts


s_dsh:  .asciz  "---"

        .section .ui8,"ax"

        | osc_name(d0 = the mode 1..2, d2 = the id, d3 = its WAV name) -> d0 =
        | the label: a CHD sound's COL dial is named by the chord its value
        | picks (as the dial last drew it: LASTCOL, held trig's lock included;
        | the engine's 13 zones over 0..127). Z clear. d1, a0.
        .align  2
osc_name:
        subq.l  #2,%d0
        bne.s   6f
        moveq   #ID_COL,%d0
        cmp.l   %d2,%d0
        bne.s   6f
        move.l  LASTCOL,%d0
        asr.l   #8,%d0
        bpl.s   1f
        moveq   #0,%d0
1:      moveq   #127,%d1
        cmp.l   %d1,%d0
        ble.s   2f
        move.l  %d1,%d0
2:      mulu.w  #NCHORDS,%d0
        lsr.l   #7,%d0
        lsl.l   #2,%d0
        lea     c_names,%a0
        add.l   %d0,%a0
        move.l  %a0,%d0
        rts
6:      move.l  %d3,%d0
        rts

        | fold_name(d0 = the sound's word 103) -> d0 = the FLD dial's label:
        | FLD in CHD, else "---" (it folds chords only). Z clear. d1, a0.
        .align  2
fold_name:
        lea     s_dsh,%a0
        move.l  %d0,%d1
        lsr.l   #8,%d1
        cmpi.l  #WAV_SIG,%d1
        bne.s   1f
        moveq   #3,%d1
        and.l   %d1,%d0
        subq.l  #2,%d0
        bne.s   1f
        lea     s_fld,%a0
1:      move.l  %a0,%d0
        rts

