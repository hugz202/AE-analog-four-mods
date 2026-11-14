        | SPDX-License-Identifier: MIT
        | res-limit - AE 0012 (resonance limit) for the Analog Four MKII, OS 1.56,
        | as an elekloader elemod on core-a4mk2 0.7.
        |
        | SOUND SETUP (FUNC + OSC1) gets a RESONANCE LIMIT checkbox after F1
        | RESONANCE BOOST. With it on for a synth track, each voice playing that
        | track gets F1 RES x 80/127 and F2 RES x 64/127 after the modulation
        | (knob, p-locks, LFOs, envelopes), so the filters stay out of
        | self-oscillation. The switch is a kit field, one bit a track
        | (res-limit.c).
        |
        | Engine (res_gate). The audio interrupt 0x401013be rebuilds the voice
        | parameter words each block (0x80005af0 + 8p + 2v: the smoothed values,
        | then the modulation added in place and clamped to 0..0x7fff,
        | 0x401032d2..0x40103432), then calls 0x400fa2b0 (VCA/pan words) and
        | 0x400ff74e, which builds the filter words of the analog frame from them:
        | F1 from 0x80005bb0 (FREQ, frame w6) and 0x80005bb8 (RES, w7, with
        | RESONANCE BOOST's flag 0x800042e6 + v), F2 from 0x80005bd0 (w9) and
        | 0x80005bd8 (w10). res_gate takes the first of those calls
        | (`jsr 0x400fa2b0.l` at 0x40103af6): it scales the two RES words of each
        | voice whose track (0x80005ff0 + 4v) has the switch, makes the call and
        | rejoins at 0x40103afc. These are the MK1's F1_RES / F2_RES (0x800050f8 /
        | 0x80005118 there), 0x20 apart as on the MK1.
        |
        | Menu (res_menu). SOUND SETUP's builder 0x400e5f54 adds each item from
        | four callbacks (label, YES toggle, checkbox draw, encoder adjust),
        | op_new(0x54) and menu_toggle_item, as the MK1's does. After BOOST's
        | (0x400e62c8, `movea.l (%a3),%a0; move.l 8(%a0),%d7`, re-emitted)
        | add_item builds ours the same way, with BOOST's four callback managers
        | (0x400e43b8 + 0x52 k: generic, they clone and free the 1-byte state)
        | and our invokers.
        |
        | The code is the MK1's (AE-analog-four-mods OS-1.56, mods/0012-res-
        | limit) with the MKII's addresses; the setting moved from the sound's
        | word 103 to core's kit storage. Calls follow the stock ABI: d0/d1/a0/a1
        | are scratch, the rest is saved.

        | OS 1.56 MKII addresses (MK1 in brackets)
        .equ    VOICE_TRACK,     0x80005ff0       | + 4v (0x80005530)
        .equ    F1_RES,          0x80005bb8       | + 2v (0x800050f8)
        .equ    F2_RES,          0x80005bd8       | + 2v (0x80005118)
        .equ    voice_words,     0x400fa2b0       | the displaced call
        .equ    RES_RESUME,      0x40103afc
        .equ    MENU_RESUME,     0x400e62ce       | (0x400e07c2)
        .equ    op_new,          0x400653b8
        .equ    menu_toggle_item,0x4005c7c4
        .equ    functor_dtor,    0x4014471e
        .equ    boost_managers,  0x400e43b8
        .equ    string_from_cstr,0x4018471e
        .equ    icon_for,        0x4005b380
        .equ    icon_set,        0x4186fa58
        .equ    draw_icon,       0x4005aed4
        | x 80/127 and x 64/127 (127 = 0x7f00 -> 0x5000 / 0x4000), << 16
        .equ    F1_K,            41283
        .equ    F2_K,            33027

        .text
        .globl  res_gate
        .globl  res_menu

        | ==================================================================
        | Engine
        | ==================================================================
        .align  2
res_gate:
        lea     -16(%sp),%sp
        movem.l %d2-%d3/%a2-%a3,(%sp)
        lea     res_on,%a2
        lea     VOICE_TRACK+16,%a3
        moveq   #6,%d2                            | 2v, voice 3 down to 0
1:      move.l  -(%a3),%d1
        moveq   #3,%d0
        cmp.l   %d0,%d1
        bhi.s   2f                                | not on a synth track
        tst.b   (%a2,%d1.l)
        beq.s   2f
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
        movem.l (%sp),%d2-%d3/%a2-%a3
        lea     16(%sp),%sp
        jsr     voice_words                       | displaced
        jmp     RES_RESUME

        | ==================================================================
        | The menu item
        | ==================================================================

        | The SOUND SETUP builder, after BOOST's item: ours, then the displaced
        | two instructions (the next item's add method).
        .align  2
res_menu:
        move.l  %a3,-(%sp)
        jbsr    add_item
        addq.l  #4,%sp
        movea.l (%a3),%a0                         | displaced
        move.l  8(%a0),%d7                        | displaced
        jmp     MENU_RESUME

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
        moveq   #3,%d2                            | the callbacks freed (the item
        lea     -16(%fp),%a2                      | holds copies)
2:      move.l  %a2,-(%sp)
        jsr     functor_dtor
        addq.l  #4,%sp
        lea     -16(%a2),%a2
        subq.l  #1,%d2
        bpl.s   2b
        movem.l (%sp),%d2-%d3/%a2-%a3
        unlk    %fp
        rts

        | (a0 = the result) -> the label string, as BOOST's (0x400e3f2c)
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

        | YES: flip it
        .align  2
inv_toggle:
        jbsr    lim_get
        eori.l  #1,%d0
        move.l  %d0,-(%sp)
        jbsr    lim_set
        addq.l  #4,%sp
        rts

        | an encoder step (3rd argument): add it; lim_set takes > 0 as on
        .align  2
inv_adjust:
        jbsr    lim_get
        add.l   12(%sp),%d0
        move.l  %d0,-(%sp)
        jbsr    lim_set
        addq.l  #4,%sp
        rts

        | (-, -, x, y, z): the checkbox, as BOOST's (0x400e5474) draws it with
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

        | The item's callbacks: BOOST's managers, our invokers (label, toggle,
        | draw, adjust), and the label.
        .section .rodata
        .align  2
fn_table:
        .long   boost_managers,         inv_label
        .long   boost_managers + 0x52,  inv_toggle
        .long   boost_managers + 0xa4,  inv_draw
        .long   boost_managers + 0xf6,  inv_adjust
s_label:
        .asciz  "RESONANCE LIMIT"
