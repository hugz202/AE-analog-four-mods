        | SPDX-License-Identifier: MIT
        | rand-track - AE 0011 (random track) for the Analog Four MKII, OS 1.56,
        | as an elekloader elemod on core-a4mk2.
        |
        | Hold a track key and press YES: the track is copied (for the undo),
        | cleared (stock CLEAR TRACK) and filled over its length with a random
        | line. Hold the track key and press LEFT: the copy goes back.
        |
        | One hook, in the panel key handler 0x400c8b90 (the MK1's 0x400c4348;
        | d2 = the event, a2 = the view). Its first call reads the key code
        | (`jsr key_code` at 0x400c8ba2, the event pushed): rnd_gate makes that
        | call itself, and for YES or LEFT pressed while a track key is held
        | (held_tracks: the mask stock's own TRACK + UP / DOWN transpose tests)
        | runs rnd_action and leaves through the handler's own handled exit
        | (`moveq #1,%d3`, then the epilogue, which restores from %fp). Anything
        | else resumes stock with the key code in d0. In this handler YES (0x44)
        | and LEFT (0x40) fall to the default case, so stock gives TRACK + YES
        | and TRACK + LEFT no meaning here.
        |
        | rnd_action works on the current track (the one the held key
        | selected), as stock's COPY / PASTE / CLEAR TRACK do:
        |   YES   a copy of the track (its data and its lock area, what stock's
        |         own clear keeps for UNDO CLEAR) into rnd_snap, stock CLEAR
        |         TRACK (track_clear(tp, 1)), then over the track's length a
        |         trig on about 62 % of the steps (the first always), about 25 %
        |         of them accented and 18 % slid, and a note in KEY NOTE + KEY
        |         SCALE (pentatonic minor when KEY SCALE is OFF) around the
        |         track's default note: the root 5/16, its octave 2/16, the fifth
        |         (if in the scale) 2/16, else any scale note within -12 .. +11.
        |         Flags go through stock's setter (trig_flag_set: 0x01 trig, 0x08
        |         accent, 0x10 note slide); the note is the step's NOTE byte.
        |   LEFT  that copy back, as stock's UNDO CLEAR restores its own (stock's
        |         undo cannot be used: any edit after the clear cancels it, and
        |         the random line is such an edit), if the copy is this track's.
        | The FX track (no notes) is left alone. A pop-up says what happened,
        | built as stock's CLEAR TRACK builds its own.
        |
        | KEY SCALE 3..35 are scale-lock's; without scale-lock the menu stops at
        | MIN and only OFF / MAJ / MIN occur. With slide in the build the slide
        | trigs play the 303 way. No storage, no settings.
        |
        | The code is the MK1's (AE-analog-four-mods OS-1.56, mods/0011-rand-
        | track); the differences: the addresses, the undo copy in this mod's
        | .bss in place of free DDR, and one text section in place of caves.
        | Calls follow the stock ABI: d0/d1/a0/a1 are scratch.

        | OS 1.56 MKII addresses, traced in the MKII image (MK1 in brackets)
        .equ    key_code,              0x4005b6f0  | (0x40059948) event +12
        .equ    key_is_press,          0x4005b75e  | (0x400599b6) event +16 bit 0
        .equ    held_tracks,           0x40022014  | (0x40021d34) (view + 108)
        .equ    key_resume,            0x400c8ba8  | (0x400c4360)
        .equ    key_handled,           0x400c8f6a  | (0x400c4722) moveq #1,%d3
        .equ    track_index_of,        0x400adbd2  | (0x400aab78)
        .equ    current_track_pattern, 0x400a5f80  | (0x400a2fb8)
        .equ    track_clear,           0x400b9666  | (0x400b6562)
        .equ    trig_flag_set,         0x400b71aa  | (0x400b40a6)
        .equ    step_lock_prep,        0x400b528e  | (0x400b218a)
        .equ    memcpy,                0x40077fa0  | (0x40075ab8)
        .equ    scale_table,           0x4019fadc  | (0x40181d80)
        .equ    str_from_cstr2,        0x4014c84c  | (0x40131bfe)
        .equ    str_convert,           0x4014c122  | (0x401314d4)
        .equ    show_popup,            0x40061b5c  | (0x4005fcb8)
        .equ    str_dtor,              0x40144764  | (0x40129b16)
        .equ    block_counter,         0x41864b1c  | (0x415c00b0) fx_block's first read

        .equ    KEY_YES,    0x44
        .equ    KEY_LEFT,   0x40
        .equ    TRK_BYTES,  945                   | one track's data in a pattern
        .equ    STEP_NOTE,  128                   | + step: the step's NOTE
        .equ    DEF_NOTE,   0x1c0                 | the track's default NOTE
        .equ    KEY_NOTE,   0x1c8                 | NOTE SETUP's KEY NOTE (0..11)
        .equ    KEY_SCALE,  0x1c9                 | and KEY SCALE (0 OFF, 1..35)
        .equ    TRK_LEN,    453                   | the track's own length (word)
        .equ    PAT_LEN,    93894                 | the pattern's length (word)
        .equ    PAT_PERTRK, 93900                 | 1: per-track lengths
        .equ    ROW_BYTES,  13                    | scale_table: degree + 1 per interval
        .equ    SCALE_MAX,  35
        .equ    PNMI_ROW,   7                     | pentatonic minor (KEY SCALE OFF)
        .equ    F_TRIG,     0x01
        .equ    F_ACC,      0x08
        .equ    F_SLIDE,    0x10
        .equ    P_TRIG,     160                   | of 256: trig density
        .equ    P_ACC,      64                    | accent (of the trigs)
        .equ    P_SLIDE,    46                    | slide (of the trigs)
        .equ    MAGIC,      0x52414e44            | "RAND"
        .equ    LOCK_BYTES, 14704                 | a track's lock area (stock: 0x3970)
        .equ    STEP_LOCKS, 228                   | per step

        .text
        .globl  rnd_gate

        | ------------------------------------------------------------------
        | The key handler's key-code read (`jsr key_code`, the event pushed).
        | ------------------------------------------------------------------
        .align  2
rnd_gate:
        jsr     key_code                          | displaced: d0 = the key
        moveq   #KEY_YES,%d1
        cmp.l   %d1,%d0
        beq.s   1f
        moveq   #KEY_LEFT,%d1
        cmp.l   %d1,%d0
        bne.s   9f
1:      move.l  %d0,-(%sp)                        | the key
        move.l  %d2,-(%sp)
        jsr     key_is_press
        addq.l  #4,%sp
        tst.b   %d0
        beq.s   8f
        move.l  108(%a2),-(%sp)
        jsr     held_tracks
        addq.l  #4,%sp
        tst.l   %d0
        beq.s   8f
        move.l  %a2,-(%sp)                        | rnd_action(view, key)
        jsr     rnd_action
        jmp     key_handled                       | (unlk drops what is pushed)
8:      move.l  (%sp)+,%d0                        | not ours: the key back
9:      jmp     key_resume

        | ------------------------------------------------------------------
        | rnd_action(view, key)
        | ------------------------------------------------------------------
        .align  2
rnd_action:
        link    %fp,#-28
        lea     -40(%sp),%sp
        movem.l %d2-%d7/%a2-%a5,(%sp)
        move.l  8(%fp),%a2                        | the view
        move.l  104(%a2),%a0
        pea     48(%a0)
        jsr     track_index_of
        addq.l  #4,%sp
        move.l  %d0,%d7                           | t
        moveq   #4,%d1                            | the FX track: nothing
        cmp.l   %d1,%d0
        beq.w   rnd_exit
        moveq   #5,%d1
        cmp.l   %d1,%d0
        bhi.w   rnd_exit
        move.l  104(%a2),-(%sp)
        jsr     current_track_pattern
        addq.l  #4,%sp
        move.l  %d0,%a3                           | tp
        tst.l   %d0
        beq.w   rnd_exit
        moveq   #KEY_LEFT,%d0
        cmp.l   12(%fp),%d0
        beq.w   rnd_undo

        | ---- generate
        bsr.w   snap_take                         | our undo copy first
        pea     1
        move.l  %a3,-(%sp)
        jsr     track_clear                       | stock CLEAR TRACK
        addq.l  #8,%sp
        tst.b   %d0
        beq.w   rnd_exit

        | ---- setup: a4 the track's data, a5 the scale row, d6 the length,
        | d4 the root note
        bsr.w   track_data
        tst.l   %d0
        beq.w   rnd_exit
        move.l  %d0,%a4
        move.l  %d7,%d0                           | the pattern's data: a4 - 945 t
        mulu.w  #TRK_BYTES,%d0
        move.l  %a4,%a5
        sub.l   %d0,%a5
        move.l  #PAT_PERTRK,%d0                   | the length: the track's own, or
        mvs.b   (%a5,%d0.l),%d0                   | the pattern's
        moveq   #1,%d1
        cmp.l   %d1,%d0
        bne.s   1f
        mvs.w   TRK_LEN(%a4),%d6
        bra.s   2f
1:      move.l  #PAT_LEN,%d0
        mvs.w   (%a5,%d0.l),%d6
2:      moveq   #1,%d0
        cmp.l   %d0,%d6
        bge.s   3f
        move.l  %d0,%d6
3:      moveq   #64,%d0
        cmp.l   %d0,%d6
        ble.s   4f
        move.l  %d0,%d6                           | d6 = the length, 1..64
4:      moveq   #PNMI_ROW,%d0                     | the scale row
        mvs.b   KEY_SCALE(%a4),%d1
        ble.s   5f
        moveq   #SCALE_MAX,%d2
        cmp.l   %d2,%d1
        bgt.s   5f
        lea     scale_remap,%a0
        mvz.b   (%a0,%d1.l),%d0
5:      mulu.w  #ROW_BYTES,%d0
        lea     scale_table,%a5
        add.l   %d0,%a5                           | a5 = the row
        mvz.b   KEY_NOTE(%a4),%d5                 | the key, 0..11
        moveq   #12,%d0
        cmp.l   %d0,%d5
        bcs.s   6f
        moveq   #0,%d5
6:      mvz.b   DEF_NOTE(%a4),%d4                 | the root at or below the
        move.l  %d4,%d0                           | track's default note
        sub.l   %d5,%d0
        addi.l  #120,%d0                          | (>= 0) mod 12
        moveq   #12,%d1
7:      cmp.l   %d1,%d0
        bcs.s   8f
        sub.l   %d1,%d0
        bra.s   7b
8:      sub.l   %d0,%d4                           | d4 = the root note
        bsr.w   rng_seed

        | ---- the steps
        moveq   #0,%d3                            | the step
10:     bsr.w   rng
        tst.l   %d3
        beq.s   11f                               | the first step always
        moveq   #0,%d1
        move.b  %d0,%d1
        cmpi.l  #P_TRIG,%d1
        bcc.w   19f
11:     move.l  %d0,%d2                           | the draw, for accent and slide
        moveq   #F_TRIG,%d0                       | (the flags first: setting the
        bsr.w   set_flag                          | trig resets the step's note)
        move.l  %d2,%d1
        lsr.l   #8,%d1
        andi.l  #255,%d1
        cmpi.l  #P_ACC,%d1
        bcc.s   12f
        moveq   #F_ACC,%d0
        bsr.w   set_flag
12:     move.l  %d2,%d1
        swap    %d1
        andi.l  #255,%d1
        cmpi.l  #P_SLIDE,%d1
        bcc.s   18f
        moveq   #F_SLIDE,%d0
        bsr.w   set_flag
18:     bsr.w   pick_note                         | then the note (a5 row, d4 root)
        lea     STEP_NOTE(%a4),%a0
        move.b  %d0,(%a0,%d3.l)
19:     addq.l  #1,%d3
        cmp.l   %d6,%d3
        blt.s   10b
        lea     s_rand,%a0
        bra.s   rnd_end

rnd_undo:
        bsr.w   snap_restore                      | our copy back
        tst.l   %d0
        beq.s   rnd_exit
        lea     s_undo,%a0
rnd_end:
        bsr.w   rnd_popup                         | (as stock's CLEAR TRACK makes it)
rnd_exit:
        movem.l (%sp),%d2-%d7/%a2-%a5
        lea     40(%sp),%sp
        unlk    %fp
        rts

        | set_flag(d0 = the mask): trig_flag_set(tp, step, mask, 1). d3 = step,
        | a3 = tp.
        .align  2
set_flag:
        pea     1
        move.l  %d0,-(%sp)
        move.l  %d3,-(%sp)
        move.l  %a3,-(%sp)
        jsr     trig_flag_set
        lea     16(%sp),%sp
        rts

        | rnd_popup(a0 = the text): the view in a2, inside rnd_action's frame
        | (fp - 4 .. - 16 free, as stock's).
        .align  2
rnd_popup:
        move.l  %a3,-(%sp)
        lea     -8(%fp),%a3
        move.l  %a0,-(%sp)
        move.l  %a3,%a0
        jsr     str_from_cstr2
        move.l  %a3,-(%sp)
        lea     -16(%fp),%a3
        move.l  %a3,-(%sp)
        jsr     str_convert
        clr.l   -(%sp)
        move.l  %a3,-(%sp)
        move.l  %a2,-(%sp)
        jsr     show_popup
        pea     -12(%fp)
        lea     str_dtor,%a3
        jsr     (%a3)
        pea     -4(%fp)
        jsr     (%a3)
        lea     32(%sp),%sp
        move.l  (%sp)+,%a3
        rts

        | pick_note(a5 = the scale row, d4 = the root note) -> d0 = a MIDI note
        | in the scale: the root 5/16, its octave 2/16, the fifth (if the row has
        | it) 2/16, else a scale note between root - 12 and root + 11. d1 used.
        .align  2
pick_note:
        move.l  %d2,-(%sp)
        bsr.w   rng
        move.l  %d0,%d2
        moveq   #15,%d1
        and.l   %d2,%d1
        moveq   #5,%d0
        cmp.l   %d0,%d1
        bcs.s   1f                                | 0..4: the root
        moveq   #7,%d0
        cmp.l   %d0,%d1
        bcs.s   2f                                | 5, 6: the octave
        moveq   #9,%d0
        cmp.l   %d0,%d1
        bcc.s   3f
        tst.b   7(%a5)                            | 7, 8: the fifth, if in the scale
        beq.s   3f
        moveq   #7,%d0
        bra.s   4f
1:      moveq   #0,%d0
        bra.s   4f
2:      moveq   #12,%d0
        bra.s   4f
3:      lsr.l   #8,%d2                            | any scale degree: a random
        moveq   #0,%d0                            | interval, walked up to the
        move.b  %d2,%d0                           | next one in the row
        mulu.w  #12,%d0
        lsr.l   #8,%d0                            | 0..11
        moveq   #12,%d1
5:      tst.b   (%a5,%d0.l)
        bne.s   6f
        addq.l  #1,%d0
        cmpi.l  #12,%d0
        bcs.s   7f
        moveq   #0,%d0
7:      subq.l  #1,%d1
        bne.s   5b
6:      btst    #16,%d2                           | half of them an octave down
        beq.s   4f                                | (the draw's next bits)
        subi.l  #12,%d0
4:      add.l   %d4,%d0
        bpl.s   8f
        addi.l  #12,%d0
8:      cmpi.l  #127,%d0
        ble.s   9f
        subi.l  #12,%d0
9:      move.l  (%sp)+,%d2
        rts

        | rng_seed(): mixes the audio block counter into the state. rng() -> d0:
        | xorshift32. d1 used.
        .align  2
rng_seed:
        move.l  rng_state,%d0
        move.l  block_counter,%d1
        swap    %d1
        eor.l   %d1,%d0
        bne.s   1f
        move.l  #0x2545f491,%d0
1:      move.l  %d0,rng_state
        rts

        .align  2
rng:
        move.l  rng_state,%d0
        move.l  %d0,%d1
        lsl.l   #8,%d1                            | x ^= x << 13
        lsl.l   #5,%d1
        eor.l   %d1,%d0
        move.l  %d0,%d1                           | x ^= x >> 17
        swap    %d1
        andi.l  #0xffff,%d1
        lsr.l   #1,%d1
        eor.l   %d1,%d0
        move.l  %d0,%d1                           | x ^= x << 5
        lsl.l   #5,%d1
        eor.l   %d1,%d0
        move.l  %d0,rng_state
        rts

        | track_data(a3 = tp) -> d0 = the track's data (its vtable +40), 0 if none.
        .align  2
track_data:
        move.l  (%a3),%a0
        move.l  40(%a0),%a0
        move.l  %a3,-(%sp)
        jsr     (%a0)
        addq.l  #4,%sp
        rts

        | lock_area(a3 = tp) -> d0 = its lock area (the lock object's storage +
        | tp[72] * LOCK_BYTES, as stock's clear finds it), 0 if none.
        .align  2
lock_area:
        move.l  44(%a3),%d0
        beq.s   9f
        move.l  %d0,%a0
        move.l  (%a0),%a1
        move.l  %a0,-(%sp)
        move.l  40(%a1),%a1
        jsr     (%a1)
        addq.l  #4,%sp
        tst.l   %d0
        beq.s   9f
        move.l  72(%a3),%d1
        bmi.s   8f
        move.l  %d2,-(%sp)
        move.l  #LOCK_BYTES,%d2
        mulu.l  %d2,%d1
        move.l  (%sp)+,%d2
        add.l   %d1,%d0
        rts
8:      moveq   #0,%d0
9:      rts

        | snap_take(a3 = tp): the track's data and lock area into rnd_snap,
        | tagged.
        .align  2
snap_take:
        clr.l   snap_magic                        | invalid while it is written
        bsr.w   track_data
        tst.l   %d0
        beq.s   9f
        pea     TRK_BYTES
        move.l  %d0,-(%sp)
        pea     snap_data
        jsr     memcpy
        lea     12(%sp),%sp
        bsr.w   lock_area
        tst.l   %d0
        beq.s   9f
        move.l  #LOCK_BYTES,-(%sp)
        move.l  %d0,-(%sp)
        pea     snap_lock
        jsr     memcpy
        lea     12(%sp),%sp
        move.l  %a3,snap_tp
        move.l  #MAGIC,%d0
        move.l  %d0,snap_magic
9:      rts

        | snap_restore(a3 = tp) -> d0 = 1 if the copy was this track's and is
        | back: the data, then per step stock's lock helper and that step's
        | locks, then the two notifications - stock UNDO CLEAR's sequence
        | (0x400b8656).
        .align  2
snap_restore:
        move.l  snap_magic,%d0
        cmpi.l  #MAGIC,%d0
        bne.w   8f
        cmpa.l  snap_tp,%a3
        bne.w   8f
        lea     -8(%sp),%sp
        movem.l %d2-%d3,(%sp)
        bsr.w   track_data
        tst.l   %d0
        beq.w   7f
        pea     TRK_BYTES
        pea     snap_data
        move.l  %d0,-(%sp)
        jsr     memcpy
        lea     12(%sp),%sp
        bsr.w   lock_area
        move.l  %d0,%d3                           | the lock area
        beq.s   6f
        moveq   #0,%d2                            | the step
1:      move.l  %d2,-(%sp)
        move.l  %a3,-(%sp)
        jsr     step_lock_prep
        addq.l  #8,%sp
        pea     STEP_LOCKS
        move.l  %d2,%d0
        mulu.w  #STEP_LOCKS,%d0
        lea     snap_lock,%a0
        pea     (%a0,%d0.l)
        add.l   %d3,%d0
        move.l  %d0,-(%sp)
        jsr     memcpy
        lea     12(%sp),%sp
        addq.l  #1,%d2
        moveq   #64,%d0
        cmp.l   %d0,%d2
        bne.s   1b
6:      move.l  (%a3),%a0                         | the notifications
        clr.l   -(%sp)
        move.l  %a3,-(%sp)
        move.l  16(%a0),%a0
        jsr     (%a0)
        addq.l  #8,%sp
        move.l  44(%a3),%d0
        beq.s   5f
        move.l  %d0,%a0
        move.l  (%a0),%a1
        clr.l   -(%sp)
        move.l  %a0,-(%sp)
        move.l  16(%a1),%a1
        jsr     (%a1)
        addq.l  #8,%sp
5:      moveq   #1,%d0
        bra.s   3f
7:      moveq   #0,%d0                            | no track data
3:      movem.l (%sp),%d2-%d3
        lea     8(%sp),%sp
        rts
8:      moveq   #0,%d0                            | no copy for this track
        rts

        | KEY SCALE value -> scale_table row (scale-lock's table: 1 MAJ and 2 MIN
        | keep their stock meaning, then the modes, then the rest of the library).
scale_remap:
        .byte   0
        .byte   0, 5
        .byte   1, 2, 3, 4, 6
        .byte   7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20
        .byte   21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34

s_rand: .asciz  "RANDOM TRACK"
s_undo: .asciz  "RANDOM UNDONE"

        .data
        .align  2
rng_state:  .long   0x2545f491

        .bss
        .align  4
snap_magic: .space  4                             | MAGIC when the copy is valid
snap_tp:    .space  4                             | the track pattern it belongs to
snap_data:  .space  948                           | its data, 945 B
snap_lock:  .space  LOCK_BYTES                    | its lock area
