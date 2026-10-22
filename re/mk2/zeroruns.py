"""zeroruns.py MAINOS.bin CEILING MIN: runs of one filler byte (00/ff) below CEILING
(__bss_start), with how many 32-bit words in the image point into or at each."""
import struct, sys, bisect
img = open(sys.argv[1], 'rb').read(); base = 0x40000400; ceil = int(sys.argv[2], 16); mn = int(sys.argv[3])
words = sorted(struct.unpack_from('>I', img, i)[0] for i in range(0, len(img) - 3, 2))
i, up = 0, ceil - base
while i < up:
    j = i
    while j < up and img[j] == img[i]: j += 1
    if j - i >= mn and img[i] in (0, 0xff):
        lo, hi = base + i, base + j
        k = bisect.bisect_left(words, lo); n = bisect.bisect_right(words, hi) - k
        print(f'{lo:#010x}..{hi:#010x} {j-i:6d} B fill {img[i]:02x} ptrs-into {n}  before={img[i-8:i].hex()} after={img[j:j+8].hex()}')
    i = j if j > i else i + 1
