        | Mod 0012 - resonance limit: a SOUND SETUP checkbox (FUNC + OSC1), RESONANCE
        | LIMIT, that scales the sound's F1 RES into 0..90 and F2 RES into 0..70 - knob,
        | p-locks, LFOs and envelopes included - so it can be swept without reaching
        | self-oscillation. OS 1.56. See mod.toml.
        |
        | The setting lives in the sound: bit 7 of its unused parameter word 103 (+226
        | in the 338-byte live sound), beside 0010's mode and chord (word 103 = 0x57xx,
        | xx = chord << 2 | mode, bits 0..6). 0010 carries the word through sound loads
        | (its conv_gate) and masks bit 7 out of its mode byte, so this mod needs 0010.
        |
        | Engine (res_gate): the voice parameter words are rebuilt every block - the
        | smoothed values, then the modulation (LFOs, envelopes) added in place and
        | clamped to 0..0x7fff (0x400fd2c0..0x400fd2d2) - and everything that drives the
        | filters reads them after (0x400fd946, 0x400f9482). At the first instruction
        | after that loop (0x400fd33a, `tst.l 0x415c00dc`, re-emitted) each voice whose
        | track's sound has the bit gets F1 RES (0x800050f8 + 2v) x 90/127 and F2 RES
        | (0x80005118 + 2v) x 70/127. Both words were found turning F1 / F2 RES in the
        | emulator (32 -> 72: 0x2000 -> 0x4800).
        |
        | Menu (menu_gate): SOUND SETUP's builder adds OSCILLATOR DRIFT, F1 RESONANCE
        | BOOST, VELOCITY TO VOL ... one item at a time, each from four callbacks
        | (label, YES toggle, checkbox draw, encoder adjust) and menu_toggle_item.
        | After BOOST's (0x400e07bc, `movea.l (%a3),%a0; move.l 8(%a0),%d7`, re-
        | emitted) add_item builds ours the same way, with BOOST's four callback
        | managers (generic: they clone and free the 1-byte state) and our invokers.
        |
        | Calls follow the stock ABI: d0/d1/a0/a1 are scratch, the rest is saved.

        .include "symbols.inc"

        .equ    SND_SIZE,     338                 | the live sounds, from S:
        .equ    SND0_FROM_S,  1352                | S - 1352 + 338 t
        .equ    SND_WAV,      226                 | parameter word 103
        .equ    WAV_SIG,      0x57                | its high byte when set
        .equ    VOICE_TRACK,  0x80005530          | + 4v: the voice's track
        .equ    F1_RES,       0x800050f8          | + 2v: F1 RES, modulated, 0..0x7fff
        .equ    F2_RES,       0x80005118          | + 2v: F2 RES
        .equ    MOD_FLAG,     0x415c00dc          | the displaced test's operand
        .equ    RES_RESUME,   0x400fd340          | past the displaced instructions
        .equ    MENU_RESUME,  0x400e07c2
        | x 80/127 and x 64/127 (127 = 0x7f00 -> 0x5000 / 0x4000), << 16 (the
        | first try, 90 / 70, was a little high on the unit)
        .equ    F1_K,         41283
        .equ    F2_K,         33027

        | ==================================================================
        | Engine (cave21)
        | ==================================================================
        .text
        .align  2
res_gate:
        lea     -16(%sp),%sp
        movem.l %d2-%d3/%a2-%a3,(%sp)
        move.l  project_ptr,%d0
        beq.s   9f
        move.l  %d0,%a0
        move.l  PROJECT_KIT_FX_STORAGE(%a0),%d0
        beq.s   9f
        move.l  %d0,%a2
        lea     SND_WAV-SND0_FROM_S(%a2),%a2      | track 0's word 103
        lea     VOICE_TRACK+16,%a3
        moveq   #6,%d2                            | 2v, voice 3 down to 0
1:      move.l  -(%a3),%d1
        moveq   #3,%d0
        cmp.l   %d0,%d1
        bhi.s   2f                                | not on a synth track
        mulu.w  #SND_SIZE,%d1
        mvz.w   (%a2,%d1.l),%d1
        move.l  %d1,%d0
        lsr.l   #8,%d0
        cmpi.l  #WAV_SIG,%d0
        bne.s   2f
        tst.b   %d1                               | bit 7: the limit
        bpl.s   2f
        lea     F1_RES,%a0
        mvz.w   (%a0,%d2.l),%d3
        mulu.w  #F1_K,%d3
        swap    %d3
        move.w  %d3,(%a0,%d2.l)
        lea     F2_RES,%a0
        mvz.w   (%a0,%d2.l),%d3
        mulu.w  #F2_K,%d3
        swap    %d3
        move.w  %d3,(%a0,%d2.l)
2:      subq.l  #2,%d2
        bpl.s   1b
9:      movem.l (%sp),%d2-%d3/%a2-%a3
        lea     16(%sp),%sp
        tst.l   MOD_FLAG                          | displaced
        jmp     RES_RESUME


        | ==================================================================
        | The menu item (cave22, cave26)
        | ==================================================================
        .section .rl2,"ax"

        | add_item(view): four 16-byte callbacks {state, -, manager, invoker} in
        | the frame (as the builder's own at fp - 72), the item, the view's add.
        .align  2
add_item:
        link    %fp,#-64
        lea     -16(%sp),%sp
        movem.l %d2-%d3/%a2-%a3,(%sp)
        lea     -64(%fp),%a2
        lea     fn_table,%a3
        moveq   #3,%d2
1:      clr.l   8(%a2)
        pea     1.w
        jsr     op_new
        addq.l  #4,%sp
        move.l  %d0,(%a2)
        move.l  (%a3)+,8(%a2)
        move.l  (%a3)+,12(%a2)
        lea     16(%a2),%a2
        subq.l  #1,%d2
        bpl.s   1b
        pea     0x54.w
        jsr     op_new
        addq.l  #4,%sp
        move.l  %d0,%d3
        pea     8.w
        pea     -1.w
        pea     -16(%fp)
        pea     -32(%fp)
        pea     -48(%fp)
        pea     -64(%fp)
        move.l  %d0,-(%sp)
        jsr     menu_toggle_item
        lea     28(%sp),%sp
        move.l  8(%fp),%a0                        | the view: its add method
        move.l  (%a0),%a1
        move.l  8(%a1),%a1
        move.l  %d3,-(%sp)
        move.l  %a0,-(%sp)
        jsr     (%a1)
        addq.l  #8,%sp
        jmp     add_item_end

        .section .rl6,"ax"
        | The SOUND SETUP builder, after BOOST's item: ours, then the displaced
        | two instructions (the next item's add method).
        .align  2
menu_gate:
        move.l  %a3,-(%sp)
        jbsr    add_item
        addq.l  #4,%sp
        movea.l (%a3),%a0                         | displaced
        move.l  8(%a0),%d7                        | displaced
        jmp     MENU_RESUME

        .align  2
add_item_end:                                     | the callbacks freed (the item
        moveq   #3,%d2                            | holds copies), back
        lea     -16(%fp),%a2
1:      move.l  %a2,-(%sp)
        jsr     functor_dtor
        addq.l  #4,%sp
        lea     -16(%a2),%a2
        subq.l  #1,%d2
        bpl.s   1b
        movem.l (%sp),%d2-%d3/%a2-%a3
        unlk    %fp
        rts

        | (a0 = the result) -> the label string, as BOOST's (0x400de4b0)
        .align  2
inv_label:
        link    %fp,#-4
        move.l  %d2,-(%sp)
        pea     -1(%fp)
        pea     s_label
        move.l  %a0,%d2
        move.l  %a0,-(%sp)
        jsr     string_from_cstr
        lea     12(%sp),%sp
        move.l  %d2,%d0
        move.l  -8(%fp),%d2
        unlk    %fp
        rts

        | ==================================================================
        | The setting (cave23, cave25)
        | ==================================================================
        .section .rl3,"ax"

        | snd_data() -> d0 = the current track's sound object, a0 = its data (the
        | 338-byte format); d0 = 0 on the FX / CV tracks. The chain the stock items'
        | callbacks use (0x400df95e).
        .align  2
snd_data:
        move.l  %d2,-(%sp)
        jsr     project_singleton
        move.l  %d0,-(%sp)
        jsr     project_track_ctx
        move.l  %d0,(%sp)
        jsr     track_index_of
        addq.l  #4,%sp
        move.l  %d0,%d2
        moveq   #3,%d0
        cmp.l   %d2,%d0
        bcs.s   8f
        jsr     project_singleton
        move.l  %d0,-(%sp)
        jsr     active_kit
        move.l  %d2,(%sp)
        move.l  %d0,-(%sp)
        jsr     kit_track_sound
        addq.l  #8,%sp
        tst.l   %d0
        beq.s   9f
        move.l  %d0,-(%sp)
        move.l  %d0,%a0
        move.l  (%a0),%a0
        move.l  40(%a0),%a0
        jsr     (%a0)                             | (sound) -> its data
        move.l  %d0,%a0
        move.l  (%sp)+,%d0
        move.l  %a0,%d1
        bne.s   9f
8:      moveq   #0,%d0
9:      move.l  (%sp)+,%d2
        rts

        | lim_get() -> d0 = 1 on, 0 off, -1 not a synth track
        .align  2
lim_get:
        jbsr    snd_data
        tst.l   %d0
        beq.s   7f
        mvz.w   SND_WAV(%a0),%d1
        move.l  %d1,%d0
        lsr.l   #8,%d0
        cmpi.l  #WAV_SIG,%d0
        bne.s   8f
        moveq   #1,%d0
        btst    #7,%d1
        bne.s   9f
8:      moveq   #0,%d0
9:      rts
7:      moveq   #-1,%d0
        rts

        .section .rl5,"ax"

        | lim_set(d0 > 0: on, else off): bit 7 of word 103 (the word's signature
        | set if it had none), then the sound's change notice as a setting's setter
        | sends it (0x400afb34).
        .align  2
lim_set:
        lea     -8(%sp),%sp
        movem.l %d2/%a2,(%sp)
        move.l  %d0,%d2
        jbsr    snd_data
        tst.l   %d0
        beq.s   9f
        move.l  %d0,%a2
        mvz.w   SND_WAV(%a0),%d1
        move.l  %d1,%d0
        lsr.l   #8,%d0
        cmpi.l  #WAV_SIG,%d0
        beq.s   1f
        move.l  #WAV_SIG << 8,%d1                 | not set yet: all fields 0
1:      bclr    #7,%d1
        tst.l   %d2
        ble.s   2f
        bset    #7,%d1
2:      move.w  %d1,SND_WAV(%a0)
        lea     -12(%sp),%sp                      | {vt, -1, 1, 1}
        move.l  #change_info_vt,(%sp)
        moveq   #-1,%d0
        move.l  %d0,4(%sp)
        moveq   #1,%d0
        move.b  %d0,8(%sp)
        move.b  %d0,9(%sp)
        move.l  %sp,%a1
        move.l  %a1,-(%sp)
        move.l  %a2,-(%sp)
        move.l  (%a2),%a0
        move.l  16(%a0),%a0
        jsr     (%a0)
        lea     20(%sp),%sp
9:      movem.l (%sp),%d2/%a2
        lea     8(%sp),%sp
        rts

        .section .rl7,"ax"

        | The item's callbacks: BOOST's managers, our invokers (label, toggle,
        | draw, adjust), and the label.
        .align  2
fn_table:
        .long   boost_managers,         inv_label
        .long   boost_managers + 0x52,  inv_toggle
        .long   boost_managers + 0xa4,  inv_draw
        .long   boost_managers + 0xf6,  inv_adjust
s_label:
        .asciz  "RESONANCE LIMIT"

        | ==================================================================
        | The invokers (cave24)
        | ==================================================================
        .section .rl4,"ax"

        | YES: flip it
        .align  2
inv_toggle:
        jbsr    lim_get
        eori.l  #1,%d0
        jmp     lim_set

        | an encoder step (3rd argument): add it, clamp to off / on
        .align  2
inv_adjust:
        jbsr    lim_get
        add.l   12(%sp),%d0
        jmp     lim_set

        | (-, -, x, y, z): the checkbox, as BOOST's (0x400df9c6) draws it with
        | its 3rd .. 5th arguments
        .align  2
inv_draw:
        lea     -12(%sp),%sp
        movem.l %d3-%d5,(%sp)
        movem.l 24(%sp),%d3-%d5
        jbsr    lim_get
        tst.l   %d0
        bmi.s   9f
        clr.l   -(%sp)
        move.l  %d0,-(%sp)
        pea     icon_set
        jsr     icon_for
        lea     12(%sp),%sp
        clr.l   -(%sp)
        move.l  %d5,-(%sp)
        addi.l  #11,%d4
        move.l  %d4,-(%sp)
        move.l  %d0,-(%sp)
        move.l  %d3,-(%sp)
        jsr     draw_icon
        lea     20(%sp),%sp
9:      movem.l (%sp),%d3-%d5
        lea     12(%sp),%sp
        rts
