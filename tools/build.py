#!/usr/bin/env python3
"""Build patched Analog Four MKII firmware from stock + the enabled mods.

Ported from the MK1 branches (OS-1.56, OS-1.55). The MK1 container carries ONE
section, MAIN OS, with the bootstrap riding inside it; the MKII container (ELE3)
carries five - meta, bootstrap, FPGA, MAIN OS and a panel MCU image - and the
bootstrap is a section of its own. Whatever re/symbols.toml [meta] says the stock
file holds is checked here; only MAIN OS is ever replaced (see docs/HAZARDS.md).

Every build starts from the pinned stock image and asserts its way forward:
stock checksum, extracted MAIN OS checksum and size, registry layout, the cave
target actually being free, and each detour host still holding its expected
stock bytes. Any mismatch aborts rather than producing a plausible-looking image.

Only MAIN OS (section 3) is ever rewritten. On a device whose bootstrap rides
inside MAIN OS (the MK1), never inside that embedded image either.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import layout
import symbols as symmod
from toolchain import tool

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / "build"
STOCK_SYX = ROOT / "stock" / symmod.load(ROOT / "re" / "symbols.toml")["meta"]["stock_syx"]
EFT_DIR = ROOT / "vendor" / "elektron-firmware-tool"
EFT = EFT_DIR / "elektron-firmware-tool"

MAINOS_SECTION = 3


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(cmd, **kw):
    proc = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if proc.returncode != 0:
        raise SystemExit(f"command failed: {' '.join(map(str, cmd))}\n{proc.stdout}{proc.stderr}")
    return proc.stdout


def check_stock():
    sums = (ROOT / "stock" / "SHA256SUMS").read_text().split()
    want = dict(zip(sums[1::2], sums[0::2]))
    for name, expect in want.items():
        got = sha256((ROOT / "stock" / name).read_bytes())
        if got != expect:
            raise SystemExit(f"stock/{name} checksum mismatch\n  want {expect}\n  got  {got}")


def ensure_tool():
    if not EFT.exists():
        run(["make"], cwd=EFT_DIR)
    if not EFT.exists():
        raise SystemExit(f"{EFT} missing; run `git submodule update --init` then `make` there")


def embedded_bootstrap_ok(img: bytes, meta) -> bool:
    if "embedded_bootstrap_start" not in meta:
        return True                     # the MKII: the bootstrap is its own section
    lo = meta["embedded_bootstrap_start"] - meta["base"]
    hi = meta["embedded_bootstrap_end"] - meta["base"]
    return sha256(img[lo:hi]) == meta["embedded_bootstrap_sha256"]


def extract_sections(meta) -> bytes:
    """Unpack stock once into build/extract; return the stock MAIN OS."""
    cache = BUILD / "stock_mainos.bin"
    if not cache.exists():
        tmp = BUILD / "extract"
        shutil.rmtree(tmp, ignore_errors=True)
        tmp.mkdir(parents=True)
        run([EFT, "-i", STOCK_SYX, "-o", tmp])
        src = tmp / f"section_{MAINOS_SECTION}_MAIN_OS.bin"
        if not src.exists():
            raise SystemExit(f"extraction produced no {src.name}; got {list(tmp.iterdir())}")
        others = sorted(f.name for f in tmp.iterdir() if f.name != src.name)
        if others != sorted(meta.get("other_sections", [])):
            raise SystemExit(f"stock should hold MAIN OS and {meta.get('other_sections', [])}, "
                             f"got also {others}")
        shutil.copy(src, cache)
    data = cache.read_bytes()
    if len(data) != meta["mainos_size"]:
        raise SystemExit(f"MAIN OS is {len(data)} B, expected {meta['mainos_size']}")
    if sha256(data) != meta["mainos_sha256"]:
        raise SystemExit(f"MAIN OS checksum mismatch: {sha256(data)}")
    if not embedded_bootstrap_ok(data, meta):
        raise SystemExit("embedded bootstrap checksum mismatch in the STOCK image")
    return data


def load_mods(only):
    mods = {}
    for d in sorted((ROOT / "mods").iterdir()):
        f = d / "mod.toml"
        if not f.is_file():
            continue
        with open(f, "rb") as fh:
            m = tomllib.load(fh)
        mod = m["mod"]
        mod["_dir"] = d
        mod["_sources"] = m.get("sources", {})
        mod["_params"] = dict(m.get("params", {}))
        mod["_provides"] = bool(mod.get("provides_shared"))
        mod["_needs_shared"] = bool(m.get("requires", {}).get("shared"))
        if only is not None:
            mod["enabled"] = mod["id"] in only
        mods[mod["id"]] = mod
    if only:
        missing = set(only) - set(mods)
        if missing:
            raise SystemExit(f"unknown mod(s): {', '.join(sorted(missing))}")
    return mods


def emit_shared_inc(syms, owner):
    """Write build/shared.inc: the provider's `shared_*` symbols, for other stubs.

    Only the shared_ prefix is exported, so a provider can keep private labels. The
    file is regenerated every build, and a stub that includes it without the provider
    enabled fails to assemble rather than linking against a stale address.
    """
    lines = [f"| Generated by tools/build.py from {owner} - do not edit.", ""]
    for name, addr in sorted(syms.items(), key=lambda kv: kv[1]):
        if name.startswith("shared_"):
            lines.append(f"        .equ    {name}, 0x{addr:08x}")
    (BUILD / "shared.inc").write_text("\n".join(lines) + "\n")


def assemble(mod, claims, params=None):
    """Assemble and link the stub across its cave claims.

    `claims` is the mod's list of registry cave entries, each naming the section it
    holds (`.text` unless it says otherwise). The pools are separate regions of the
    image and can never merge, so a mod larger than the biggest free run has to be
    split; giving each claim a section is how the linker is told where each part
    landed, and keeps the split visible in the registry rather than implied by size.

    Returns ({section: bytes}, symbols). Detour targets are resolved from `symbols`
    rather than assumed to be the start of the block: a mod may expose several entry
    points, and a detour left pointing at a stale offset is a known way to brick the
    unit.
    """
    stub = mod["_dir"] / mod["_sources"]["stub"]
    objdir = BUILD / "obj"
    objdir.mkdir(parents=True, exist_ok=True)
    obj = objdir / f"{mod['id']}.o"
    elf = objdir / f"{mod['id']}.elf"
    defs = []
    for k, v in sorted((params or {}).items()):
        defs += ["--defsym", f"P_{k.upper()}={int(v)}"]
    # ColdFire V4 with EMAC and NO FPU. On the MK1 -mcpu=5475 plus -mno-float makes any
    # FPU instruction an assembly error rather than a crash on the unit; the MKII's
    # MCF5441x is 54455 (no FPU at all), as elekloader's Analog Four MKII profile.
    meta = symmod.load(ROOT / "re" / "symbols.toml")["meta"]
    cpu = [f"-mcpu={meta.get('cpu', '5475')}", *meta.get("cpu_flags", ["-mno-float"])]
    run([tool("as"), *cpu, "-I", BUILD, "-I", ROOT, *defs, "-o", obj, stub])
    placed = []
    for c in claims:
        placed += [f"--section-start={c.get('section', '.text')}=0x{c['addr']:08x}"]
    run([tool("ld"), "-e", "0", *placed, "-o", elf, obj])
    sections = {}
    for c in claims:
        name = c.get("section", ".text")
        binf = objdir / f"{mod['id']}{name.replace('.', '_')}.bin"
        run([tool("objcopy"), "-O", "binary", "--only-section", name, elf, binf])
        sections[name] = binf.read_bytes()
    syms = {}
    for line in run([tool("nm"), elf]).splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1].upper() in ("T", "D", "B", "A"):
            syms[parts[2]] = int(parts[0], 16)
    return sections, syms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mods", nargs="*", default=None,
                    help="build only these mod ids (for hardware bisection)")
    ap.add_argument("--tag", default=None, help="output name suffix")
    ap.add_argument("--param", action="append", default=[], metavar="MOD:KEY=VAL",
                    help="override a mod param for an ablation build")
    args = ap.parse_args()

    BUILD.mkdir(exist_ok=True)
    syms = symmod.load(ROOT / "re" / "symbols.toml")
    meta = syms["meta"]
    base = meta["base"]
    reg = layout.load(ROOT / "registry" / "allocations.toml")

    check_stock()
    ensure_tool()
    img = bytearray(extract_sections(meta))
    # Kept pristine so a claim in a dead-code pool can be checked against the stock
    # bytes it was analysed on, rather than against zero: those pools hold routines,
    # not padding, so "is it all zeros" is the wrong question there.
    stock_img = bytes(img)

    reg_pools = reg.get("pool", [])

    def pool_for(c):
        """The pool a claim sits wholly inside, or None. layout.py already proved one
        exists for every claim, so None here only happens for a claim table with no
        pool of its own."""
        lo, hi = c["addr"], c["addr"] + c["size"]
        return next((p for p in reg_pools
                     if p["start"] <= lo and hi <= p["end"]), None)
    original_len = len(img)

    mods = load_mods(set(args.mods) if args.mods is not None else None)
    enabled = {i for i, m in mods.items() if m.get("enabled")}

    # Ablation overrides. Applied after defaults so the manifest records exactly what was
    # assembled, and unknown mods/keys abort rather than silently building the default.
    overrides: dict[str, dict[str, int]] = {}
    for spec in args.param:
        try:
            who, kv = spec.split(":", 1)
            key, val = kv.split("=", 1)
        except ValueError:
            raise SystemExit(f"--param must be MOD:KEY=VAL, got {spec!r}")
        if who not in mods:
            raise SystemExit(f"--param names unknown mod {who!r}")
        if key not in mods[who]["_params"]:
            known = ", ".join(sorted(mods[who]["_params"])) or "(none)"
            raise SystemExit(f"--param: {who} has no param {key!r}. Known: {known}")
        mods[who]["_params"][key] = int(val, 0)
        overrides.setdefault(who, {})[key] = int(val, 0)

    problems = layout.validate(reg, enabled,
                               {m: d["_params"] for m, d in mods.items()},
                               layout.load_excludes(ROOT))
    if problems:
        for p in problems:
            print("ERROR:", p)
        raise SystemExit(1)

    symmod.emit_inc(syms, BUILD / "symbols.inc")

    caves = {}
    for c in reg.get("cave", []):
        caves.setdefault(c["owner"], []).append(c)
    stub_symbols: dict[str, dict[str, int]] = {}
    applied = []

    # Providers assemble first: their symbols become build/shared.inc, which the
    # stubs that call into them include. Claim addresses are fixed in the registry,
    # so one pass is enough - nothing here depends on a provider's own size.
    providers = sorted(m for m in enabled if mods[m].get("_provides"))
    needs = sorted(m for m in enabled if mods[m].get("_needs_shared"))
    if needs and not providers:
        raise SystemExit(
            f"{', '.join(needs)} require the shared runtime, but no enabled mod "
            f"provides it - enable the provider or disable them"
        )

    for mid in sorted(enabled, key=lambda m: (not mods[m].get("_provides"), m)):
        mod = mods[mid]
        if not mod["_sources"].get("stub"):
            # a patch-only mod (raw byte edits, no code cave) - nothing to assemble
            stub_symbols[mid] = {}
            continue
        claim = [c for c in caves.get(mid, [])
                 if not layout.gated_out(c.get("gate"), mod["_params"], mid)]
        if not caves.get(mid):
            raise SystemExit(f"{mid} is enabled but has no cave claim in the registry")
        if not claim:
            stub_symbols[mid] = {}
            continue
        sections, stub_syms = assemble(mod, claim, mod["_params"])
        stub_symbols[mid] = stub_syms
        if mod.get("_provides"):
            emit_shared_inc(stub_syms, mid)
        for c in claim:
            name = c.get("section", ".text")
            code = sections[name]
            if len(code) > c["size"]:
                raise SystemExit(
                    f"{mid}: {name} is {len(code)} B but its cave claim at "
                    f"0x{c['addr']:08x} reserves {c['size']} B - widen the claim in "
                    f"registry/allocations.toml"
                )
            off = c["addr"] - base
            region = img[off:off + c["size"]]
            home = pool_for(c)
            if home is not None and home.get("stock") == "code":
                # A dead-code pool holds a routine nothing calls, so it is not zeros.
                # Two things are checked instead: the pool still holds the exact bytes
                # the reachability analysis was run on, and nothing has already been
                # written into this claim.
                lo, hi = home["start"] - base, home["end"] - base
                got = hashlib.sha256(stock_img[lo:hi]).hexdigest()
                want = home.get("expect_sha256")
                if want is None:
                    raise SystemExit(
                        f"pool {home['name']} is stock = \"code\" but has no "
                        f"expect_sha256; a dead-code pool has to name the bytes it was "
                        f"analysed on, or the claim is not guarded at all"
                    )
                if got != want:
                    raise SystemExit(
                        f"{mid}: pool {home['name']} does not hold the bytes it was "
                        f"analysed on - sha256 {got}, expected {want}. The pool is not "
                        f"the dead routine cavescan reported; re-run the analysis "
                        f"before putting anything here"
                    )
                if region != stock_img[off:off + c["size"]]:
                    raise SystemExit(
                        f"{mid}: cave at 0x{c['addr']:08x} in {home['name']} has "
                        f"already been written by an earlier claim"
                    )
            elif any(region):
                raise SystemExit(
                    f"{mid}: cave at 0x{c['addr']:08x} is not free - "
                    f"{sum(1 for b in region if b)} non-zero byte(s) already there"
                )
            img[off:off + len(code)] = code
            applied.append({"mod": mid, "stub_addr": c["addr"],
                            "stub_size": len(code), "section": name})

    detours_applied = []
    for det in sorted(reg.get("detour", []), key=lambda d: d.get("chain_pos", 0)):
        if det["owner"] not in enabled:
            continue
        if layout.gated_out(det.get("gate"), mods[det["owner"]]["_params"], det["owner"]):
            continue
        off = det["addr"] - base
        # expect covers the full displaced span the stub re-emits; verify all of it,
        # even though only the first `size` bytes are overwritten by the jmp.
        want = bytes.fromhex(det["expect"])
        got = bytes(img[off:off + len(want)])
        if got != want:
            raise SystemExit(
                f"{det['owner']}: detour host 0x{det['addr']:08x} holds {got.hex()}, "
                f"expected {want.hex()} - the address is wrong, the image is not stock, "
                f"or another mod already patched here"
            )
        entry = det["entry"]
        stub_syms = stub_symbols[det["owner"]]
        if entry not in stub_syms:
            raise SystemExit(
                f"{det['owner']}: detour at 0x{det['addr']:08x} names entry {entry!r}, "
                f"which the linked stub does not define. "
                f"Known: {', '.join(sorted(stub_syms)) or '(none)'}"
            )
        target = stub_syms[entry]
        if target % 2:
            raise SystemExit(
                f"{det['owner']}: entry {entry!r} resolved to 0x{target:08x}, an ODD "
                f"address. A detour installs `jmp <target>`, and an odd instruction "
                f"address is an ADDRESS ERROR on ColdFire (VEC 03) the first time the host "
                f"runs. Add `.align 2` before the label, and keep byte-sized state after "
                f"every entry point rather than between them."
            )
        owned = caves[det["owner"]]
        if not any(c["addr"] <= target < c["addr"] + c["size"] for c in owned):
            raise SystemExit(
                f"{det['owner']}: entry {entry!r} resolved to 0x{target:08x}, outside its "
                f"cave claims " + ", ".join(f"0x{c['addr']:08x}+0x{c['size']:x}"
                                            for c in owned)
            )
        img[off:off + 6] = b"\x4e\xf9" + target.to_bytes(4, "big")
        rejoin = det.get("rejoin")
        if rejoin is None:
            # where stock resumes: right past the instructions the stub re-emits
            rejoin = det["addr"] + len(want)
        elif rejoin != "none" and not isinstance(rejoin, int):
            raise SystemExit(
                f"{det['owner']}: detour at 0x{det['addr']:08x} has rejoin {rejoin!r}; "
                f"it must be an address or \"none\""
            )
        detours_applied.append(
            {"mod": det["owner"], "addr": det["addr"], "entry": entry,
             "target": target, "displaced": want.hex(), "rejoin": rejoin,
             "reemit": det.get("reemit", True)}
        )

    patches_applied = []
    for q in reg.get("patch", []):
        if q["owner"] not in enabled:
            continue
        if layout.gated_out(q.get("gate"), mods[q["owner"]]["_params"], q["owner"]):
            continue
        off = q["addr"] - base
        want = bytes.fromhex(q["expect"])
        if "from_symbol" in q:
            stub_syms = stub_symbols.get(q["owner"], {})
            if q["from_symbol"] not in stub_syms:
                raise SystemExit(f"{q['owner']}: no symbol `{q['from_symbol']}` in its stub")
            repl = stub_syms[q["from_symbol"]].to_bytes(4, "big")
        else:
            repl = bytes.fromhex(q["replace"])
        got = bytes(img[off:off + len(want)])
        if got != want:
            raise SystemExit(
                f"{q['owner']}: patch site 0x{q['addr']:08x} holds {got.hex()}, "
                f"expected {want.hex()} - wrong address, non-stock image, or a collision"
            )
        img[off:off + len(repl)] = repl
        patches_applied.append({"mod": q["owner"], "addr": q["addr"],
                                "expect": want.hex(), "replace": repl.hex()})

    if len(img) != original_len:
        raise SystemExit(f"image size changed: {original_len} -> {len(img)}")
    if not embedded_bootstrap_ok(bytes(img), meta):
        raise SystemExit(f"a mod wrote into the embedded bootstrap image "
                         f"0x{meta['embedded_bootstrap_start']:08x}.."
                         f"0x{meta['embedded_bootstrap_end']:08x} - refusing to build")

    tag = args.tag or ("_".join(m.split("-", 1)[0] for m in sorted(enabled)) or "stock")
    if overrides and not args.tag:
        # keep ablation outputs from colliding with the default build's filenames
        tag += "_" + "_".join(f"{k}{v}" for m in sorted(overrides)
                              for k, v in sorted(overrides[m].items()))
    mainos_out = BUILD / f"mainos_{tag}.bin"
    syx_out = BUILD / f"{meta.get('out_prefix', 'A4')}_{meta['target']}_{tag}.syx"
    mainos_out.write_bytes(img)
    run([EFT, "-i", STOCK_SYX, "-c", str(MAINOS_SECTION), mainos_out, "-o", syx_out])

    manifest = {
        "target": meta["target"],
        "stock_mainos_sha256": meta["mainos_sha256"],
        "patched_mainos_sha256": sha256(bytes(img)),
        "patched_mainos_size": len(img),
        "syx": syx_out.name,
        "syx_sha256": sha256(syx_out.read_bytes()),
        "mods": [
            {**a, "status": mods[a["mod"]]["status"], "title": mods[a["mod"]]["title"]}
            for a in applied
        ],
        "detours": detours_applied,
        "patches": patches_applied,
        "params": {m: mods[m]["_params"] for m in sorted(enabled) if mods[m]["_params"]},
    }
    (BUILD / f"manifest_{tag}.json").write_text(json.dumps(manifest, indent=2) + "\n")

    print(f"built {syx_out.relative_to(ROOT)} ({syx_out.stat().st_size:,} B)")
    print(f"  MIDI upgrade (Transfer, or the STARTUP menu's OS UPGRADE) -> {syx_out.name}")
    for a in applied:
        print(f"  {a['mod']}: stub 0x{a['stub_addr']:08x} ({a['stub_size']} B) "
              f"[{mods[a['mod']]['status']}]")
        prm = mods[a["mod"]]["_params"]
        if prm:
            marks = " ".join(f"{k}={v}" + ("*" if k in overrides.get(a["mod"], {}) else "")
                             for k, v in sorted(prm.items()))
            print(f"      params {marks}")
        for d in detours_applied:
            if d["mod"] == a["mod"]:
                print(f"      detour 0x{d['addr']:08x} -> {d['entry']} @ 0x{d['target']:08x}")
    for q in patches_applied:
        print(f"  {q['mod']}: patch 0x{q['addr']:08x} {q['expect']} -> {q['replace']}")
    print(f"  MAIN OS {len(img)} B, sha256 {manifest['patched_mainos_sha256'][:16]}...")


if __name__ == "__main__":
    main()
