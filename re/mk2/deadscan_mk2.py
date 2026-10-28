#!/usr/bin/env python3
"""deadscan_mk2.py mk2 [COVER_FILE ...] (re/os156/deadscan.py with an MKII entry:
no embedded bootstrap, code below 0x401865cc; x.../ and p156/m....dis as there,
with xmk2/ and p156/mmk2.dis for the MKII).

deadscan.py VER [COVER_FILE ...]: code in MAIN OS that nothing references.

A "routine" is a run of instructions from just after an unconditional end (rts,
rte, jmp, bra, unlk+rts...) to the next one. It is unreferenced when no branch/call
target and no 32-bit word anywhere in the image (2-byte aligned: vtables, pointer
tables, immediates, lea/pea operands) lands inside it. Coverage files from
`DTEMU_COVER` (dtboot) remove anything that ran. Prints contiguous unreferenced
runs, largest first, with flags:
  J  a computed jump (jmp/jsr through an indexed pc-relative or register EA) in the
     routine just before - its case table could target the run without a pointer
  X  executed in a coverage file (only listed with --all)
Run from a folder holding x155/ x156/ and p156/m155.dis m156.dis (P156_WORK)."""
import bisect, os, re, struct, sys

W = os.environ.get('P156_WORK', '.')
v = sys.argv[1]
covs = [a for a in sys.argv[2:] if not a.startswith('--')]
show_all = '--all' in sys.argv
B = 0x40000400
img = open(f'{W}/x{v}/section_3.bin', 'rb').read()
BOOT = {'mk2': (0, 0), '155': (0x40226958, 0x40233a30), '156': (0x40226ee8, 0x40233fc0)}[v]
CODE_END = {'155': 0x40169000, '156': 0x401694a0, 'mk2': 0x401865cc}[v]      # tables / strings above

RX = re.compile(r'^([0-9a-f]{8}):\t([0-9a-f ]+?)\s*\t(\S+)\s*(.*)$')
ins = []
for line in open(f'{W}/p156/m{v}.dis'):
    m = RX.match(line)
    if m:
        a = int(m.group(1), 16)
        if a < CODE_END:
            ins.append((a, m.group(3), m.group(4)))
addrs = [a for a, _, _ in ins]

# references: branch/call targets printed by objdump, and every aligned 32-bit word
refs = set()
TGT = re.compile(r'(?:^|[ ,(@])0x(4[0-2][0-9a-f]{6})')
for a, mn, op in ins:
    for h in TGT.findall(' ' + op):
        refs.add(int(h, 16))
for o in range(0, len(img) - 3, 2):
    x = struct.unpack('>I', img[o:o + 4])[0]
    if B <= x < CODE_END:
        refs.add(x)
# switch tables: `jmp %pc@(T,%xN:l)` with 16-bit offsets from T right after it;
# the table ends where the nearest forward target begins
SW = re.compile(r'^%pc@\(0x([0-9a-f]+),%[ad]\d:l(?::\d)?\)$')
nsw = 0
for a, mn, op in ins:
    m = SW.match(op) if mn == 'jmp' else None
    if not m:
        continue
    T = int(m.group(1), 16)
    nsw += 1
    lim, i = 1 << 32, 0
    while T + 2 * i < lim and i < 1024:
        off = struct.unpack('>h', img[T + 2 * i - B:T + 2 * i - B + 2])[0]
        tgt = T + off
        refs.add(tgt)
        if tgt > T:
            lim = min(lim, tgt)
        i += 1
refs = sorted(refs)
print(f'{nsw} switch tables decoded')

END = re.compile(r'^(rts|rte|jmp|bras|braw|bral|bra)$')
COMPUTED = re.compile(r'^(jmp|jsr)$')
# routines
routines = []
s = 0
for i, (a, mn, op) in enumerate(ins):
    if END.match(mn):
        routines.append((s, i))
        s = i + 1
covered = []
for f in covs:
    for line in open(f):
        p, q = line.split()
        covered.append((int(p, 16), int(q, 16)))
covered.sort()
cstarts = [p for p, _ in covered]


def ran(lo, hi):
    k = bisect.bisect_right(cstarts, hi - 1) - 1
    while k >= 0 and covered[k][1] > lo:
        if covered[k][0] < hi:
            return True
        k -= 1
    return False


def computed(si, ei):
    for j in range(si, ei + 1):
        a, mn, op = ins[j]
        if COMPUTED.match(mn) and ('pc@(' in op and ',%' in op or op.startswith('%a') and '@' in op):
            return True
    return False


out = []
prev_comp = False
cur = None
for si, ei in routines:
    if si > ei:
        continue
    lo = ins[si][0]
    hi = ins[ei + 1][0] if ei + 1 < len(ins) else CODE_END
    if BOOT[0] <= lo < BOOT[1]:
        continue
    k = bisect.bisect_left(refs, lo)
    referenced = k < len(refs) and refs[k] < hi
    x = ran(lo, hi)
    dead = not referenced and (not x or show_all)
    if dead:
        flags = ('J' if prev_comp else '') + ('X' if x else '')
        if cur and cur[1] == lo:
            cur[1] = hi; cur[2] += flags; cur[3] += 1
        else:
            if cur:
                out.append(cur)
            cur = [lo, hi, flags, 1]
    else:
        if cur:
            out.append(cur); cur = None
    prev_comp = computed(si, ei)
if cur:
    out.append(cur)

out.sort(key=lambda r: r[0] - r[1])
tot = sum(h - l for l, h, _, _ in out)
print(f'{len(out)} unreferenced runs, {tot} B')
for l, h, f, n in out[:40]:
    print(f'  {l:#010x}..{h:#010x} {h - l:6} B  {n:3} routine(s)  {"".join(sorted(set(f)))}')
