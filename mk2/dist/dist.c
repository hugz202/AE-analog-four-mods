/* SPDX-License-Identifier: MIT */
/* dist - the DIST page (AE 0008) and the digital path's settings (AE 0007)
 * for the Analog Four MKII, OS 1.56, on core-a4 0.2. dist.s is the audio
 * side; this is the page.
 *
 * On a synth track, AMP pressed twice: the DIST page (page 50), after stock's
 * AMP, through core-a4's page tables. AMP is retitled "AMP (P 1/2)" to match.
 *
 *   knob  setting  range               the hidden record it is drawn as
 *   A     DIG      off / on            38 (OSC1 Pitch Mod), as OSC1 AM's switch
 *   B     CHR      HARD / RAT / OD     39 (OSC1 Freq Mod), as AMP PAN's marker
 *   C     DRV      0..127              51 (OSC2 Pitch Mod), as CHO's dial
 *   D     BIT      0..127              52 (OSC2 Freq Mod), the same
 *   E     SRR      0..127              64 (OSCX Pitch Mod), the same
 *   F     LEV      0..127              65 (OSCX Freq Mod), the same
 *   G     SLD      off / on            88 (F1+F2 Freq), as OSC2 AM's switch
 *
 * The seven ids are records no stock page shows (they exist only as LFO and
 * envelope destinations, with a fixed value of 64), so core_params can answer
 * for them everywhere. Their range in the parameter table becomes 0..127
 * (mod.json's byte sites): the encoder handler makes no turn of a record
 * whose range is one value. At the first tick their RAM records take the
 * encoder feel and callbacks of CHO's (FEEL) and the dial art of the record
 * named above, and are marked unlockable: a turn with a trig held makes no
 * parameter lock. Their names come from dist.s's gates on the two name
 * getters, only while the knob draw or the encoder's header asks (an LFO's
 * destination list still reads PM1, FM1 ...).
 *
 * The settings are kit fields in core-a4's mod storage, one 32-bit field per
 * synth track (dist_trk0..3): all 128 bits a kit keeps. core_store_set
 * writes the current kit's fields through to the stored project, as stock
 * writes its own edits, so they survive a power cycle without a save. The UI
 * tick copies them into dist_set for the audio interrupt, and an edit does
 * at once.
 *
 * Other mods name the knobs of their own pages through the ae_names table
 * this mod declares (wave does).
 */
#include <stdint.h>
#include "analog-four-mk2/pages.h"
#include "analog-four-mk2/store.h"
#include "ae_names.h"

#define PROJECT_PTR 0x418717c8      /* the live project */
#define KIT_FX_STORAGE 0x11ac       /* project + 364 (the kit) + 0x1030 (its FxSetup) + 16: its storage */
#define KIT_FROM_FX 0x564           /* that storage is the edited kit's FX block, kit + 0x564 */
#define ACTIVE_TRACK 48             /* project + 48: the active track's object */
#define FXSETUP 0x119c              /* project + 364 + 0x1030: the kit's FxSetup */
#define FX_CHANGE_VT 0x4018cb34     /* the change record stock's FX setters send */
#define TRACK_INDEX_OF 0x400adbd2
#define PARAM_INFO 0x41856c44       /* the RAM records, 0x54 bytes an id */
#define PI_STRIDE 0x54
#define PI_DRAW 0x24                /* its draw callback, 16 bytes */
#define LOCK_OFF 0x20               /* record +0 bit 5: the id takes no lock */
#define FEEL 94                     /* AMP CHO: every knob turns as its dial does */

#define PAGE_DIST 50
#define PAGE_AMP 11
#define TURN 3                      /* turns a position, for settings of 3..16 positions */

typedef int32_t (*track_index_of_t)(void *);
typedef void (*notify_t)(void *fx, void *change);

STORE_FIELD(dist_trk0);
STORE_FIELD(dist_trk1);
STORE_FIELD(dist_trk2);
STORE_FIELD(dist_trk3);

extern unsigned char dist_set[];    /* dist.s: 6 bytes a track (DIG DRV BIT SRR LEV SLD), then CHR x 4 */
extern unsigned char dist_sld[];    /* dist.s: 1, then each track's SLD */

/* a knob: its id, its bits in the track's field, its largest value, the
 * offset in dist_set it is copied to, its name and the stock record it is drawn as */
struct knob {
    int16_t id;
    uint8_t shift, max, cache, donor;
    char name[4];
    const char *long_name;          /* the header's, while the knob turns */
};

#define F_LEV_XOR 64                /* LEV is kept XOR 64: a kit with no dist data reads 64 */

static const struct knob knobs[] = {
    {38, 31, 1, 0, 50, "DIG", "Digital Path"},
    {39, 29, 2, 24, 97, "CHR", "Character"},       /* dist_set + 24 + t */
    {51, 22, 127, 1, 94, "DRV", "Drive"},
    {52, 15, 127, 2, 94, "BIT", "Bit Reduction"},
    {64, 8, 127, 3, 94, "SRR", "Sample Rate"},
    {65, 1, 127, 4, 94, "LEV", "Digital Level"},
    {88, 0, 1, 5, 63, "SLD", "303 Slide"},
};
#define NKNOBS (sizeof knobs / sizeof knobs[0])

static const char chr_names[3][4] = {"HRD", "RAT", "OD"};

static const struct knob *knob_of(int32_t id)
{
    unsigned i;
    for (i = 0; i < NKNOBS; i++)
        if (knobs[i].id == id)
            return &knobs[i];
    return 0;
}

static unsigned width(const struct knob *k)
{
    return k->max == 1 ? 1 : k->max == 2 ? 2 : 7;
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

/* the current kit, as core-a4's kit scope takes it */
static void *kit(void)
{
    unsigned char *p = project(), *s;
    if (!p)
        return 0;
    s = *(unsigned char **)(p + KIT_FX_STORAGE);
    return s ? s - KIT_FROM_FX : 0;
}

static unsigned field(int32_t t)
{
    switch (t) {
    case 0: return STORE(dist_trk0);
    case 1: return STORE(dist_trk1);
    case 2: return STORE(dist_trk2);
    default: return STORE(dist_trk3);
    }
}

static unsigned get_setting(const struct knob *k, uint32_t w)
{
    unsigned v = (w >> k->shift) & ((1u << width(k)) - 1);
    if (k->id == 65)
        v ^= F_LEV_XOR;
    return v > k->max ? k->max : v;
}

static uint32_t put_setting(const struct knob *k, uint32_t w, unsigned v)
{
    uint32_t mask = ((1u << width(k)) - 1) << k->shift;
    if (k->id == 65)
        v ^= F_LEV_XOR;
    return (w & ~mask) | ((uint32_t)v << k->shift & mask);
}

/* one track's settings into dist_set and dist_sld, for the audio and slide */
static void cache(int32_t t, uint32_t w)
{
    unsigned i;
    for (i = 0; i < NKNOBS; i++) {
        const struct knob *k = &knobs[i];
        unsigned char v = get_setting(k, w);
        if (k->cache == 24)
            dist_set[24 + t] = v;
        else
            dist_set[6 * t + k->cache] = v;
    }
    dist_sld[1 + t] = dist_set[6 * t + 5];
}

static void cache_all(void)
{
    void *kp = kit();
    int32_t t;
    for (t = 0; t < 4; t++)
        cache(t, kp ? core_store_get(field(t), kp, 0) : 0);
}

/* the active kit's FX marked edited, as stock's FxSetup setters do */
static void kit_notify(void)
{
    unsigned char *p = project();
    struct { uint32_t vt; int32_t all; uint8_t a, b; } change = {FX_CHANGE_VT, -1, 1, 1};
    void **fx;
    if (!p)
        return;
    fx = (void **)(p + FXSETUP);
    ((notify_t)((void **)*fx)[4])(fx, &change);
}

/* How far a turn moves a setting (the image port's step_of). Dials take
 * the delta's whole steps (at least one); switches one per turn. Settings of
 * 3..16 positions step once per TURN turns, each counted as one plain step
 * whatever its speed, as stock's stepped parameters do (6 counts a step, no
 * acceleration); the count starts over on another knob or a change of
 * direction. */
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
    int32_t t = active_track();
    void *kp = kit();
    unsigned v;
    if (!k)
        return 0;
    v = (t >= 0 && t < 4 && kp) ? get_setting(k, core_store_get(field(t), kp, 0)) : 0;
    if (k->max == 2)
        v = (v * 127 + 1) >> 1;     /* 0, 64, 127: AMP PAN's marker left, centre, right */
    *value = (int32_t)v << 8;
    return 1;
}

static int dist_delta(void *view, int32_t id, int32_t delta, int32_t func)
{
    const struct knob *k = knob_of(id);
    int32_t t = active_track(), v;
    void *kp = kit();
    uint32_t w;
    (void)view;
    (void)func;
    if (!k)
        return 0;
    if (t < 0 || t > 3 || !kp)
        return 1;
    w = core_store_get(field(t), kp, 0);
    v = (int32_t)get_setting(k, w) + step_of(delta, id, k->max);
    if (v < 0)
        v = 0;
    if (v > k->max)
        v = k->max;
    w = put_setting(k, w, (unsigned)v);
    core_store_set(field(t), kp, 0, w);
    cache(t, w);
    kit_notify();
    return 1;
}

static void copy_name(char *buf, const char *s)
{
    while ((*buf++ = *s++) != 0)
        ;
}

/* The text the knob draw shows while a knob turns: CHR its character's
 * name, the switches their own name (the graphic is the value), the dials
 * stock's numbers, formatted as AMP CHO's. */
static int dist_text(struct core_text *t)
{
    const struct knob *k = knob_of(t->id);
    if (!k)
        return CORE_TEXT_PASS;
    if (k->max == 2) {
        unsigned v = ((unsigned)t->value >> 8) & 0xff;
        copy_name(t->buf, chr_names[v >= 96 ? 2 : v >= 32 ? 1 : 0]);
        return CORE_TEXT_DONE;
    }
    if (k->max == 1) {
        copy_name(t->buf, t->value ? "ON" : "OFF");
        return CORE_TEXT_DONE;
    }
    t->id = 94;
    return CORE_TEXT_STOCK;
}

const struct core_param dist_params = {38, 88, dist_get, dist_delta, dist_text};

const struct core_page dist_page = {PAGE_DIST, "DIST (P 2/2)", {38, 39, 51, 52, 64, 65, 88}};
const struct core_page dist_amp_page = {PAGE_AMP, "AMP (P 1/2)", {89, 90, 91, 92, 93, 94, 95, 96, 97, 98}};
const struct core_view_page dist_view_page = {CORE_TRACK_SYNTH, CORE_KEY_AMP, PAGE_DIST, 0};

static const char *dist_name(int32_t id, int32_t long_name)
{
    const struct knob *k = knob_of(id);
    return !k ? 0 : long_name ? k->long_name : k->name;
}

const struct ae_name dist_names = {38, 88, dist_name};

/* dist.s's name gates: the first ae_names entry that names the id */
const char *dist_name_of(int32_t id, int32_t long_name)
{
    const struct ae_name *const *e;
    for (e = ae_names; *e; e++)
        if (id >= (*e)->first && id <= (*e)->last) {
            const char *n = (*e)->name(id, long_name);
            if (n)
                return n;
        }
    return 0;
}

void dist_tick(void *ctrl)
{
    static int ready;
    (void)ctrl;
    if (!ready) {
        unsigned i, j;
        ready = 1;
        for (i = 0; i < NKNOBS; i++) {
            uint32_t *r = (uint32_t *)(PARAM_INFO + PI_STRIDE * knobs[i].id);
            const uint32_t *f = (const uint32_t *)(PARAM_INFO + PI_STRIDE * FEEL);
            const uint32_t *d = (const uint32_t *)(PARAM_INFO + PI_STRIDE * knobs[i].donor);
            r[0] = f[0] | LOCK_OFF;
            for (j = 1; j < PI_STRIDE / 4; j++)     /* a dial's steps, feel and callbacks */
                r[j] = f[j];
            for (j = PI_DRAW / 4; j < PI_DRAW / 4 + 4; j++)
                r[j] = d[j];                        /* and the donor's art */
        }
    }
    cache_all();
}

void dist_project(int how, unsigned dropped)
{
    (void)how;
    (void)dropped;
    cache_all();
}
