        | Mod 0008 - extra pages: a DIST page behind AMP (press AMP again).
        | See design.md and mod.toml.
        |
        | The A4 builds one view per page at startup and files it in a std::map at
        | controller + 436 under a slot number (0..28, all used); each page key
        | holds a list of slots and a press steps to the next one. Here:
        |   - page_build (end of the startup builder): one more plain
        |     ParameterPageView, on the blank page 17, filed under slot 29;
        |   - patches: set_slot's clamp 28 -> 29, the AMP key's slot list
        |     [10] -> amp_slots [10, 29], and page 17's descriptor (name "DIST",
        |     the knob ids 0007's layer table maps to its settings);
        |   - knob_gate (every page view's knob draw, vtable +0xa0): notes the
        |     view being drawn (shared_draw_view), for 0007's name gates;
        |   - held_gate (the encoder handler's held-trig path): no p-locks on the
        |     DIST page, nor on the NOISE page's WAV and CHD knobs (0010) - they
        |     would land on the stock parameters behind their ids.
        | 0007's gates find their settings by (shared_view_page(view), id).
        | (A second page, TYPE behind CHORUS for the comb, was added and removed
        | again: see shelved/README.md.)

        .include "symbols.inc"

        .equ    SLOT_DIST,      29
        .equ    PAGE_DIST,      17
        .equ    PAGE_NOISE,     7
        .equ    ID_MODE,        92                 | 0010's knobs on the NOISE page
        .equ    ID_CHORD,       94
        .equ    TAG_AMP,        0x36               | the AMP view's tag
        .equ    VIEW_SIZE,      0x1c4              | MKII (the MK1's views are 0x260)
        .equ    VIEW_MAP,       444                | controller + 444 (MK1: + 436)
        .equ    PPV_VTABLE,     0x4018d650         | plain ParameterPageView (MK1: 0x40170524)
        .equ    VIEW_PAGE,      128

        .text

        | ------------------------------------------------------------------
        | shared_view_page(a0 = a view) -> d0 = its page number if it is a
        | plain ParameterPageView (DIST, NOISE, ...), else -1. Uses d0 only.
        | ------------------------------------------------------------------
        .align  2
shared_view_page:
        move.l  (%a0),%d0
        cmpi.l  #PPV_VTABLE,%d0
        bne.s   9f
        move.l  VIEW_PAGE(%a0),%d0
        rts
9:      moveq   #-1,%d0
        rts

        | ------------------------------------------------------------------
        | The startup view builder, after slot 28 is filed (MKII 0x400c236e). Its
        | helpers are still in registers: a2 = operator new, a4 = the map
        | entry assign, a5 = the map's operator[], a3 = the shared_ptr release
        | it runs after each assign; d2 = &its shared_ptr temp, d3 = &the key
        | (fp - 32), d4 = the release's argument; the controller is fp@(8).
        | The same sequence as each stock slot.
        | ------------------------------------------------------------------
        .align  2
page_build:
        pea     VIEW_SIZE                         | (12 bytes of the builder's
                                                  | arguments still stacked)
        jsr     (%a2)                             | new
        addq.l  #4,%sp
        move.l  %d0,-(%sp)                        | the view, kept
        pea     TAG_AMP
        pea     PAGE_DIST
        move.l  %d0,-(%sp)
        jsr     ppv_ctor                          | ParameterPageView(view, 17, tag)
        lea     12(%sp),%sp
        move.l  %d2,-(%sp)                        | view is already at (sp)+4
        jsr     view_wrap                         | shared_ptr temp = view
        addq.l  #8,%sp
        move.l  %d3,%a0
        moveq   #SLOT_DIST,%d0
        move.l  %d0,(%a0)                         | the key
        move.l  %d3,-(%sp)
        move.l  8(%fp),%a0
        pea     VIEW_MAP(%a0)
        jsr     (%a5)                             | &map[29]
        addq.l  #8,%sp
        move.l  %d2,-(%sp)
        move.l  %d0,-(%sp)
        jsr     (%a4)                             | map[29] = temp
        addq.l  #8,%sp
        move.l  %d4,-(%sp)
        jsr     (%a3)                             | release, as stock
        addq.l  #4,%sp
        lea     12(%sp),%sp                       | displaced
        move.l  8(%fp),%a0                        | displaced
        jmp     page_build_resume

        | ------------------------------------------------------------------
        | The knob draw (vtable +0xa0 of every page view), at its entry:
        | 4(%sp) = the view. d0 is free here. The MKII builds this frame
        | without a frame pointer (the MK1: link %fp,#-68; move.b 43(%fp),%d0).
        | ------------------------------------------------------------------
        .align  2
knob_gate:
        move.l  4(%sp),%d0
        move.l  %d0,shared_draw_view
        lea     -68(%sp),%sp                      | displaced
        movem.l %d2-%d7/%a2-%a6,(%sp)             | displaced
        jmp     knob_draw_resume

        | ------------------------------------------------------------------
        | The encoder handler's held-trig call (view vtable +0x7c, args
        | (view, id, delta) pushed, a0 = the vtable, a2 = the view). On the
        | DIST page, or the NOISE page's WAV knob: no lock, straight to the
        | handler's exit. d2 = the id.
        | ------------------------------------------------------------------
        .align  2
held_gate:
        move.l  %a0,%d1
        move.l  %a2,%a0
        jbsr    shared_view_page
        cmpi.l  #PAGE_DIST,%d0
        beq.s   2f
        cmpi.l  #PAGE_NOISE,%d0
        bne.s   1f
        moveq   #ID_MODE,%d0
        cmp.l   %d2,%d0
        beq.s   2f
        moveq   #ID_CHORD,%d0
        cmp.l   %d2,%d0
        bne.s   1f
2:      lea     12(%sp),%sp                       | the call's arguments
        jmp     encoder_exit
1:      move.l  %d1,%a0
        move.l  124(%a0),%a0                      | displaced
        jsr     (%a0)                             | displaced
        jmp     held_resume

        | ------------------------------------------------------------------
        | Data
        | ------------------------------------------------------------------
        .align  2
amp_slots:      .long   10, SLOT_DIST             | the AMP key: AMP, then DIST
amp_slots_end:
s_dist:         .asciz  "DIST (P 2/2)"            | the MKII's page title style
s_amp:          .asciz  "AMP (P 1/2)"
        .align  2
shared_draw_view:   .long 0                       | the view whose knobs were drawn last
