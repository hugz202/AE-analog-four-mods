/* SPDX-License-Identifier: MIT */
/* dist - the DIST page (AE 0008) and the digital path's settings (AE 0007)
 * for the Analog Four MKII, OS 1.56, on core-a4mk2 0.7 (written for core-a4 0.5). dist.s is the audio
 * side; this is the page and the settings.
 *
 * On a synth track, AMP pressed twice: the DIST page (page 50), after stock's
 * AMP, through core-a4's page tables. AMP is retitled "AMP (P 1/2)" to match.
 *
 *   knob  setting  range               lock  LFO, routes, macros, CC
 *   A     DIG      off / on            yes   no
 *   B     CHR      HARD / RAT / OD     yes   no
 *   C     DRV      0..127              yes   yes
 *   D     BIT      0..127              yes   yes
 *   E     SRR      0..127              yes   yes
 *   F     LEV      0..127              yes   yes
 *   G     SLD      off / on            no    no
 *
 * The settings are sound fields in core-a4's mod storage, all 32 bits a
 * sound keeps, so they travel with the sound (kits, the sound pool, copies),
 * and so wave (which keeps its own in the sound) cannot share a build with
 * dist. DIG, CHR, DRV, BIT, SRR and LEV are lockable (core-a4 0.5): hold a
 * trig and turn the knob, or turn it in live recording. DRV, BIT, SRR and LEV
 * are also destinations ("mod": the LFOs, the Dest knobs, the routes, the
 * macros and CONTROL IN) and have a CC each; DIG and CHR are switches, so
 * they take locks only and jump, with no smoothing, slide or modulation. SLD
 * is slide's per-track mode, read by the sequencer: it has no lock.
 *
 * The knobs are 7 mod ids the linker gives ("knobs": 7, from 0x200 up; from
 * 2.4, before which they were 0x300..0x306): core names the lockable
 * ones from their core_lock_param, and dist.s's gate on the name getters
 * names SLD. Each audio block (ev_render_out, after core's snapshot) puts in
 * dist_set what each track plays: DRV..LEV from core's value read (the
 * sound's value or the trig's lock, smoothed, Param Slide and every
 * modulation), DIG and CHR the trig's lock or the sound's value. The UI tick
 * keeps the sound's DIG, CHR and SLD in dist_base and dist_sld.
 *
 * A new sound reads 0 in every field (core-a4 keeps no field init), so LEV
 * starts at 0: switching DIG on with LEV at 0 sets LEV to 100, about level
 * with the analog path.
 */
#include <stdint.h>
#include "analog-four-mk2/pages.h"
#include "analog-four-mk2/store.h"
#include "analog-four-mk2/lock.h"

#define PROJECT_PTR 0x418717c8      /* the live project */
#define KIT_FX_STORAGE 0x11ac       /* the kit's FX storage, kit + 0x564 */
#define KIT_FROM_FX 0x564
#define KIT_SOUND0 0x1c             /* a kit's sounds, 0x152 bytes each */
#define SOUND_SIZE 0x152
#define ACTIVE_TRACK 48             /* project + 48: the active track's object */
#define TRACK_INDEX_OF 0x400adbd2

#define PAGE_DIST 50
#define PAGE_AMP 11
#define TURN 3                      /* turns a position, for settings of 3..16 positions */
#define LEV_START 100               /* LEV when DIG goes on with LEV at 0 */

/* the knobs' ids, from the linker ("knobs": 7 in mod.json): link-time
 * constants, so the code tells them apart by id - ID_DIG, never by a case */
CORE_KNOBS;
#define K_DIG 0
#define K_CHR 1
#define K_DRV 2
#define K_BIT 3
#define K_SRR 4
#define K_LEV 5
#define K_SLD 6
#define ID_DIG CORE_KNOB(K_DIG)
#define ID_CHR CORE_KNOB(K_CHR)
#define ID_DRV CORE_KNOB(K_DRV)
#define ID_BIT CORE_KNOB(K_BIT)
#define ID_SRR CORE_KNOB(K_SRR)
#define ID_LEV CORE_KNOB(K_LEV)
#define ID_SLD CORE_KNOB(K_SLD)

typedef int32_t (*track_index_of_t)(void *);

STORE_FIELD(dist_dig);
STORE_FIELD(dist_chr);
STORE_FIELD(dist_drv);
STORE_FIELD(dist_bit);
STORE_FIELD(dist_srr);
STORE_FIELD(dist_lev);
STORE_FIELD(dist_sld_f);

extern unsigned char dist_set[];    /* dist.s: 6 bytes a track (DIG DRV BIT SRR LEV SLD), then CHR x 4 */
extern unsigned char dist_sld[];    /* dist.s: 1, then each track's SLD */
extern volatile unsigned char core_dry_mute;   /* core: bit v mutes voice v's dry words; cleared each block */

#define CAT CORE_LOCK_CATEGORY("DIST")
const struct core_lock_param dist_lp_dig = {STORE(dist_dig), ID_DIG, 0, 1, "DIG", "Digital Path", CAT};
const struct core_lock_param dist_lp_chr = {STORE(dist_chr), ID_CHR, 0, 2, "CHR", "Character", CAT};
const struct core_lock_param dist_lp_drv = {STORE(dist_drv), ID_DRV, 0, 127, "DRV", "Drive", CAT};
const struct core_lock_param dist_lp_bit = {STORE(dist_bit), ID_BIT, 0, 127, "BIT", "Bit Reduction", CAT};
const struct core_lock_param dist_lp_srr = {STORE(dist_srr), ID_SRR, 0, 127, "SRR", "Sample Rate", CAT};
const struct core_lock_param dist_lp_lev = {STORE(dist_lev), ID_LEV, 0, 127, "LEV", "Digital Level", CAT};

/* a knob, by its index (K_DIG..K_SLD): its field, its largest value, the
 * offset in dist_set (24: CHR's row) */
struct knob {
    unsigned field;
    uint8_t max, cache;
};

static const struct knob knobs[] = {
    {STORE(dist_dig), 1, 0},
    {STORE(dist_chr), 2, 24},
    {STORE(dist_drv), 127, 1},
    {STORE(dist_bit), 127, 2},
    {STORE(dist_srr), 127, 3},
    {STORE(dist_lev), 127, 4},
    {STORE(dist_sld_f), 1, 5},
};
#define NKNOBS (sizeof knobs / sizeof knobs[0])

static const char chr_names[3][4] = {"HRD", "RAT", "OD"};

static const struct knob *knob_of(int32_t id)
{
    uint32_t k = (uint32_t)(id - ID_DIG);
    return k < NKNOBS ? &knobs[k] : 0;
}

static unsigned char *project(void)
{
    return *(unsigned char **)PROJECT_PTR;
}

/* the active track, 0..5, or -1 before there is a project */
static int32_t active_track(void)
{
    unsigned char *p = project();
    if (!p)
        return -1;
    return ((track_index_of_t)TRACK_INDEX_OF)(p + ACTIVE_TRACK);
}

/* track t's live sound in the current kit, as core-a4's sound scope takes it */
static void *sound(int32_t t)
{
    unsigned char *p = project(), *s;
    if (!p || t < 0 || t > 3)
        return 0;
    s = *(unsigned char **)(p + KIT_FX_STORAGE);
    return s ? s - KIT_FROM_FX + KIT_SOUND0 + SOUND_SIZE * t : 0;
}

static unsigned get(const struct knob *k, void *s)
{
    unsigned v = s ? core_store_get(k->field, s, 0) : 0;
    return v > k->max ? k->max : v;
}

/* each synth track's DIG and CHR as its sound has them, for the audio side */
static volatile unsigned char dist_base[4][2];

static void cache_all(void)
{
    int32_t t;
    for (t = 0; t < 4; t++) {
        void *s = sound(t);
        dist_base[t][0] = get(&knobs[K_DIG], s);
        dist_base[t][1] = get(&knobs[K_CHR], s);
        dist_set[6 * t + 5] = dist_sld[1 + t] = get(&knobs[K_SLD], s);
    }
}

/* How far a turn moves a setting (the image port's step_of). Dials take
 * the delta's whole steps (at least one); switches one per turn. Settings of
 * 3..16 positions step once per TURN turns, each counted as one plain step
 * whatever its speed, as stock's stepped parameters do; the count starts
 * over on another knob or a change of direction. */
static int32_t step_of(int32_t delta, int32_t id, unsigned max)
{
    static int32_t acc_id, acc;
    int32_t d = delta < 0 ? -1 : 1;
    if (max > 15) {
        int32_t s = delta >> 8;
        return s ? s : d;
    }
    if (max == 1)
        return d;
    if (id != acc_id) {
        acc_id = id;
        acc = 0;
    }
    if ((acc ^ d) < 0)
        acc = 0;
    acc += d;
    if (acc >= TURN || acc <= -TURN) {
        acc = 0;
        return d;
    }
    return 0;
}

static int dist_get(int32_t id, int32_t *value)
{
    const struct knob *k = knob_of(id);
    if (!k)
        return 0;
    *value = (int32_t)get(k, sound(active_track())) << 8;
    return 1;
}

static int dist_delta(void *view, int32_t id, int32_t delta, int32_t func)
{
    const struct knob *k = knob_of(id);
    int32_t t = active_track(), v;
    void *s = sound(t);
    (void)view;
    (void)func;
    if (!k)
        return 0;
    if (!s)
        return 1;
    v = (int32_t)get(k, s) + step_of(delta, id, k->max);
    v = v < 0 ? 0 : v > k->max ? k->max : v;
    core_store_set(k->field, s, 0, (unsigned)v);
    if (id == ID_DIG && v && !core_store_get(STORE(dist_lev), s, 0))
        core_store_set(STORE(dist_lev), s, 0, LEV_START);
    cache_all();
    return 1;
}

static void copy_name(char *buf, const char *s)
{
    while ((*buf++ = *s++) != 0)
        ;
}

/* The value's text: CHR its character's name, the switches ON or OFF, the
 * dials their number. A trig's lock is shown through here too. */
static int dist_text(struct core_text *t)
{
    const struct knob *k = knob_of(t->id);
    unsigned v = ((unsigned)t->value >> 8) & 0xff;
    if (!k)
        return CORE_TEXT_PASS;
    if (k->max == 2) {
        copy_name(t->buf, chr_names[v > 2 ? 2 : v]);
        return CORE_TEXT_DONE;
    }
    if (k->max == 1) {
        copy_name(t->buf, v ? "ON" : "OFF");
        return CORE_TEXT_DONE;
    }
    t->buf[0] = v >= 100 ? '0' + v / 100 : ' ';
    t->buf[1] = v >= 10 ? '0' + v / 10 % 10 : ' ';
    t->buf[2] = '0' + v % 10;
    t->buf[3] = 0;
    return CORE_TEXT_DONE;
}

const struct core_param dist_params = {ID_DIG, ID_SLD, dist_get, dist_delta, dist_text};

/* Knob looks (core-a4mk2 0.6's core_knob_looks, from 2.2): the knobs drawn as
 * 1.0 drew them, on stock knobs' art. DIG as OSC1 AM's switch (50), CHR as
 * AMP PAN's marker (97) over its three positions, DRV..LEV as AMP CHO's dial
 * (94), SLD as OSC2 AM's switch (63). The ranges are the settings' own (8.8,
 * as dist_get answers), so the graphic spans them. */
#define STOCK_OSC1_AM 50
#define STOCK_OSC2_AM 63
#define STOCK_AMP_CHO 94
#define STOCK_AMP_PAN 97
const struct core_knob_look dist_look_dig = {ID_DIG, ID_DIG, STOCK_OSC1_AM, 0, 0, 1 << 8};
const struct core_knob_look dist_look_chr = {ID_CHR, ID_CHR, STOCK_AMP_PAN, 0, 0, 2 << 8};
const struct core_knob_look dist_look_dials = {ID_DRV, ID_LEV, STOCK_AMP_CHO, 0, 0, 127 << 8};
const struct core_knob_look dist_look_sld = {ID_SLD, ID_SLD, STOCK_OSC2_AM, 0, 0, 1 << 8};

const struct core_page dist_page = {PAGE_DIST, "DIST (P 2/2)",
                                    {ID_DIG, ID_CHR, ID_DRV, ID_BIT, ID_SRR, ID_LEV, ID_SLD}};
const struct core_page dist_amp_page = {PAGE_AMP, "AMP (P 1/2)", {89, 90, 91, 92, 93, 94, 95, 96, 97, 98}};
const struct core_view_page dist_view_page = {CORE_TRACK_SYNTH, CORE_KEY_AMP, PAGE_DIST, 0};

/* SLD's names, through core's knob names (core_knob_names; SLD is the one
 * dist knob that is not lockable, so core has no name for it) */
const char *dist_name_of(int32_t id, int32_t long_name)
{
    return id != ID_SLD ? 0 : long_name ? "303 Slide" : "SLD";
}

/* core_knob_names' entry (analog-four-mk2/ui.h, struct core_knob_name) */
struct dist_knob_name {
    uint16_t first_id, last_id;
    uint8_t kind, pad[3];
    const char *(*name)(int32_t id, int32_t long_name);
};
/* the ids are 16 bits there, and SLD's id is the linker's (an abs32
 * relocation), so the entry spans every id and dist_name_of picks SLD */
const struct dist_knob_name dist_knob_sld = {0, 0xffff, 0, {0, 0, 0}, dist_name_of};

/* each audio block, after core's snapshot (order 1): what each track plays,
 * and core_dry_mute's bit for each track on the digital path. Voice t takes
 * track t's settings (2.3's mapping, kept so the output is unchanged; a poly
 * or unison track's other voices take their own track index's) */
void dist_render(void)
{
    static int h[4];
    int32_t t, v[4], i, l;
    if (!h[0]) {
        h[0] = core_param_handle(STORE(dist_drv));
        h[1] = core_param_handle(STORE(dist_bit));
        h[2] = core_param_handle(STORE(dist_srr));
        h[3] = core_param_handle(STORE(dist_lev));
    }
    for (t = 0; t < 4; t++) {
        unsigned char *d = &dist_set[6 * t];
        l = core_lock_value(t, STORE(dist_dig));
        d[0] = l >= 0 ? l : dist_base[t][0];
        l = core_lock_value(t, STORE(dist_chr));
        dist_set[24 + t] = l >= 0 ? (l > 2 ? 2 : l) : dist_base[t][1];
        if (!d[0])
            continue;                       /* off: the audio side reads nothing else */
        core_dry_mute |= 1 << t;            /* the next block's dry words: volume 0 (voice t) */
        core_param_values(t, h, 4, 0, v);
        for (i = 0; i < 4; i++) {
            int32_t x = v[i] == CORE_PARAM_NONE ? 0 : (v[i] + 128) >> 8;
            d[1 + i] = x < 0 ? 0 : x > 127 ? 127 : x;
        }
    }
}

void dist_tick(void *ctrl)
{
    (void)ctrl;
    cache_all();
}

void dist_project(int how, unsigned dropped)
{
    (void)how;
    (void)dropped;
    cache_all();
}
