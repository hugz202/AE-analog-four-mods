        | SPDX-License-Identifier: MIT
        | scale-lock - AE 0001 (scale lock) for the Analog Four MKII, OS 1.56, as an
        | elekloader elemod on core-a4 0.2.
        |
        | The track's KEY SCALE (NOTE SETUP, TrackPattern +0x1c9) grows from
        | OFF/MAJ/MIN to OFF + 35 scales, and anything but OFF locks the active
        | track's notes to KEY NOTE + KEY SCALE: played notes and hold-a-trig
        | step entry are snapped, and the NOTE encoder steps through the scale -
        | the track's note and held trigs' locks alike. The scale data is stock:
        | 1.56 links Elektron's scale library (scale_table, scale_short_names)
        | without ever calling it.
        |
        | The code is the image port's (MK2-OS-1.56, mods/0001-scale-lock), with
        | one move: core-a4 0.2 owns param_apply_delta's entry, so the NOTE
        | encoder's no-trig path is caught one step further in, at
        | 0x400232ea, after the prologue core's jump displaces (core resumes the
        | routine there).
        |
        | Calls follow the stock ABI: d0/d1/a0/a1 are scratch, the rest is saved.

        | OS 1.56 addresses (re/symbols.toml on the MK2-OS-1.56 branch)
        .equ    project_singleton,     0x401494de
        .equ    current_track_pattern, 0x400a5f80
        .equ    key_scale_get,         0x400b5a92
        .equ    key_note_get,          0x400b59f0
        .equ    key_scale_names,       0x401ac544
        .equ    scale_table,           0x4019fadc
        .equ    scale_short_names,     0x402148e4
        .equ    track_play_note_body,  0x400bce0e
        .equ    set_step_note_body,    0x400afa40
        .equ    param_apply_delta_mid, 0x400232f2  | after the two loads this site displaces
        .equ    key_scale_draw_resume, 0x400dbc92
        .equ    lock_delta_apply_body, 0x40023892
        .equ    lock_add_resume,       0x40023fb0

        .equ    PARAM_NOTE,  19
        .equ    VT_LOCK_GET, 0x70                 | the view's lock getter
        .equ    VT_PAGE_GET, 0x54                 | page_get_value's vtable slot
        .equ    SCALE_MAX,   35                   | KEY SCALE 1..35 lock
        .equ    ROW_BYTES,   13                   | scale_table row: intervals 0..12

        .text
        .globl  scale_lock_play, scale_lock_step, scale_lock_note_delta
        .globl  scale_lock_lock_delta, scale_lock_lock_add, scale_lock_name

        | ------------------------------------------------------------------
        | Played notes: track_play_note(view, raw, final, velocity), at its entry.
        |
        | Stack untouched: (%sp) return, 4 view, 8 raw, 12 final, 16 velocity.
        | Every note the track plays comes through here - the trig keys in
        | KEYBOARD mode (as key events) and incoming note events alike - and
        | live recording records what this function is given. `final` is the
        | absolute pitch (stock refuses it above 127), so it is snapped as is.
        | Note-off finds the held note by `raw` and releases the `final` stored
        | with it, so the snapped note is the one released, whatever the scale
        | is by then.
        | ------------------------------------------------------------------
        .align  2
scale_lock_play:
        lea     -8(%sp),%sp
        movem.l %d3-%d4,(%sp)
        bsr.w   track_lock
        beq.s   9f
        move.l  %d0,%a1                           | row
        move.l  20(%sp),%d3                       | final: 12 + 8 saved
        moveq   #127,%d0
        cmp.l   %d0,%d3
        bhi.s   9f                                | stock refuses it anyway
        bsr.w   snap                              | -> d4
        add.l   %d4,%d3
        moveq   #127,%d0
        cmp.l   %d0,%d3
        bhi.s   9f                                | snapped off either end: leave it
        move.l  %d3,20(%sp)
9:      movem.l (%sp),%d3-%d4
        lea     8(%sp),%sp
        link.w  %fp,#-88                          | displaced
        moveq   #127,%d0                          | displaced
        jmp     track_play_note_body

        | ------------------------------------------------------------------
        | Step entry: set_step_note(track, step, offset), at its entry.
        |
        | Stack untouched: (%sp) return, 4 track, 8 step, 12 offset. Hold a trig
        | and play a key: the keyboard handlers store final - 60 - KEY NOTE, an
        | offset from the key's root, so its degree is offset mod 12 and it is
        | snapped with a key of 0. Stock clamps the result to -36..36 after.
        | ------------------------------------------------------------------
        .align  2
scale_lock_step:
        lea     -8(%sp),%sp
        movem.l %d3-%d4,(%sp)
        bsr.w   track_lock
        beq.s   9f
        move.l  %d0,%a1                           | row
        moveq   #0,%d1                            | already relative to the key
        move.l  20(%sp),%d3                       | offset: 12 + 8 saved
        bsr.w   snap
        add.l   %d4,%d3
        move.l  %d3,20(%sp)
9:      movem.l (%sp),%d3-%d4
        lea     8(%sp),%sp
        lea     -16(%sp),%sp                      | displaced
        movem.l %d2-%d4/%a2,(%sp)                 | displaced
        jmp     set_step_note_body

        | ------------------------------------------------------------------
        | The NOTE encoder.
        |
        | A NOTE edit adds the encoder's delta (8.8) to a value in one of three
        | places, and each is caught where the delta meets the value:
        |
        | - no trig held: param_apply_delta, for the track's note;
        | - trigs held: lock_delta_apply, once per held trig, for its lock;
        | - one trig's lock edited directly: the add at 0x40023faa.
        |
        | The first two read the value the edit starts from and rewrite the delta
        | so that stock lands on note_step's answer, clamp, notification and all;
        | the third replaces the add. Other parameters, an unlocked track, or a
        | zero delta go to stock unchanged. FUNC is not tested: the lock applies
        | with or without it.
        | ------------------------------------------------------------------

        | param_apply_delta, after its prologue (core-a4 0.2 owns the entry and
        | resumes here): `moveal %sp@(16),%a2; movel %sp@(28),%d3`. Stock has
        | saved d2, d3 and a2. Stack: 0..11 the saved registers, 12 return,
        | 16 view, 20 id, 24 delta, 28 the FUNC-held flag, 32 outFlag.
        .align  2
scale_lock_note_delta:
        moveq   #PARAM_NOTE,%d0
        cmp.l   20(%sp),%d0
        bne.s   9f
        tst.l   24(%sp)
        beq.s   9f
        move.l  %d2,-(%sp)                        | view 20, id 24, delta 28 below
        moveq   #-1,%d0                           | page_get_value(view, NOTE, -1)
        move.l  %d0,-(%sp)
        moveq   #PARAM_NOTE,%d0
        move.l  %d0,-(%sp)
        move.l  28(%sp),%a0                       | view: 20 + 8 pushed
        move.l  %a0,-(%sp)
        move.l  (%a0),%a0
        move.l  VT_PAGE_GET(%a0),%a0
        jsr     (%a0)
        lea     12(%sp),%sp
        move.l  %d0,%d2                           | the value it starts from
        move.l  28(%sp),%d1                       | the delta
        bsr.w   note_step
        beq.s   8f                                | unlocked
        bsr.w   to_delta
        move.l  %d0,28(%sp)
8:      move.l  (%sp)+,%d2
9:      movea.l 16(%sp),%a2                       | displaced
        move.l  28(%sp),%d3                       | displaced
        jmp     param_apply_delta_mid

        | lock_delta_apply(view, step, id, delta), at its entry. Stack untouched:
        | (%sp) return, 4 view, 8 step, 12 id, 16 delta. Its caller has made sure
        | the step has a lock, so the lock is what the edit starts from.
        .align  2
scale_lock_lock_delta:
        moveq   #PARAM_NOTE,%d0
        cmp.l   12(%sp),%d0
        bne.s   9f
        tst.l   16(%sp)
        beq.s   9f
        move.l  %d2,-(%sp)                        | view 8, step 12, id 16, delta 20
        move.l  16(%sp),-(%sp)                    | id
        move.l  16(%sp),-(%sp)                    | step: 12 + 4
        move.l  16(%sp),%a0                       | view: 8 + 8
        move.l  %a0,-(%sp)
        move.l  (%a0),%a0
        move.l  VT_LOCK_GET(%a0),%a0
        jsr     (%a0)                             | the step's lock, < 0 if none
        lea     12(%sp),%sp
        tst.l   %d0
        bmi.s   8f
        move.l  %d0,%d2
        move.l  20(%sp),%d1                       | the delta
        bsr.w   note_step
        beq.s   8f
        bsr.w   to_delta
        move.l  %d0,20(%sp)
8:      move.l  (%sp)+,%d2
9:      lea     -16(%sp),%sp                      | displaced
        movem.l %d2-%d4/%a2,(%sp)                 | displaced
        jmp     lock_delta_apply_body

        | The held-trig routine's direct arm, at `lea %sp@(12),%sp; addl %d5,%d0`:
        | d0 the lock's value, d5 the delta, d4 the parameter id. The lea is
        | re-emitted and the add REIMPLEMENTED: for NOTE note_step gives the sum,
        | which is value + delta whenever the track is unlocked. d1/a0/a1 are free
        | here.
        .align  2
scale_lock_lock_add:
        lea     12(%sp),%sp                       | displaced
        moveq   #PARAM_NOTE,%d1
        cmp.l   %d4,%d1
        bne.s   8f
        move.l  %d5,%d1
        bsr.w   note_step
        jmp     lock_add_resume
8:      add.l   %d5,%d0                           | the stock add
        jmp     lock_add_resume

        | ------------------------------------------------------------------
        | note_step(d0 = value, d1 = delta, 8.8) -> d0 = new value
        |
        | Whole steps are delta / 256, and a nonzero delta smaller than that is
        | still one step, so no encoder resolution can stall it. Each step walks
        | to the next in-scale note in the delta's direction; past 0 or 127 it
        | stays on the last in-scale note reached. The value is 8.8, as stored;
        | 1..127 is taken as a plain note. Returns d1 = 1 and Z clear when the
        | track is locked; otherwise d0 = value + delta, d1 = 0, Z set.
        | Clobbers d0/d1/a0/a1.
        | ------------------------------------------------------------------
        .align  2
note_step:
        lea     -24(%sp),%sp
        movem.l %d2-%d6/%a2,(%sp)
        move.l  %d0,%d5                           | value
        move.l  %d1,%d2                           | delta
        beq.s   8f
        bsr.w   track_lock
        beq.s   8f
        move.l  %d0,%a2                           | row
        move.l  %d1,%d3                           | key
        moveq   #1,%d4                            | 8.8
        moveq   #127,%d0
        cmp.l   %d0,%d5
        bgt.s   1f
        tst.l   %d5
        beq.s   1f
        moveq   #0,%d4                            | 1..127: a plain note
        bra.s   2f
1:      asr.l   #8,%d5
2:      tst.l   %d5
        bpl.s   3f
        moveq   #0,%d5
3:      move.l  %d2,%d0                           | steps from the delta
        asr.l   #8,%d0
        bne.s   4f
        moveq   #1,%d0
        tst.l   %d2
        bpl.s   4f
        moveq   #-1,%d0
4:      move.l  %d0,%d2                           | steps left, signed
        move.l  %d5,%d6                           | the last in-scale note reached

5:      tst.l   %d2
        beq.s   7f
        bmi.s   55f
        subq.l  #1,%d2                            | one step up
51:     addq.l  #1,%d5
        moveq   #127,%d0
        cmp.l   %d0,%d5
        bgt.s   7f
        move.l  %d5,%d0
        bsr.w   in_lock
        beq.s   51b
        move.l  %d5,%d6
        bra.s   5b
55:     addq.l  #1,%d2                            | one step down
56:     subq.l  #1,%d5
        bmi.s   7f
        move.l  %d5,%d0
        bsr.w   in_lock
        beq.s   56b
        move.l  %d5,%d6
        bra.s   5b

7:      move.l  %d6,%d0
        tst.l   %d4
        beq.s   71f
        lsl.l   #8,%d0
71:     moveq   #1,%d1
        bra.s   9f
8:      move.l  %d5,%d0
        add.l   %d2,%d0
        moveq   #0,%d1
9:      movem.l (%sp),%d2-%d6/%a2
        lea     24(%sp),%sp
        tst.l   %d1
        rts

        | to_delta(d0 = new value, d2 = old value) -> d0 = the 8.8 delta between
        | them: a plain-note value (1..127) differs in whole notes, shifted up.
        .align  2
to_delta:
        sub.l   %d2,%d0
        moveq   #127,%d1
        cmp.l   %d1,%d2
        bgt.s   1f
        tst.l   %d2
        beq.s   1f
        lsl.l   #8,%d0
1:      rts

        | in_lock(d0 = note) for note_step: key in d3, row in a2.
        .align  2
in_lock:
        move.l  %d3,%d1
        move.l  %a2,%a1
        | falls through

        | ------------------------------------------------------------------
        | in_row(d0 = note, d1 = key, a1 = row) -> d0 = row[(note - key) mod 12]
        |
        | Non-zero (the degree + 1) when the note is in the scale; flags set from
        | d0. Clobbers d0 only.
        | ------------------------------------------------------------------
in_row:
        sub.l   %d1,%d0
1:      tst.l   %d0
        bpl.s   2f
        addi.l  #12,%d0
        bra.s   1b
2:      cmpi.l  #12,%d0
        blt.s   3f
        subi.l  #12,%d0
        bra.s   2b
3:      mvz.b   (%a1,%d0.l),%d0
        tst.l   %d0
        rts

        | ------------------------------------------------------------------
        | snap(d3 = note, d1 = key, a1 = row) -> d4 = correction
        |
        | The first of 0, -1, +1, -2, +2 that lands in the scale - the order
        | stock's own scale_quantize tries. No scale in the table has a gap of
        | more than four semitones, so one always does; 0 if not. Clobbers d0/a0.
        | ------------------------------------------------------------------
        .align  2
snap:
        lea     snap_offsets,%a0
1:      mvs.b   (%a0)+,%d4
        move.l  %d3,%d0
        add.l   %d4,%d0
        bsr.s   in_row
        bne.s   2f
        cmpa.l  #snap_offsets_end,%a0
        bne.s   1b
        moveq   #0,%d4
2:      rts

        | ------------------------------------------------------------------
        | track_lock() -> d0 = the active track's scale row, or 0 if unlocked,
        |                 d1 = its KEY NOTE (0..11); flags set from d0
        |
        | The route every NOTE SETUP thunk takes: project_singleton, then
        | current_track_pattern, whose accessor both getters take.
        | ------------------------------------------------------------------
        .align  2
track_lock:
        jsr     project_singleton
        move.l  %d0,-(%sp)
        jsr     current_track_pattern
        move.l  %d0,(%sp)                         | the accessor, for both getters
        jsr     key_scale_get                     | signed byte
        moveq   #SCALE_MAX,%d1
        cmp.l   %d1,%d0
        bhi.s   8f                                | OFF (0 is caught below), or junk
        tst.l   %d0
        beq.s   8f
        lea     scale_remap,%a0
        mvz.b   (%a0,%d0.l),%d0                   | library row
        moveq   #ROW_BYTES,%d1
        mulu.w  %d1,%d0
        addi.l  #scale_table,%d0
        move.l  %d0,-(%sp)                        | the row, across the call
        move.l  4(%sp),-(%sp)                     | the accessor again, as the argument
        jsr     key_note_get
        addq.l  #4,%sp
        move.l  %d0,%d1
        move.l  (%sp)+,%d0
        addq.l  #4,%sp
        tst.l   %d0
        rts
8:      addq.l  #4,%sp
        moveq   #0,%d0
        rts

        | ------------------------------------------------------------------
        | The KEY SCALE value text (NOTE SETUP).
        |
        | Reached by a jmp over `moveal %fp@(20),%a0; movel %fp@(-12,%d0:l:4),%sp@-`
        | with d0 = the value. Stock indexes a 3-entry stack copy of OFF/MAJ/MIN;
        | 1 and 2 keep those names, 3..35 show the library's short name for their
        | row (CHRO is name 0, so a row's name is one further on). d1 and a1 are
        | free until the draw call; a0 is reloaded here as stock does.
        | ------------------------------------------------------------------
        .align  2
scale_lock_name:
        tst.l   %d0
        ble.s   1f
        moveq   #2,%d1
        cmp.l   %d1,%d0
        bgt.s   2f
        lea     key_scale_names,%a1               | MAJ, MIN
        move.l  (%a1,%d0.l*4),%d0
        bra.s   9f
2:      moveq   #SCALE_MAX,%d1
        cmp.l   %d1,%d0
        bgt.s   1f
        lea     scale_remap,%a1
        mvz.b   (%a1,%d0.l),%d0
        lea     scale_short_names+4,%a1
        move.l  (%a1,%d0.l*4),%d0
        bra.s   9f
1:      move.l  key_scale_names,%d0               | OFF
9:      move.l  %d0,-(%sp)
        moveal  %fp@(20),%a0                      | displaced
        jmp     key_scale_draw_resume

        | ------------------------------------------------------------------
        | Data. Byte-sized, so after every entry point.
        | ------------------------------------------------------------------

        | KEY SCALE value -> scale_table row. 1 = MAJ and 2 = MIN keep their stock
        | meaning (Ionian, Aeolian); then the other five modes, then the rest of
        | the library in its own order. Chromatic is not offered: it is OFF.
scale_remap:
        .byte   0                                 | OFF, never read
        .byte   0, 5                              | MAJ, MIN
        .byte   1, 2, 3, 4, 6                     | DOR PHRY LYD MIXO LOCR
        .byte   7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20
        .byte   21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34

snap_offsets:
        .byte   0, -1, 1, -2, 2
snap_offsets_end:
