/* SPDX-License-Identifier: MIT */
/* res-limit - AE 0012 (resonance limit) for the Analog Four MKII, OS 1.56, on
 * core-a4mk2 0.8.
 *
 * SOUND SETUP (FUNC + OSC1) gets a RESONANCE LIMIT checkbox after F1
 * RESONANCE BOOST (core's ev_sound_setup and core_sound_setup_toggle). With it
 * on for a synth track, each voice playing that track gets F1 RES x 80/127 and
 * F2 RES x 64/127 after the modulation (knob, p-locks, LFOs, envelopes), in
 * core's ev_voice_params, before the firmware builds the filter words from
 * them. So the filters stay out of self-oscillation.
 *
 * The setting is one bit per synth track (bit t of res_lim, a kit field in
 * core's mod storage, 4 bits: decided 2026-11-14). The UI tick (and each
 * project load) copies the current kit's bits into res_on, which the audio
 * interrupt reads. */
#include <stdint.h>
#include "analog-four-mk2/store.h"
#include "analog-four-mk2/ui.h"

#define PROJECT_PTR 0x418717c8      /* the live project */
#define KIT_FX_STORAGE 0x11ac       /* the kit's FX storage, kit + 0x564 */
#define KIT_FROM_FX 0x564
#define ACTIVE_TRACK 48             /* project + 48: the active track's object */
#define TRACK_INDEX_OF 0x400adbd2

/* x 80/127 and x 64/127 (127 = 0x7f00 -> 0x5000 / 0x4000), << 16 */
#define F1_K 41283u
#define F2_K 33027u

typedef int32_t (*track_index_of_t)(void *);

STORE_FIELD(res_lim);

static volatile unsigned char res_on[4];

static unsigned char *project(void)
{
    return *(unsigned char **)PROJECT_PTR;
}

/* the live kit, as core-a4mk2's kit scope takes it */
static void *kit(void)
{
    unsigned char *p = project(), *s;
    if (!p)
        return 0;
    s = *(unsigned char **)(p + KIT_FX_STORAGE);
    return s ? s - KIT_FROM_FX : 0;
}

static int32_t active_track(void)
{
    unsigned char *p = project();
    if (!p)
        return -1;
    return ((track_index_of_t)TRACK_INDEX_OF)(p + ACTIVE_TRACK);
}

static unsigned bits(void)
{
    void *k = kit();
    return k ? core_store_get(STORE(res_lim), k, 0) & 15 : 0;
}

static void cache_all(void)
{
    unsigned b = bits();
    int32_t t;
    for (t = 0; t < 4; t++)
        res_on[t] = b >> t & 1;
}

/* ev_voice_params: the audio interrupt, every block */
void res_voice(uint16_t *words, const int32_t *voice_track)
{
    int v;
    for (v = 0; v < 4; v++) {
        uint32_t t = (uint32_t)voice_track[v];
        if (t > 3 || !res_on[t])
            continue;
        VOICE_WORD(words, VP_F1_RES, v) = (uint16_t)((VOICE_WORD(words, VP_F1_RES, v) * F1_K) >> 16);
        VOICE_WORD(words, VP_F2_RES, v) = (uint16_t)((VOICE_WORD(words, VP_F2_RES, v) * F2_K) >> 16);
    }
}

/* the row: 1 checked, 0 not, -1 no box (FX and CV tracks) */
static int lim_get(const struct core_toggle *t)
{
    int32_t tr = active_track();
    (void)t;
    if (tr < 0 || tr > 3 || !kit())
        return -1;
    return (int)(bits() >> tr & 1);
}

static void lim_set(const struct core_toggle *t, int on)
{
    int32_t tr = active_track();
    void *k = kit();
    unsigned b;
    (void)t;
    if (tr < 0 || tr > 3 || !k)
        return;
    b = bits() & ~(1u << tr);
    if (on > 0)
        b |= 1u << tr;
    core_store_set(STORE(res_lim), k, 0, b);
    core_project_edited();
    cache_all();
}

static const struct core_toggle res_row = {"RESONANCE LIMIT", lim_get, lim_set};

/* ev_sound_setup: SOUND SETUP's builder, after F1 RESONANCE BOOST's row */
void res_setup(void *menu)
{
    core_sound_setup_toggle(menu, &res_row);
}

void res_tick(void *ctrl)
{
    (void)ctrl;
    cache_all();
}

void res_project(int how, unsigned dropped)
{
    (void)how;
    (void)dropped;
    cache_all();
}
