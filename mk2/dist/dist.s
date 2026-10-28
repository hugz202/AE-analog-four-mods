        | SPDX-License-Identifier: MIT
        | dist - AE 0007 (digital path) and 0008 (the DIST page) for the Analog
        | Four MKII, OS 1.56, as an elekloader elemod on core-a4 0.2. This file
        | is the audio side and the knob-name gate; dist.c is the page.
        |
        | Per synth track, on the DIST page (press AMP twice): DIG puts the track
        | on the digital path (its analog dry sound is muted and the A4's own
        | digitised copy is processed instead), CHR picks the character (HARD,
        | RAT, OD), DRV the drive, BIT the bit reduction, SRR the sample-rate
        | reduction, LEV the processed signal's level; SLD is slide's mode.
        |
        | The settings are kit fields in core-a4's mod storage (dist.c). The
        | audio interrupt never calls core: the UI tick copies each track's
        | settings into dist_set, laid out as the MK1 kept them in the kit's
        | spare FX words, so the code below is the image port's (MK2-OS-1.56,
        | mods/0007-digital-path) reading dist_set where it read the kit:
        |   dist_set + 6t + 0..5   DIG DRV BIT SRR LEV SLD for track t (0..3)
        |   dist_set + 24 + t      CHR for track t
        | (LEV is the plain level here; the kit field keeps it XOR 64, so a kit
        | with no dist data reads 64.)
        |
        | Calls follow the stock ABI: d0/d1/a0/a1 are scratch, the rest is saved.

        | OS 1.56 addresses (re/symbols.toml on the MK2-OS-1.56 branch)
        .equ    dry_volume_resume,    0x400fa6ca
        .equ    fx_block_body,        0x400fe744
        .equ    fx_block_tail_resume, 0x400fead4
        .equ    short_name_resume,    0x4009e7a8
        .equ    long_name_resume,     0x4009e7cc
        .equ    KNOB_NAME_CALL,       0x4002367e  | where the knob draw's short-name call returns
        .equ    POPUP_NAME_CALL,      0x40025c2c  | where the encoder handler's long-name call returns

        .equ    TRK_SIZE,   6
        .equ    F_DIG,      0
        .equ    F_DRV,      1
        .equ    F_BIT,      2
        .equ    F_SRR,      3
        .equ    F_LEV,      4
        .equ    F_SLD,      5
        .equ    FRAMES,     32
        .equ    FRAME_SIZE, 32                    | 8 codec slots of 32 bits
        .equ    FX_STATE4,  0x41864a74            | what fx_block_tail stores
                                                  | (MK1: 0x415c0008)
        .equ    VOICE0_SLOT, 8                    | track 0's slot in a frame: the
                                                  | MKII send mix reads slots 2..7
                                                  | (four voices, then the input;
                                                  | MK1: 0..3 and 6..7)

        .text
        .globl  dist_dry, dist_fxin, dist_fxout, dist_sname, dist_lname

        | ==================================================================
        | Audio side (the audio interrupt)
        | ==================================================================

        | ------------------------------------------------------------------
        | track_levels, at `movel %a3@,%d0; macl %d0,%d7,%acc0`: the volume
        | loaded for the analog dry VCA words only (the send gain is already
        | written). d2 = track, d1 and a0 dead. A track on the digital path gets
        | a dry volume of 0 - what stock computes for VOL 0 - and keeps its
        | capture.
        | ------------------------------------------------------------------
        .align  2
dist_dry:
        lea     dist_set,%a0
        moveq   #3,%d0
        cmp.l   %d0,%d2
        bhi.s   1f
        move.l  %d2,%d1
        mulu.w  #TRK_SIZE,%d1
        tst.b   F_DIG(%a0,%d1.l)
        beq.s   1f
        moveq   #0,%d0
        bra.s   2f
1:      move.l  (%a3),%d0                         | displaced
2:      mac.l   %d0,%d7,%acc0                     | displaced
        jmp     dry_volume_resume

        | ------------------------------------------------------------------
        | fx_block, at its entry. The prologue is re-emitted first (all
        | registers are then saved and restored by stock at the exit), so the
        | registers are free here. frames = 144(%sp) after the prologue.
        |
        | Each track on the digital path is distorted here, before the send mix:
        | the result replaces the voice's slot in the codec frames - so delay,
        | reverb and chorus take the distorted voice - and is kept in dist_cap
        | for dist_fxout, because the block writes its output over the start of
        | the same frames. Worked in x = slot >> 8 (a voice peaks near 2^20):
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
        |   rate   hold y for 1 + SRR / 4 samples
        | The slot gets y << 8 back (same scale as the clean voice).
        |
        | CHR picks the drive's character (0 HARD, 1 RAT, 2 OD). RAT and OD add
        | one-pole filters, run in z = x >> 5 with Q11 coefficients
        | a = 1 - exp(-2 pi fc / 48 kHz), lp += (in - lp) * a:
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
        .equ    CHR_OFF,    24                    | dist_set + 24 + t: per-track CHR
        | Per-track DSP state in dist_hold, a REC-byte record per track (a5
        | steps by REC), copied to the stack around the track's sample loop:
        .equ    FS,         4
        .equ    REC,        14*FS
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
        .equ    SENDK,      13*FS                 | send trim, Q8
        .align  2
dist_fxin:
        lea     -140(%sp),%sp                     | displaced
        movem.l %d2-%d7/%a2-%a6,(%sp)             | displaced
        lea     dist_set,%a2                      | track 0's settings
        move.l  144(%sp),%a3                      | the frames
        addq.l  #VOICE0_SLOT,%a3                  | track 0's slot in them
        lea     dist_cap,%a1
        lea     dist_hold,%a5                     | &hold[0]
        moveq   #4,%d7                            | tracks left

1:      tst.b   F_DIG(%a2)
        beq.w   8f
        move.l  %a5,-(%sp)                        | the track's state onto the
        lea     -REC(%sp),%sp                     | stack for the block
        move.l  %sp,%a0
        moveq   #REC/4,%d1
21:     move.l  (%a5)+,(%a0)+
        subq.l  #1,%d1
        bne.s   21b
        move.l  %sp,%a5
        move.l  %d7,%d1                           | CHR: dist_set + 24 + t
        mulu.w  #5,%d1                            | = a2 + 4 + 5 * d7
        addq.l  #4,%d1                            | (a2 = dist_set + 6t, d7 = 4 - t)
        mvz.b   (%a2,%d1.l),%d1
        moveq   #0,%d0                            | CHR 0 HARD, 1 RAT, 2+ OD
        tst.l   %d1
        beq.s   12f
        moveq   #1,%d0
        subq.l  #1,%d1
        beq.s   12f
        moveq   #2,%d0
12:     move.l  %d0,TYPE(%a5)
        | Filter states: clear them when the character changes (or on the
        | first block), and clear any state out of +-2^20 (a real one stays
        | under 2^18; past 2^20 the multiply could wrap and the filter lock
        | onto a pinned DC output).
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
14:     mvz.b   F_DRV(%a2),%d0
        moveq   #15,%d3
        and.l   %d0,%d3
        addi.l  #16,%d3                           | d3 = 16 + DRV % 16
        move.l  %d0,%d6
        lsr.l   #4,%d6                            | d6 = DRV / 16
        move.l  #CLIP << 4,%d0
        move.l  #4096,%d5                         | makeup numerator
        moveq   #2,%d1                            | OD: the soft clip's level
        cmp.l   TYPE(%a5),%d1
        bne.s   15f
        move.l  #SOFT_CLIP << 4,%d0
        move.l  #2731,%d5                         | and the soft clip's 3/2
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
        mvz.b   F_DRV(%a2),%d0                    | send trim, Q8: 256 - DRV
        neg.l   %d0                               | (DRV 64 -2.5 dB, 127 -6 dB):
        addi.l  #256,%d0                          | a clipped voice is denser than
        move.l  %d0,SENDK(%a5)                    | a clean one at the same peak
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
        tst.l   TYPE(%a5)                         | RAT/OD: emphasis and pre-clip LP
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
        move.l  TYPE(%a5),%d1                     | OD's soft clip, the tone LP
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
        move.l  %d0,(%a1)+                        | for dist_fxout
        muls.l  SENDK(%a5),%d0                    | << 8 back to slot scale, trimmed
        move.l  %d0,(%a0)                         | for the sends
        lea     FRAME_SIZE(%a0),%a0
        subq.l  #1,%d2
        bne.w   2b
        move.l  REC(%sp),%a0                      | the state back
        moveq   #REC/4,%d1
24:     move.l  (%a5)+,(%a0)+
        subq.l  #1,%d1
        bne.s   24b
        move.l  REC(%sp),%a5
        lea     REC+4(%sp),%sp
        bra.s   9f

8:      lea     FRAMES*4(%a1),%a1
9:      lea     TRK_SIZE(%a2),%a2
        addq.l  #4,%a3                            | the next voice's slot
        lea     REC(%a5),%a5
        subq.l  #1,%d7
        bne.w   1b
        jmp     fx_block_body

        | ------------------------------------------------------------------
        | fx_block, after its output loop (a4 just past the 32 output pairs):
        | each track on the digital path adds its processed voice from
        | dist_cap to both output channels (centre), at
        |   out += (y >> 2) * LEV * 13 / 32   (y = the x-scale sample from
        | dist_fxin). Calibrated on hardware (the MK1): LEV ~100 matches the
        | same sound on the analog path, 127 = +2 dB over it. The displaced
        | store goes first; a0 and d1 must survive (stock stores them next).
        | ------------------------------------------------------------------
        .align  2
dist_fxout:
        move.l  %d0,FX_STATE4                     | displaced
        lea     -32(%sp),%sp
        movem.l %d1-%d4/%a0-%a3,(%sp)
        lea     dist_set,%a2
        lea     dist_cap,%a1
        moveq   #4,%d4                            | tracks left

1:      tst.b   F_DIG(%a2)
        beq.s   8f
        mvz.b   F_LEV(%a2),%d3                    | level
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
        movem.l (%sp),%d1-%d4/%a0-%a3
        lea     32(%sp),%sp
        jmp     fx_block_tail_resume

        | ==================================================================
        | Knob names
        | ==================================================================

        | ------------------------------------------------------------------
        | The parameter sets' name getters (set, id), at their entries
        | (0x4009e79e short, 0x4009e7c2 long; both `movel %sp@(8),%d0;
        | cmpil #295,%d0`): they return the record's name. The knob draw prints
        | the short name under each knob, and the encoder handler shows the
        | long one in the header while a knob turns. Asked from there (and only
        | from there), an id an ae_names entry names gets that name: the hidden
        | records the mods' pages use keep their own names everywhere else (an
        | LFO's destination list among them). d0/d1/a0/a1 are free, as for any
        | call.
        | ------------------------------------------------------------------
        .align  2
dist_sname:
        move.l  (%sp),%d0
        cmpi.l  #KNOB_NAME_CALL,%d0
        bne.s   9f
        clr.l   -(%sp)                            | dist_name_of(id, 0): short
        move.l  12(%sp),-(%sp)
        jsr     dist_name_of                      | (dist.c)
        addq.l  #8,%sp
        tst.l   %d0
        beq.s   9f
        rts
9:      move.l  8(%sp),%d0                        | displaced
        cmpi.l  #295,%d0                          | displaced
        jmp     short_name_resume

        .align  2
dist_lname:
        move.l  (%sp),%d0
        cmpi.l  #POPUP_NAME_CALL,%d0
        bne.s   9f
        pea     1                                 | dist_name_of(id, 1): long
        move.l  12(%sp),-(%sp)
        jsr     dist_name_of
        addq.l  #8,%sp
        tst.l   %d0
        beq.s   9f
        rts
9:      move.l  8(%sp),%d0                        | displaced
        cmpi.l  #295,%d0                          | displaced
        jmp     long_name_resume

        | ==================================================================
        | Data
        | ==================================================================
        .data
        .globl  dist_set, dist_sld
        .align  2
dist_set:   .space  28                            | 6 x 4 settings, then 4 CHR
        | For slide (a weak import there): byte 0 says dist is in the build,
        | bytes 1..4 are the synth tracks' SLD. The tick keeps them.
dist_sld:   .byte   1, 0, 0, 0, 0
        .align  2

        .bss
        .align  2
dist_cap:   .space  4 * FRAMES * 4                | the processed tracks, a block
dist_hold:  .space  4 * REC                       | their DSP state
