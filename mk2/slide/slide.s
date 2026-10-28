        | SPDX-License-Identifier: MIT
        | slide - AE 0002 (303 slide) for the Analog Four MKII, OS 1.56, as an
        | elekloader elemod on core-a4.
        |
        | Two hooks in the trig routine (0x4007a1d2, args track/pattern/step).
        | Here d2 = step, a5 = track, a2 = the pattern's base, a3 = track * 945,
        | and d3 = the step's trig flags, which become the trig event's flags
        | (bit 4 = note slide).
        |
        | How stock slides: while playing a note it looks ahead to the next trig;
        | if that trig carries the slide flag and this note's LEN reaches it,
        | the next step is stored as the track's legato target. When the target
        | plays with its slide flag, stock clears the envelope retrigger bits:
        | the note glides, legato.
        |
        | With the track's slide mode on, the slide trig is read one note earlier:
        |   slide_gate (after LEN is resolved):
        |   - slide FROM: this note's slide flag (bit 4 of d3) is replaced by
        |     the previous trig's;
        |   - tie: if THIS step carries the slide flag, its LEN is raised to
        |     reach the next trig plus a quarter step;
        |   look_gate (the look-ahead's "does the next trig slide?" test):
        |   - asks "does THIS step slide?" instead, so the next trig becomes the
        |     legato target and keeps its envelope going.
        |
        | The mode is SLD on dist's DIST page, per track and kept with the kit.
        | Without dist every synth track slides the 303 way. dist_sld is dist's
        | (a weak import, so all zeros without it): byte 0 non-zero when dist is
        | in the build, bytes 1..4 the four synth tracks' SLD.
        |
        | The code is the image port's (MK2-OS-1.56, mods/0002-slide-303).

        | OS 1.56 addresses (re/symbols.toml on the MK2-OS-1.56 branch)
        .equ    slide_resume, 0x4007a494
        .equ    look_resume,  0x4007a7f8
        .equ    look_slide,   0x4007a804
        .equ    look_none,    0x4007a874

        .equ    SLIDE_BIT,    4
        .equ    TRIG_BITS,    3
        .equ    STEP_TICKS,   2700000              | LEN 14 ("1/16") = one step
        .equ    OVERLAP,      675000               | a quarter step
        .equ    LEN_TICKS,    0x40218384           | ticks(LEN) = LEN_TICKS[LEN + 1]
                                                   | (MK1: 0x401f1c34)
        .equ    LEN_MAX,      126                  | 127 is INF
        .equ    PAT_LEN_MODE, 93900                | pattern byte: per-track lengths?
        .equ    PAT_LEN,      93894                | pattern length (word)
        .equ    TRK_LEN,      453                  | track length (word), per-track mode
        .equ    MAX_STEPS,    64

        .text
        .globl  slide_gate, slide_look

        .align  2
slide_gate:
        lea     -32(%sp),%sp
        movem.l %d0-%d1/%d4/%d6-%d7/%a0-%a1/%a4,(%sp)
        jbsr    sld_on
        beq.w   99f

        lea     (%a2,%a3.l),%a0                   | the track's pattern data
        move.l  #PAT_LEN_MODE,%d0                 | the track length, as stock
        tst.b   (%a2,%d0.l)                       | reads it
        beq.s   1f
        mvs.w   TRK_LEN(%a0),%d6
        bra.s   2f
1:      move.l  #PAT_LEN,%d0
        mvs.w   (%a2,%d0.l),%d6
2:      moveq   #2,%d0
        cmp.l   %d0,%d6
        blt.w   99f
        moveq   #MAX_STEPS,%d0
        cmp.l   %d0,%d6
        ble.s   3f
        move.l  %d0,%d6                           | length

        | slide from the previous trig
3:      move.l  %d2,%d7
        move.l  %d6,%d4
        subq.l  #1,%d4                            | steps to look at
4:      subq.l  #1,%d7
        bpl.s   5f
        add.l   %d6,%d7                           | wrap
5:      move.w  (%a0,%d7.l*2),%d0
        moveq   #TRIG_BITS,%d1
        and.l   %d0,%d1
        bne.s   6f
        subq.l  #1,%d4
        bne.s   4b
        moveq   #0,%d0                            | no other trig: no slide in
6:      bclr    #SLIDE_BIT,%d3
        btst    #SLIDE_BIT,%d0
        beq.s   7f
        bset    #SLIDE_BIT,%d3

        | tie this note into the next trig if it is the one sliding out
7:      move.w  (%a0,%d2.l*2),%d0
        btst    #SLIDE_BIT,%d0
        beq.s   99f
        move.l  %d2,%d7
        moveq   #1,%d1                            | distance in steps
        move.l  %d6,%d4
        subq.l  #1,%d4
8:      addq.l  #1,%d7
        cmp.l   %d6,%d7
        blt.s   9f
        sub.l   %d6,%d7                           | wrap
9:      move.w  (%a0,%d7.l*2),%d0
        andi.l  #TRIG_BITS,%d0
        bne.s   10f
        addq.l  #1,%d1
        subq.l  #1,%d4
        bne.s   8b
        bra.s   99f                               | no other trig: leave LEN alone
10:     move.l  #STEP_TICKS,%d0
        muls.l  %d1,%d0
        addi.l  #OVERLAP,%d0                      | ticks needed
        lea     LEN_TICKS+4,%a1
        moveq   #0,%d4                            | LEN
11:     cmp.l   (%a1)+,%d0
        bls.s   12f
        addq.l  #1,%d4
        moveq   #LEN_MAX,%d1
        cmp.l   %d1,%d4
        ble.s   11b
        move.l  %d1,%d4
12:     move.l  %d4,116(%sp)                      | LEN: the host's %sp@(84) + 32

99:     movem.l (%sp),%d0-%d1/%d4/%d6-%d7/%a0-%a1/%a4
        lea     32(%sp),%sp
        lea     (%a2,%a3.l),%a0                   | displaced
        tst.b   458(%a0)                          | displaced (its flags are used)
        jmp     slide_resume

        | The look-ahead, d0 = the next trig's step. Stock goes on with
        | `movea.w (%a0,%a2.l),%a1` (the next trig's flags), tests bit 4 and
        | branches to look_none (no legato target) if clear, else continues at
        | look_slide. d6, d7, a0 and a1 are all reloaded by stock after this.
        .align  2
slide_look:
        lea     (%a3,%d0.l*2),%a0                 | displaced
        moveq   #16,%d6                           | displaced
        jbsr    sld_on
        bne.s   1f
        jmp     look_resume                       | stock: the next trig decides
1:      movea.w (%a0,%a2.l),%a1                   | the next trig's flags, as stock
        lea     (%a3,%d2.l*2),%a0
        move.w  (%a0,%a2.l),%d7                   | this step's
        btst    #SLIDE_BIT,%d7
        bne.s   2f
        jmp     look_none
2:      jmp     look_slide

        | sld_on: Z clear if track a5 is a synth track whose slide mode is on
        | (always, without dist). Uses d7 and a1 only.
        .align  2
sld_on:
        move.l  %a5,%d7
        cmpi.l  #3,%d7
        bhi.s   9f
        lea     dist_sld,%a1
        tst.b   (%a1)
        beq.s   8f                                | no dist: every synth track
        tst.b   1(%a1,%d7.l)
        rts
8:      moveq   #1,%d7                            | Z clear
        rts
9:      moveq   #0,%d7                            | Z set
        rts
