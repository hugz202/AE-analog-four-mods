# Analog Four / Analog Keys MK1 firmware mods, OS 1.56. See BUILD.md.
# Build and verify use only the Python standard library; python3 >= 3.11.
# On Windows run everything from WSL (Ubuntu 24.04 has python3.12, make, gcc and
# binutils-m68k-linux-gnu).
PY := python3

.PHONY: all setup symbols layout build verify full hard custom scale slide control disasm cavescan clean

all: verify

# The container tool, pinned to the commit this project was verified against, plus
# its one local patch: ELE2 containers padded to 4 bytes. The A4 1.56 container is a
# multiple of 4 either way; with the patched tool the untouched stock .syx rebuilds
# byte for byte, which `make control` asserts.
EFT_URL := https://github.com/mischa85/elektron-firmware-tool
EFT_REV := a5bce9a6af644386d900924082993a805e812874
EFT_DIR := vendor/elektron-firmware-tool

setup:
	test -d $(EFT_DIR)/.git || git clone $(EFT_URL) $(EFT_DIR)
	git -C $(EFT_DIR) checkout --quiet $(EFT_REV)
	git -C $(EFT_DIR) apply --check ../../tools/eft-ele2-align4.patch 2>/dev/null \
		&& git -C $(EFT_DIR) apply ../../tools/eft-ele2-align4.patch || true
	grep -q "stock pads to 4" $(EFT_DIR)/container.c
	$(MAKE) -C $(EFT_DIR)

symbols:
	$(PY) tools/symbols.py

layout:
	$(PY) tools/layout.py

# The mods marked `enabled = true` in their mod.toml (out of the box: the scale lock).
build: symbols layout
	$(PY) tools/build.py

verify: build
	$(PY) tools/verify.py

# Everything in this release -> build/A4_OS1.56_full.syx
FULL := 0001-scale-lock 0002-slide-303 0006-fx-slot 0007-digital-path 0008-pages 0010-wave-osc \
	0011-rand-track 0012-res-limit
full: symbols layout
	$(PY) tools/build.py --mods $(FULL) --tag full
	$(PY) tools/verify.py --tag full

# The same with one drive character: HARD only, no CHR knob on the DIST page, a
# lighter digital path -> build/A4_OS1.56_hard.syx
hard: symbols layout
	$(PY) tools/build.py --mods $(FULL) --param 0007-digital-path:chr=0 --tag hard
	$(PY) tools/verify.py --tag hard

# Your own selection -> build/A4_OS1.56_$(TAG).syx, e.g.
#   make custom MODS="0001-scale-lock 0006-fx-slot 0007-digital-path 0008-pages" TAG=dist
# PARAMS sets mod options, e.g. PARAMS="0002-slide-303:always_on=1" (see BUILD.md).
# The build refuses a selection whose dependencies are missing.
MODS ?=
TAG ?= custom
PARAMS ?=
custom: symbols layout
	@test -n "$(MODS)" || { echo 'set MODS="..." (see BUILD.md)'; exit 1; }
	$(PY) tools/build.py --mods $(MODS) $(foreach p,$(PARAMS),--param $(p)) --tag $(TAG)
	$(PY) tools/verify.py --tag $(TAG)

# The scale lock alone -> build/A4_OS1.56_scale.syx
scale: symbols layout
	$(PY) tools/build.py --mods 0001-scale-lock --tag scale
	$(PY) tools/verify.py --tag scale

# The 303 slide alone, on for every synth track -> build/A4_OS1.56_slide.syx
slide: symbols layout
	$(PY) tools/build.py --mods 0002-slide-303 --param 0002-slide-303:always_on=1 --tag slide
	$(PY) tools/verify.py --tag slide

# The pipeline test: no mods at all, stock MAIN OS recompressed by our tool; checks
# that it rebuilds the untouched stock file byte for byte.
control: symbols layout
	$(PY) tools/build.py --mods --tag control
	$(PY) tools/verify.py --tag control

# For mod development: whole-image disassembly -> build/mainos.dis, and the scan for
# free code space.
disasm: build
	sh tools/disasm.sh

cavescan: build
	$(PY) tools/cavescan.py

clean:
	rm -rf build
