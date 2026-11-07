/* SPDX-License-Identifier: MIT */
/* wave - the NOISE page's oscillator knobs (AE 0010) for the Analog Four
 * MKII, OS 1.56, on core-a4 0.5. wave.s is the oscillator and the name gates.
 *
 * The NOISE page (page 7) is answered through core_pages with two more
 * knobs: D, the mode (OFF / WAV / CHD), and F, the chord (OCT 5TH MAJ MIN SU2
 * SU4 MA7 MI7 DO7 MI9 HDX SW1 SW2), each knob's name its value. While the
 * active track's sound has WAV or CHD on, S&H, COL and FAD are named SHP, FLD
 * and FM (the oscillator's use of them), there and in the lists that show
 * them (from core-a4 0.5 the name getters cannot tell who asks).
 *
 * The knobs are mod ids above 0x126 (0x310 mode, 0x311 chord), and both
 * settings are sound fields in core-a4's mod storage (wave_mode, 2 bits;
 * wave_chord, 4 bits), so they travel with the sound through kits, the sound
 * pool and copies. Both are lockable (core-a4 0.5): hold a trig and turn the
 * knob, or turn it in live recording, and that trig plays its own mode or
 * chord. The mode is a choice and takes locks only, landing at the trig. The
 * chord is also a destination ("mod": LFOs, envelopes, routes, macros,
 * CONTROL IN) with a CC, declared "smooth": false, so a change lands at once
 * and modulation and Param Slide step through the chord list one whole chord
 * at a time (core's value read, rounded). The chord's short name, CHRD, is
 * its knob's label and its name on a Dest knob; the mode's lock param carries
 * none, so core asks the name getters for its label, which wave.s answers
 * with the value. Each audio block (ev_render_out) wave_render puts each track's mode
 * (its trig's lock in its place) and chord (core's value read) into
 * wave_trk; the UI tick keeps the sounds' own in wave_base.
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

#define PAGE_NOISE 7
#define ID_MODE 0x310
#define ID_CHORD 0x311
#define ID_SNH 74
#define ID_COL 75
#define ID_FAD 76
#define NCHORDS 13
#define TURN 3                      /* turns a position */

typedef int32_t (*track_index_of_t)(void *);

STORE_FIELD(wave_mode);
STORE_FIELD(wave_chord);

const struct core_lock_param wave_lp_mode = {STORE(wave_mode), ID_MODE, 0, 2, 0, "Wave Mode",
                                             CORE_LOCK_CATEGORY("WAVE")};
const struct core_lock_param wave_lp_chord = {STORE(wave_chord), ID_CHORD, 0, NCHORDS - 1, "CHRD", "Wave Chord",
                                              CORE_LOCK_CATEGORY("WAVE")};

extern unsigned char wave_trk[];    /* wave.s: each synth track's mode byte */
static volatile unsigned char wave_base[4];   /* the sounds' own, chord << 2 | mode */

static const char mode_names[3][4] = {"OFF", "WAV", "CHD"};
static const char chord_names[NCHORDS][4] = {
    "OCT", "5TH", "MAJ", "MIN", "SU2", "SU4", "MA7", "MI7", "DO7", "MI9", "HDX", "SW1", "SW2"};

static unsigned char *project(void)
{
    return *(unsigned char **)PROJECT_PTR;
}

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

static unsigned clamp_mode(unsigned m)
{
    return m > 2 ? 0 : m;
}

static unsigned clamp_chord(unsigned c)
{
    return c >= NCHORDS ? NCHORDS - 1 : c;
}

/* track t's sound's setting, chord << 2 | mode */
static unsigned setting(int32_t t)
{
    void *s = sound(t);
    if (!s)
        return 0;
    return clamp_chord(core_store_get(STORE(wave_chord), s, 0)) << 2 |
           clamp_mode(core_store_get(STORE(wave_mode), s, 0));
}

static void cache_all(void)
{
    int32_t t;
    for (t = 0; t < 4; t++)
        wave_base[t] = setting(t);
}

/* stepped settings move once per TURN turns, as dist's do */
static int32_t step_of(int32_t delta, int32_t id)
{
    static int32_t acc_id, acc;
    int32_t d = delta < 0 ? -1 : 1;
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

/* the raw value, in 8.8 (a trig's lock is shown through wave_text too) */
static int wave_get(int32_t id, int32_t *value)
{
    unsigned v = setting(active_track());
    if (id == ID_MODE)
        *value = (int32_t)(v & 3) << 8;
    else if (id == ID_CHORD)
        *value = (int32_t)(v >> 2) << 8;
    else
        return 0;
    return 1;
}

static int wave_delta(void *view, int32_t id, int32_t delta, int32_t func)
{
    int32_t t = active_track(), mode, chord;
    void *s = sound(t);
    unsigned v;
    (void)view;
    (void)func;
    if (id != ID_MODE && id != ID_CHORD)
        return 0;
    if (!s)
        return 1;
    v = setting(t);
    mode = v & 3;
    chord = v >> 2;
    if (id == ID_MODE) {
        mode += step_of(delta, id);
        mode = mode < 0 ? 0 : mode > 2 ? 2 : mode;
    } else {
        chord += step_of(delta, id);
        chord = chord < 0 ? 0 : chord > NCHORDS - 1 ? NCHORDS - 1 : chord;
    }
    if (id == ID_MODE)
        core_store_set(STORE(wave_mode), s, 0, (unsigned)mode);
    else
        core_store_set(STORE(wave_chord), s, 0, (unsigned)chord);
    cache_all();
    return 1;
}

static const char *value_name(int32_t id)
{
    unsigned v = setting(active_track());
    return id == ID_MODE ? mode_names[v & 3] : chord_names[v >> 2];
}

/* the value's text, from the value turned or locked */
static int wave_text(struct core_text *t)
{
    const char *n;
    char *b = t->buf;
    unsigned v = ((unsigned)t->value >> 8) & 0xff;
    if (t->id == ID_MODE)
        n = mode_names[clamp_mode(v)];
    else if (t->id == ID_CHORD)
        n = chord_names[clamp_chord(v)];
    else
        return CORE_TEXT_PASS;
    while ((*b++ = *n++) != 0)
        ;
    return CORE_TEXT_DONE;
}

const struct core_param wave_mode_params = {ID_MODE, ID_MODE, wave_get, wave_delta, wave_text};
const struct core_param wave_chord_params = {ID_CHORD, ID_CHORD, wave_get, wave_delta, wave_text};

const struct core_page wave_noise_page = {PAGE_NOISE, "NOISE (P 2/2)",
                                          {ID_SNH, ID_COL, ID_FAD, ID_MODE, 77, ID_CHORD}};

/* wave.s's name gates: the mode its value (the chord's are core's); S&H, COL and FAD the
 * oscillator's while the active track's sound has it on; 0 for any other id */
const char *wave_name_of(int32_t id, int32_t long_name)
{
    if (id == ID_MODE)
        return long_name ? "Wave Mode" : value_name(id);
    if (id >= ID_SNH && id <= ID_FAD && (setting(active_track()) & 3)) {
        if (long_name)
            return id == ID_SNH ? "Wave Shape" : id == ID_COL ? "Wave Fold" : "Wave FM";
        return id == ID_SNH ? "SHP" : id == ID_COL ? "FLD" : "FM";
    }
    return 0;
}

/* each audio block, after core's snapshot: each synth track's mode (its
 * trig's lock in its place) and chord (core's value read, unsmoothed, rounded
 * to a whole chord) */
void wave_render(void)
{
    static int h;
    int32_t t, m, c;
    if (!h)
        h = core_param_handle(STORE(wave_chord));
    for (t = 0; t < 4; t++) {
        m = core_lock_value(t, STORE(wave_mode));
        m = m >= 0 ? (int32_t)clamp_mode(m) : wave_base[t] & 3;
        c = wave_base[t] >> 2;
        if (m) {
            core_param_values(t, &h, 1, 0, &c);
            c = c == CORE_PARAM_NONE ? wave_base[t] >> 2 : (c + 128) >> 8;
            c = c < 0 ? 0 : (int32_t)clamp_chord(c);
        }
        wave_trk[t] = c << 2 | m;
    }
}

void wave_tick(void *ctrl)
{
    (void)ctrl;
    cache_all();
}

void wave_project(int how, unsigned dropped)
{
    (void)how;
    (void)dropped;
    cache_all();
}
