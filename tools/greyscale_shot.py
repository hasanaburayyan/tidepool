#!/usr/bin/env python3
"""Desaturate an in-engine screenshot, so rule 1 can be checked on what the game draws.

    python3 tools/greyscale_shot.py screenshots/level08.png

Writes <name>_greyscale.png beside it. Rule 1 - nothing is communicated by hue alone -
has always been asserted against the sprites I generate. That is the easy half. The claim
that actually matters is about a whole board: a player who cannot separate our teal from
our sand must still be able to solve the level. Only a screenshot can answer that, and
until now nothing could read one.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art"))

import png


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    src = sys.argv[1]
    img = png.load(src)
    out = png.Canvas(img.width, img.height)
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = img[x, y]
            v = round(0.2126 * r + 0.7152 * g + 0.0722 * b)  # Rec. 709 luma
            out[x, y] = (v, v, v, a)
    dst = sys.argv[2] if len(sys.argv) > 2 else src[:-4] + "_greyscale.png"
    out.save(dst)
    print("%s -> %s (%dx%d)" % (src, dst, img.width, img.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
