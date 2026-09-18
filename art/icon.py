"""The application icon, generated from the same palette and sprites as the game.

The placeholder was a cold blue-black (#123a4a) with no sand and no outline - the one
picture of Tidepool a player sees before the game even opens, and the only one off
palette. This composes it from art that already exists instead of drawing a new picture:
a wet channel, and a rescued starfish sitting in it. That is the whole game in one tile -
route the water, reach the critter - and because it is built from the real sprites, a
palette change repaints the icon with everything else.

Written as SVG so the OS can scale it, but as one crisp rect per pixel run rather than
smooth shapes: an icon that anti-aliases would be the only soft edge in a pixel-art game.
"""

import os

import critters
import tiles
from png import Canvas


def compose(pal: dict) -> Canvas:
    img = tiles.render(tiles.mask_from_name("ES"), True, pal)
    img.over(critters.render(critters.SHAPES["starfish"](True), pal))
    return img


def to_svg(img: Canvas, size: int = 128) -> str:
    """One <rect> per horizontal run of a single colour. Merging runs keeps the file small
    without giving up a single pixel of accuracy."""
    rects = []
    for y in range(img.height):
        x = 0
        while x < img.width:
            px = img[x, y]
            run = 1
            while x + run < img.width and img[x + run, y] == px:
                run += 1
            if px[3]:
                rects.append('<rect x="%d" y="%d" width="%d" height="1" fill="#%02x%02x%02x"/>'
                             % (x, y, run, px[0], px[1], px[2]))
            x += run
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" '
            'shape-rendering="crispEdges">%s</svg>\n'
            % (size, size, img.width, img.height, "".join(rects)))


def write(pal: dict, root: str) -> str:
    img = compose(pal)
    path = os.path.join(root, "icon.svg")
    with open(path, "w") as fh:
        fh.write(to_svg(img))
    return path
