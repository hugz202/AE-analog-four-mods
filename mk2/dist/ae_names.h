/* SPDX-License-Identifier: MIT */
/* ae_names: knob names for the AE mods' pages on the Analog Four MKII.
 *
 * dist declares the table (mod.json "collections": {"ae_names": 4}) and owns
 * the entries of the parameter sets' two name getters: the short name
 * (0x4009e79e), which the knob draw prints under a knob, and the long name
 * (0x4009e7c2), which the header shows while a knob turns. Asked from those
 * two places only, the first entry whose range holds the id and whose name()
 * answers non-0 names it; otherwise stock's name stands (an LFO's
 * destination list keeps stock's names). A mod adds an entry with
 *
 *     {"to": "ae_names", "order": 50, "data": "00000000",
 *      "relocs": [[0, "abs32", "sym:my_names", 0]]}
 *
 *     const struct ae_name my_names = {37, 37, my_name};   // my_name(id, long_name)
 *
 * and "requires": ["core", "dist"]. name() runs in the UI task, with the C
 * convention. (A candidate for core-a4: the page tables name a knob only
 * through its record.)
 */
#ifndef AE_NAMES_H
#define AE_NAMES_H

#include <stdint.h>

struct ae_name {
    int32_t first, last;
    const char *(*name)(int32_t id, int32_t long_name);   /* 0: not named here */
};

extern const struct ae_name *const ae_names[];

#endif
