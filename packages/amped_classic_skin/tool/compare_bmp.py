import sys
from PIL import Image
import struct

def compare(path, rgba_path):
    im = Image.open(path).convert('RGBA')
    w, h = im.size
    ref = im.tobytes()
    with open(rgba_path, 'rb') as f:
        mine = f.read()
    if len(ref) != len(mine):
        print(f'{path}: SIZE MISMATCH ref={len(ref)} mine={len(mine)}')
        return False
    diffs = 0
    first = None
    for i in range(0, len(ref), 1):
        if ref[i] != mine[i]:
            diffs += 1
            if first is None:
                first = i
    n = len(ref)
    if diffs == 0:
        print(f'{path}: OK ({w}x{h})')
        return True
    # check if vertically flipped version matches
    flipped = bytearray(mine)
    for row in range(h):
        src = row * w * 4
        dst = (h - 1 - row) * w * 4
        flipped[dst:dst + w * 4] = mine[src:src + w * 4]
    fdiffs = sum(1 for i in range(n) if flipped[i] != ref[i])
    print(f'{path}: {diffs} byte diffs (flip variant: {fdiffs}), first at {first}')
    return False

if __name__ == '__main__':
    for arg in sys.argv[1:]:
        name = arg.rsplit('/', 1)[-1]
        compare(arg, 'tool/preview/' + name + '.rgba')
