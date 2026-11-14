/* SPDX-License-Identifier: MIT */
/* res-limit - AE 0012 (resonance limit) for the Analog Four MKII, OS 1.56, on
 * core-a4mk2 0.7. res-limit.s is the engine gate and the SOUND SETUP item.
 *
 * The setting is one bit per synth track (bit t of res_lim, a kit field in
 * core's mod storage: decided 2026-11-14, so it builds beside dist, which
 * fills the sound's 32 bits). The UI tick (and each project load) copies the
 * current kit's bits into res_on, which the audio interrupt reads; the menu
 * item reads and writes the field through lim_get / lim_set. */
#include <stdint.h>
#include "analog-four-mk2/store.h"

#define PROJECT_PTR 0x418717c8      /* the live project */
#define KIT_FX_STORAGE 0x11ac       /* the kit's FX storage, kit + 0x564 */
#define KIT_FROM_FX 0x564
#define ACTIVE_TRACK 48             /* project + 48: the active track's object */
#define TRACK_INDEX_OF 0x400adbd2

typedef int32_t (*track_index_of_t)(void *);

STORE_FIELD(res_lim);

volatile unsigned char res_on[4];   /* res-limit.s: each synth track's switch */

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

/* the active track's switch: 1 on, 0 off, -1 not a synth track */
int32_t lim_get(void)
{
    int32_t t = active_track();
    if (t < 0 || t > 3 || !kit())
        return -1;
    return (int32_t)(bits() >> t & 1);
}

/* on > 0: on; else off. Nothing on the FX and CV tracks. */
void lim_set(int32_t on)
{
    int32_t t = active_track();
    void *k = kit();
    unsigned b;
    if (t < 0 || t > 3 || !k)
        return;
    b = bits() & ~(1u << t);
    if (on > 0)
        b |= 1u << t;
    core_store_set(STORE(res_lim), k, 0, b);
    core_project_edited();
    cache_all();
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
