/* SPDX-License-Identifier: MIT */
/* wave - the NOISE page's oscillator knobs (AE 0010) for the Analog Four
 * MKII, OS 1.56, on core-a4 0.2. wave.s is the oscillator.
 *
 * The NOISE page (page 7) is answered through core_pages with two more
 * knobs: D, the mode (OFF / WAV / CHD), and F, the chord (OCT 5TH MAJ MIN SU2
 * SU4 MA7 MI7 DO7 MI9 HDX SW1 SW2), each knob's name its value. While the
 * track's sound has WAV or CHD on, S&H, COL and FAD are named SHP, FLD and
 * FM (the oscillator's use of them).
 *
 *   knob  setting  the hidden record it is drawn as
 *   D     mode     37 (the synth's "None" record), as AMP PAN's marker
 *   F     chord    140 (the FX track's "None" record), as AMP CHO's dial
 *
 * Neither id is on a stock page, so core_params answers for them everywhere.
 * At the first tick their RAM records take a stock knob's whole record
 * (encoder feel, callbacks and dial art) and are marked unlockable (a turn
 * with a trig held makes no lock). The names, short under the knob and long
 * in the header while it turns, come through dist's ae_names table.
 *
 * The setting is a 6-bit sound field in core-a4's mod storage (wave_set:
 * chord type << 2 | mode), so it travels with the sound through kits, the
 * sound pool and copies. The UI tick copies each synth track's into wave_trk
 * for the audio interrupt, and an edit does at once.
 */
#include <stdint.h>
#include "analog-four-mk2/pages.h"
#include "analog-four-mk2/store.h"
#include "ae_names.h"

#define PROJECT_PTR 0x418717c8      /* the live project */
#define KIT_FX_STORAGE 0x11ac       /* the kit's FX storage, kit + 0x564 */
#define KIT_FROM_FX 0x564
#define KIT_SOUND0 0x1c             /* a kit's sounds, 0x152 bytes each */
#define SOUND_SIZE 0x152
#define ACTIVE_TRACK 48             /* project + 48: the active track's object */
#define TRACK_INDEX_OF 0x400adbd2
#define PARAM_INFO 0x41856c44       /* the RAM records, 0x54 bytes an id */
#define PI_STRIDE 0x54
#define LOCK_OFF 0x20               /* record +0 bit 5: the id takes no lock */

#define PAGE_NOISE 7
#define ID_MODE 37
#define ID_CHORD 140
#define ID_SNH 74
#define ID_COL 75
#define ID_FAD 76
#define NCHORDS 13
#define TURN 3                      /* turns a position */

typedef int32_t (*track_index_of_t)(void *);

STORE_FIELD(wave_set);

extern unsigned char wave_trk[];    /* wave.s: each synth track's mode byte */

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

static unsigned setting(int32_t t)
{
    void *s = sound(t);
    unsigned v = s ? core_store_get(STORE(wave_set), s, 0) : 0;
    if ((v & 3) == 3)
        v &= ~3u;
    if ((v >> 2) >= NCHORDS)
        v = (v & 3) | (NCHORDS - 1) << 2;
    return v;
}

static void cache_all(void)
{
    int32_t t;
    for (t = 0; t < 4; t++)
        wave_trk[t] = setting(t);
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

static int wave_get(int32_t id, int32_t *value)
{
    unsigned v = setting(active_track());
    if (id == ID_MODE)
        *value = (int32_t)(((v & 3) * 127 + 1) >> 1) << 8;     /* 0, 64, 127 */
    else if (id == ID_CHORD)
        *value = (int32_t)((v >> 2) * 127 / (NCHORDS - 1)) << 8;
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
    v = (unsigned)chord << 2 | (unsigned)mode;
    core_store_set(STORE(wave_set), s, 0, v);
    wave_trk[t] = v;
    return 1;
}

static const char *value_name(int32_t id)
{
    unsigned v = setting(active_track());
    return id == ID_MODE ? mode_names[v & 3] : chord_names[v >> 2];
}

static int wave_text(struct core_text *t)
{
    const char *s, *n;
    char *b = t->buf;
    if (t->id != ID_MODE && t->id != ID_CHORD)
        return CORE_TEXT_PASS;
    for (s = value_name(t->id), n = s; (*b++ = *n++) != 0;)
        ;
    return CORE_TEXT_DONE;
}

const struct core_param wave_mode_params = {ID_MODE, ID_MODE, wave_get, wave_delta, wave_text};
const struct core_param wave_chord_params = {ID_CHORD, ID_CHORD, wave_get, wave_delta, wave_text};

const struct core_page wave_noise_page = {PAGE_NOISE, "NOISE (P 2/2)",
                                          {ID_SNH, ID_COL, ID_FAD, ID_MODE, 77, ID_CHORD}};

/* the knobs' names: the two settings their value; S&H, COL and FAD the
 * oscillator's while the track's sound has it on */
static const char *wave_name(int32_t id, int32_t long_name)
{
    if (id == ID_MODE)
        return long_name ? "Wave Mode" : value_name(id);
    if (id == ID_CHORD)
        return long_name ? "Wave Chord" : value_name(id);
    if (id >= ID_SNH && id <= ID_FAD && (setting(active_track()) & 3)) {
        if (long_name)
            return id == ID_SNH ? "Wave Shape" : id == ID_COL ? "Wave Fold" : "Wave FM";
        return id == ID_SNH ? "SHP" : id == ID_COL ? "FLD" : "FM";
    }
    return 0;
}

const struct ae_name wave_names_osc = {ID_SNH, ID_FAD, wave_name};
const struct ae_name wave_names_mode = {ID_MODE, ID_MODE, wave_name};
const struct ae_name wave_names_chord = {ID_CHORD, ID_CHORD, wave_name};

void wave_tick(void *ctrl)
{
    static int ready;
    (void)ctrl;
    if (!ready) {
        static const int16_t ids[2][2] = {{ID_MODE, 97}, {ID_CHORD, 94}};
        unsigned i, j;
        ready = 1;
        for (i = 0; i < 2; i++) {
            uint32_t *r = (uint32_t *)(PARAM_INFO + PI_STRIDE * ids[i][0]);
            const uint32_t *d = (const uint32_t *)(PARAM_INFO + PI_STRIDE * ids[i][1]);
            r[0] = d[0] | LOCK_OFF;
            for (j = 1; j < PI_STRIDE / 4; j++)     /* the encoder's steps, feel, */
                r[j] = d[j];                        /* callbacks and dial art */
        }
    }
    cache_all();
}

void wave_project(int how, unsigned dropped)
{
    (void)how;
    (void)dropped;
    cache_all();
}
