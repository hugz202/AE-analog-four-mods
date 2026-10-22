#!/usr/bin/env python3
"""Map every MK1 OS 1.56 address the shipped mods depend on into the MKII OS 1.56.

re/os156/map156.py run across devices: the working folder's "155" is the MK1 1.56
image and "156" the MKII 1.56 image (x155/, x156/ from tools/unpack.py, p156/m155.dis
and p156/m156.dis from tools/disasm.sh), and A4_PROJECT points at a checkout of the
OS-1.56 branch, whose re/symbols.toml and registry hold the MK1 addresses. The
result is re/mk2's input for re/symbols.toml and registry/allocations.toml on this
branch; every weak match it flags was checked by hand (docs/PORT-MK2.md).

Sources: re/symbols.toml (all addr fields), registry/allocations.toml (detours,
patches), and hex addresses hard-coded in the shipped stubs. Code addresses are
matched with xmatch's k-gram vote and checked by comparing the normalised listings
around both; data addresses by voting over the instructions that reference them
(each mapped as code, its operand read in 1.56); table entries without references
of their own by the shift of the nearest referenced address below, checked by
comparing the bytes."""
import bisect, collections, json, re, sys, tomllib

A = __import__('os').environ.get('A4_PROJECT', '.')  # the project root (this repo)
W = __import__("os").environ.get("P156_WORK", ".")  # x155/ x156/ from tools/unpack.py, p156/m155.dis m156.dis
sys.path.insert(0, A + '/tools')
import xmatch

BASE = 0x40000400
img = {v: open(f'{W}/x{v}/section_3.bin', 'rb').read() for v in (155, 156)}
END = {v: BASE + len(img[v]) for v in img}
M = {v: xmatch.load(f'{W}/p156/m{v}.dis') for v in (155, 156)}
SHIP = ('0001', '0002', '0006', '0007', '0008', '0010')


def rd(v, a, n):
    return img[v][a - BASE:a - BASE + n]


# ------------------------------------------------------------------ collect
want = collections.OrderedDict()   # addr -> set of reasons


def add(a, why):
    want.setdefault(a, set()).add(why)


sym = tomllib.load(open(A + '/re/symbols.toml', 'rb'))
symname = {}
for kind in ('fn', 'data'):
    for name, d in sym.get(kind, {}).items():
        if 'addr' in d:
            add(d['addr'], f'{kind}.{name}')
            symname[d['addr']] = name

reg = tomllib.load(open(A + '/registry/allocations.toml', 'rb'))
for kind in ('detour', 'patch'):
    for e in reg.get(kind, []):
        if e['owner'].startswith(SHIP):
            add(e['addr'], f"{kind}:{e['owner'][:4]}")

hexre = re.compile(r'0x(4[0-7][0-9a-f]{6}|80[0-9a-f]{6})', re.I)
for m in SHIP:
    import glob
    for f in glob.glob(f'{A}/mods/{m}*/stub.s'):
        for line in open(f, encoding='utf-8'):
            code = line.split('|')[0]
            for h in hexre.findall(code):
                add(int(h, 16), f'stub:{m}')

# tables the patches and pools are defined against (registry notes)
for x, why in []:
    add(x, why)

# ------------------------------------------------------------------ helpers
a155, n155, t155, _ = M[155]
a156, n156, t156, _ = M[156]


def is_insn(v, a):
    arr = M[v][0]
    i = bisect.bisect_left(arr, a)
    return i < len(arr) and arr[i] == a


def window_diff(x, y, n=8):
    i = bisect.bisect_left(a155, x); j = bisect.bisect_left(a156, y)
    d = 0
    for k in range(-n, n + 1):
        if 0 <= i + k < len(n155) and 0 <= j + k < len(n156):
            d += n155[i + k] != n156[j + k]
    return d


def map_code(x):
    r = xmatch.find(M[155], M[156], x)
    if not r:
        return None
    y, vote = r[0]
    return y, vote, window_diff(x, y)


TOK = re.compile(r'0x[0-9a-f]+|-?\b\d{6,}\b')


def toks(s):
    out = []
    for t in TOK.findall(s):
        v = int(t, 16) if t.startswith('0x') else int(t)
        out.append(v & 0xffffffff)
    return out


# references: 1.55 instruction index lists per absolute value
refs = collections.defaultdict(list)
for i, s in enumerate(t155):
    for v in toks(s):
        refs[v].append(i)


def map_data(x):
    votes = collections.Counter()
    for i in refs.get(x, [])[:60]:
        ia = a155[i]
        r = xmatch.find(M[155], M[156], ia)
        if not r or r[0][1] < 10:
            continue
        j = bisect.bisect_left(a156, r[0][0])
        if j >= len(a156) or a156[j] != r[0][0]:
            continue
        t1, t2 = toks(t155[i]), toks(t156[j])
        if len(t1) != len(t2):
            continue
        for p, q in zip(t1, t2):
            if p == x:
                votes[q] += 1
    return votes


# ------------------------------------------------------------------ map
res = {}
data_ok = {}
def containing(v, a):
    arr = M[v][0]
    i = bisect.bisect_right(arr, a) - 1
    return arr[i] if i >= 0 else None


for x, why in want.items():
    kind = None
    if BASE <= x < 0x40180000 and not is_insn(155, x) and \
            any(w.startswith(('patch', 'detour')) for w in why):
        c = containing(155, x)                    # an operand inside an instruction
        mc = map_code(c) if c else None
        if mc:
            y, vote, diff = mc
            res[x] = dict(kind='code', to=y + (x - c), vote=vote, diff=diff, why=sorted(why), note=f'operand of {c:#x}')
            continue
    if BASE <= x < 0x40180000 and is_insn(155, x):
        mc = map_code(x)
        if mc:
            y, vote, diff = mc
            kind = 'code'
            res[x] = dict(kind='code', to=y, vote=vote, diff=diff, why=sorted(why))
            continue
    votes = map_data(x)
    if votes:
        (y, n), = votes.most_common(1)
        tot = sum(votes.values())
        res[x] = dict(kind='data', to=y, votes=f'{n}/{tot}', why=sorted(why))
        data_ok[x] = y
    else:
        res[x] = dict(kind='unref', to=None, why=sorted(why))

# unreferenced: by the nearest referenced data address below (same shift), checked
known = sorted(data_ok.items())
for x, r in res.items():
    if r['kind'] != 'unref':
        continue
    if not (BASE <= x < END[155]):
        r['note'] = 'outside the image (RAM)'
        continue
    k = bisect.bisect_right([p for p, _ in known], x) - 1
    if k >= 0 and x - known[k][0] < 0x2000:
        sh = known[k][1] - known[k][0]
        y = x + sh
        same = rd(155, x, 32) == rd(156, y, 32)
        r.update(kind='table', to=y, note=f'shift {sh:+d} from {known[k][0]:#x}, 32 bytes {"equal" if same else "DIFFER"}')

json.dump({f'{k:#010x}': v for k, v in res.items()}, open(f'{W}/p156/map.json', 'w'), indent=1, default=str)

# ------------------------------------------------------------------ report
def fmt(x, r):
    to = f"{r['to']:#010x}" if r.get('to') is not None else '-'
    ev = ''
    if r['kind'] == 'code':
        ev = f"vote {r['vote']:5}  listing diffs {r['diff']}/17"
    elif r['kind'] == 'data':
        ev = f"refs {r['votes']}"
    else:
        ev = r.get('note', '')
    sh = f"{(r['to'] - x):+6d}" if r.get('to') is not None else '      '
    return f"{x:#010x} -> {to} {sh}  {r['kind']:5}  {ev:32}  {', '.join(r['why'])[:70]}"


bad = []
for x, r in sorted(res.items()):
    line = fmt(x, r)
    weak = (r['kind'] == 'code' and (r['vote'] < 8 or r['diff'] > 2)) or \
           (r['kind'] == 'data' and int(r['votes'].split('/')[0]) * 2 <= int(r['votes'].split('/')[1])) or \
           (r['kind'] == 'table' and 'DIFFER' in r.get('note', '')) or r['kind'] == 'unref'
    print(('!! ' if weak else '   ') + line)
    if weak:
        bad.append(x)
print(f'\n{len(res)} addresses, {len(bad)} need a look')
