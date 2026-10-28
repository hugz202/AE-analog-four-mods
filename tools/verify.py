#!/usr/bin/env python3
"""Post-build checks: the .syx round-trips, the sections we do not touch come back
unchanged, and the image differs from stock in exactly the regions the registry
claims - nothing else moved."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import layout
import symbols as symmod
from toolchain import tool
import unpack

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
STOCK_SYX = ROOT / "stock" / symmod.load(ROOT / "re" / "symbols.toml")["meta"]["stock_syx"]
EFT = ROOT / "vendor" / "elektron-firmware-tool" / "elektron-firmware-tool"


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"failed: {' '.join(map(str, cmd))}\n{p.stdout}{p.stderr}")
    return p.stdout


def diff_regions(a: bytes, b: bytes, base: int):
    """Contiguous differing spans, merged across gaps of < 16 identical bytes."""
    spans, i, n = [], 0, len(a)
    while i < n:
        if a[i] != b[i]:
            j = i
            gap = 0
            k = i
            while k < n and gap < 16:
                if a[k] != b[k]:
                    j = k
                    gap = 0
                else:
                    gap += 1
                k += 1
            spans.append((i + base, j - i + 1))
            i = j + 1
        else:
            i += 1
    return spans


def inplace_gap(stored: bytes, stage: int, load: int) -> int:
    """The bootstrap copies the packed MAIN OS section (its 8-byte [len][sum]
    header included) to `stage` and depacks it to `load`, over itself. Returns the
    smallest distance between the next byte the depacker writes and the next byte
    it has still to read; it must stay above 0, or the depack eats its own input
    and the unit runs a corrupt OS."""
    b = unpack.Bits(stored, 8)
    lead = stage - load                 # where the stream sits, seen from the output
    n, last, low = 0, 1, None
    while True:
        if b.bit():
            b.byte()
            n += 1
            d = lead + b.p - n
        else:
            g = b.gamma()
            if g == 2:
                off = last
            else:
                off = ((g << 8) + b.byte()) & 0xFFFFFFFF
                if off == 767:
                    break
                off = (off - 767) & 0xFFFFFFFF
                last = off
            sl = 2 * b.bit() + b.bit()
            L = sl if sl else b.gamma() + 2
            if off > 3328:
                L += 1
            n += L + 1
            d = lead + b.p - n
        low = d if low is None or d < low else low
    return low


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default=None, help="defaults to the most recent build")
    args = ap.parse_args()

    if args.tag is None:
        found = sorted(BUILD.glob("manifest_*.json"), key=lambda f: f.stat().st_mtime)
        if not found:
            raise SystemExit("no build found; run tools/build.py first")
        args.tag = found[-1].stem[len("manifest_"):]

    syms = symmod.load(ROOT / "re" / "symbols.toml")
    meta = syms["meta"]
    base = meta["base"]
    reg = layout.load(ROOT / "registry" / "allocations.toml")
    manifest = json.loads((BUILD / f"manifest_{args.tag}.json").read_text())

    stock = (BUILD / "stock_mainos.bin").read_bytes()
    patched = (BUILD / f"mainos_{args.tag}.bin").read_bytes()
    syx = BUILD / manifest["syx"]

    ok = True

    # The vendored tool can rebuild a container verbatim. That gives this project the
    # null-repack self-check octatrack-mods never had: if re-emitting the manufacturer's own
    # file does not reproduce it byte for byte, the packer is not trustworthy and no
    # claim about our own output means anything.
    null = BUILD / "null_repack.syx"
    run([EFT, "-i", STOCK_SYX, "-r", "-o", null])
    if null.read_bytes() == STOCK_SYX.read_bytes():
        print("ok   null repack: stock .syx rebuilds byte-identically")
    else:
        print("FAIL null repack: rebuilding the untouched stock .syx changed it")
        ok = False

    if len(stock) != len(patched):
        print(f"FAIL size {len(stock)} -> {len(patched)}")
        ok = False
    else:
        print(f"ok   size unchanged ({len(patched)} B)")

    # round-trip: unpack what we just packed, expect the same MAIN OS back, and expect
    # every other section to be exactly what stock carried - above all the bootstrap,
    # which is the recovery path and which nothing here is allowed to disturb.
    tmp = BUILD / "verify_extract"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    run([EFT, "-i", syx, "-o", tmp])
    back = (tmp / "section_3_MAIN_OS.bin").read_bytes()
    if back == patched:
        print(f"ok   {syx.name} round-trips to a byte-identical MAIN OS")
    else:
        print(f"FAIL round-trip differs (got {len(back)} B, "
              f"sha {hashlib.sha256(back).hexdigest()[:16]})")
        ok = False

    if "embedded_bootstrap_start" in meta:
        # The MK1: no bootstrap SECTION - the bootstrap image is inside MAIN OS and
        # the OS flashes it itself when its version word is newer. It must be stock,
        # byte for byte.
        lo = meta["embedded_bootstrap_start"] - base
        hi = meta["embedded_bootstrap_end"] - base
        if hashlib.sha256(back[lo:hi]).hexdigest() == meta["embedded_bootstrap_sha256"]:
            print(f"ok   embedded bootstrap image unchanged ({hi - lo:,} B) - recovery path intact")
        else:
            print(f"FAIL the embedded bootstrap image 0x{lo + base:08x}..0x{hi + base:08x} changed")
            ok = False

    # Every section but MAIN OS must come back exactly as stock carried it - above
    # all the MKII's bootstrap section (the STARTUP menu, the recovery path).
    want = sorted(meta.get("other_sections", []))
    extra = sorted(f.name for f in tmp.iterdir() if f.name != "section_3_MAIN_OS.bin")
    if extra != want:
        print(f"FAIL the rebuilt .syx carries {extra} beside MAIN OS, stock {want}")
        ok = False
    else:
        stock_x = BUILD / "extract"
        same = [n for n in want if (tmp / n).read_bytes() == (stock_x / n).read_bytes()]
        if same == want:
            print(f"ok   every other section is stock: {', '.join(want) or 'none (MAIN OS only)'}")
        else:
            print(f"FAIL sections changed: {sorted(set(want) - set(same))}")
            ok = False

    # The MKII bootstrap stages the packed MAIN OS at `stage` and depacks it over
    # itself; the container also has to end below the flash the OS keeps for itself.
    if "stage" in meta:
        _, stream = unpack.transport_decode(syx.read_bytes())
        _, cont, secs = unpack.parse_container(stream)
        main_sec = next(cont[o:o + n] for sid, o, n, _ in secs if sid == 3)
        gap = inplace_gap(main_sec, meta["stage"], base)
        if gap > 0:
            print(f"ok   MAIN OS depacks in place with {gap:,} B to spare")
        else:
            print(f"FAIL MAIN OS overruns its own packed input in place (gap {gap})")
            ok = False
        end = meta["flash_at"] + len(cont)
        if end <= meta["flash_limit"]:
            print(f"ok   container ends at flash 0x{end:06x} (limit 0x{meta['flash_limit']:06x})")
        else:
            print(f"FAIL container ends at flash 0x{end:06x}, past 0x{meta['flash_limit']:06x}")
            ok = False

    # the diff must be exactly the claimed regions
    claimed = []
    for c in reg.get("cave", []):
        claimed.append((c["addr"], c["size"], f"cave/{c['owner']}"))
    for d in reg.get("detour", []):
        claimed.append((d["addr"], d["size"], f"detour/{d['owner']}"))
    for q in reg.get("patch", []):
        claimed.append((q["addr"], q["size"], f"patch/{q['owner']}"))

    spans = diff_regions(stock, patched, base)
    print(f"     {len(spans)} differing region(s):")
    for addr, size in spans:
        # The assertion is that every byte which ACTUALLY CHANGED lies inside some
        # claim - not that the whole span sits inside one. diff_regions deliberately
        # bridges short runs of identical bytes, so a span can legitimately straddle
        # two claims and the untouched bytes between them.
        off0 = addr - base
        owners, unclaimed = [], []
        for k in range(size):
            if stock[off0 + k] == patched[off0 + k]:
                continue
            va = base + off0 + k
            hit = next((n for a, sz, n in claimed if a <= va < a + sz), None)
            if hit is None:
                unclaimed.append(va)
            elif hit not in owners:
                owners.append(hit)
        if unclaimed:
            print(f"FAIL   0x{addr:08x} +{size:<4} UNCLAIMED - "
                  f"{len(unclaimed)} changed byte(s) outside the registry, "
                  f"first at 0x{unclaimed[0]:08x}")
            ok = False
        else:
            print(f"ok     0x{addr:08x} +{size:<4} {', '.join(owners)}")

    # every detour in the built image must jump to the symbol the build resolved -
    # a stale detour pointing into a stub that moved is a known way to brick the unit
    for q in manifest.get("patches", []):
        off = q["addr"] - base
        want = bytes.fromhex(q["replace"])
        got = bytes(patched[off:off + len(want)])
        if got == want:
            print(f"ok   patch 0x{q['addr']:08x} holds {want.hex()}")
        else:
            print(f"FAIL patch 0x{q['addr']:08x} holds {got.hex()}, expected {want.hex()}")
            ok = False
    for d in manifest.get("detours", []):
        off = d["addr"] - base
        got = bytes(patched[off:off + 6])
        want = b"\x4e\xf9" + d["target"].to_bytes(4, "big")
        if got == want:
            print(f"ok   detour 0x{d['addr']:08x} -> {d['entry']} @ 0x{d['target']:08x}")
        else:
            print(f"FAIL detour 0x{d['addr']:08x} holds {got.hex()}, expected {want.hex()}")
            ok = False

    # the displaced bytes must reappear verbatim inside the owner's stub - catches a
    # prologue that was never re-emitted, or re-emitted with the wrong registers.
    #
    # A detour may opt out with `reemit = false`, for the case where the stub
    # REIMPLEMENTS the displaced instructions instead of replaying them and resumes
    # past them. That is a real pattern, but it is also exactly how a forgotten
    # prologue looks, so the opt-out is per-claim, must be written down in the
    # registry next to the reasoning, and is reported here rather than skipped.
    # A mod may hold several claims across pools, so the block a stub is searched in
    # is all of them joined. A sequence spanning the join is not a real match, but
    # these are presence heuristics and the odds of a false one are negligible.
    caves = {}
    for c in reg.get("cave", []):
        caves.setdefault(c["owner"], []).append(c)
    def stub_bytes(mid):
        return b"".join(bytes(patched[c["addr"] - base: c["addr"] - base + c["size"]])
                        for c in caves[mid])
    for d in manifest.get("detours", []):
        blk = stub_bytes(d["mod"])
        want = bytes.fromhex(d["displaced"])
        if not d.get("reemit", True):
            state = "also present" if want in blk else "absent as declared"
            print(f"ok   displaced {want.hex()} for 0x{d['addr']:08x} REIMPLEMENTED "
                  f"in {d['mod']}'s stub, not re-emitted ({state})")
        elif want in blk:
            print(f"ok   displaced {want.hex()} re-emitted in {d['mod']}'s stub")
        else:
            print(f"FAIL displaced {want.hex()} for 0x{d['addr']:08x} never re-emitted "
                  f"in {d['mod']}'s stub")
            ok = False

    # and it must rejoin stock exactly past the instructions it re-emitted. The
    # default is addr + the displaced length. A detour that deliberately resumes
    # further on says so with `rejoin = 0x...`, and one that handles the call outright
    # and returns says `rejoin = "none"`; both are declared in the registry and
    # reported here rather than skipped.
    #
    # What this catches: `expect` claiming more bytes than the stub actually rejoins
    # past. That is how 0004 shipped a stub that re-emitted a call AND the `addql`
    # after it, then landed back on that same `addql`, popping the arguments twice and
    # corrupting the stack of every list the constructor built - stock's own included.
    # Nothing else noticed: the displaced bytes were all present and the jmp target
    # was a real instruction.
    #
    # What it does NOT catch: a stub that re-emits an extra instruction the registry
    # never claimed, with `expect` and the jmp both self-consistent. Seeing that needs
    # the stub decoded, not just searched. The byte check below only spots it in the
    # narrow case where the duplicate sits immediately before the jmp.
    for d in manifest.get("detours", []):
        blk = stub_bytes(d["mod"])
        rejoin = d.get("rejoin")
        if rejoin == "none":
            print(f"ok   detour 0x{d['addr']:08x} handles it outright in {d['mod']}'s "
                  f"stub, no rejoin declared")
            continue
        want = b"\x4e\xf9" + int(rejoin).to_bytes(4, "big")
        past = d["addr"] + len(bytes.fromhex(d["displaced"]))
        where = "" if rejoin == past else f" (declared, not the default 0x{past:08x})"
        if want in blk:
            # ... and it must not re-emit the instruction it rejoins. The stub ending
            # <stock bytes at rejoin><jmp rejoin> means that instruction runs twice,
            # which no other check sees: the displaced bytes are all present and the
            # jmp lands where it should.
            at = blk.index(want)
            dup = next((n for n in (2, 4, 6)
                        if at >= n and blk[at - n:at] == stock[rejoin - base: rejoin - base + n]),
                       None)
            if dup:
                print(f"FAIL detour 0x{d['addr']:08x} re-emits the {dup} byte(s) at "
                      f"0x{rejoin:08x} and then rejoins there, so stock runs them "
                      f"twice - re-emit only what the detour displaced")
                ok = False
            else:
                print(f"ok   detour 0x{d['addr']:08x} rejoins 0x{rejoin:08x}{where}")
        else:
            print(f"FAIL detour 0x{d['addr']:08x} never jumps to 0x{rejoin:08x}{where} "
                  f"in {d['mod']}'s stub - re-emitting past the displaced bytes runs "
                  f"stock instructions twice")
            ok = False

    # ------------------------------------------------------------------
    # Stack frames. A `movem` that saves N registers at offset X needs the
    # frame to be at least X + 4N bytes; one long short and it writes over the
    # return address the bsr pushed, and the stub faults on its rts.
    #
    # Rytm hardware, 2026-09-20: rytm-mods' mod 0006 did exactly this - `lea -96(%sp),%sp`
    # with `movem.l %d2-%d4/%a3,88(%sp)`, four registers ending at 104 - and
    # the unit threw V03 at 0x40289E36, which is that rts. It is invisible to
    # every other check here because the image is perfectly well formed.
    order = "d0 d1 d2 d3 d4 d5 d6 d7 a0 a1 a2 a3 a4 a5 fp sp".split()

    def nregs(spec):
        n = 0
        for part in spec.replace("%", "").split("/"):
            if "-" in part:
                a, b = part.split("-")
                n += order.index(b) - order.index(a) + 1
            else:
                n += 1
        return n

    for mod in sorted({m["mod"] for m in manifest.get("mods", [])}):
        elf = BUILD / "obj" / f"{mod}.elf"
        if not elf.exists():
            continue
        try:
            # No -m: objdump rejects "m68k:5475" with a non-zero exit while still
            # printing the disassembly, and the ELF carries its own arch anyway.
            dis = subprocess.run([tool("objdump"), "-d", str(elf)],
                                 capture_output=True, text=True).stdout
        except OSError:
            print(f"warn {mod}: could not disassemble for the frame check")
            continue
        frame = None
        for line in dis.splitlines():
            m = re.search(r"lea %sp@\(-(\d+)\),%sp", line)
            if m:
                frame = int(m.group(1))
                continue
            m = re.search(r"moveml %(\S+),%sp@(?:\((\d+)\))?", line)
            if m and frame is not None:
                at = int(m.group(2) or 0)
                end = at + nregs(m.group(1)) * 4
                if end > frame:
                    print(f"FAIL {mod}: movem saves {nregs(m.group(1))} registers at "
                          f"{at} of a {frame}-byte frame, ending at {end} - it "
                          f"overwrites the return address; widen the frame to {end}")
                    ok = False

    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
