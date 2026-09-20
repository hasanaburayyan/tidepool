"""The title lettering: "Tidepool", drawn as pixels instead of borrowed from a font.

`title_screen.gd` said it in a comment - the name was set in Godot's fallback font "exactly
as board.gd drew placeholder tiles before Cove's art landed". A system font on the title
screen is the one thing in the game that is not in the game's style: it anti-aliases, it
changes shape between platforms, and it is the very first thing a player sees.

So the title gets its own font, for the seven letters it needs, the same way the map got
its own digits. One idea carries it, and it comes from the tiles the player meets a screen
later: the tide is IN the name. Above the waterline a letter is Deep Umber, the same ink as
the pool numbers; at and below it the letter is Tidewater. The word is a tidepool -
half-submerged, with the water at the same height in every letter, exactly as water in this
game always sits level.

Every stroke here is one pixel wide, so there is no Umber rim round the wet part the way
the critters have one: an outline would eat the stroke it outlined and the word would come
out solid ink. It does not need one. `assert_wordmark_reads` in build.py puts both
materials against the sand they sit on and both clear it by more than the 60 luma the
critters are held to, so the lettering survives greyscale without a rim.
"""

from png import Canvas

## 5x9 letterforms, one bit per pixel. Row 0 is the ascender top, row 6 the baseline, rows
## 7-8 the descender that only `p` uses. x-height letters start at row 2.
##
## Only the letters in "Tidepool" exist. A font is not the deliverable - the word is - and
## seven hand-set glyphs read better at this size than twenty-six compromises.
GLYPHS = {
    "T": ["11111",
          "00100",
          "00100",
          "00100",
          "00100",
          "00100",
          "00100",
          "00000",
          "00000"],
    "i": ["010",
          "000",
          "010",
          "010",
          "010",
          "010",
          "010",
          "000",
          "000"],
    "d": ["00001",
          "00001",
          "01111",
          "10001",
          "10001",
          "10001",
          "01111",
          "00000",
          "00000"],
    "e": ["00000",
          "00000",
          "01110",
          "10001",
          "11111",
          "10000",
          "01110",
          "00000",
          "00000"],
    "p": ["00000",
          "00000",
          "11110",
          "10001",
          "10001",
          "10001",
          "11110",
          "10000",
          "10000"],
    "o": ["00000",
          "00000",
          "01110",
          "10001",
          "10001",
          "10001",
          "01110",
          "00000",
          "00000"],
    "l": ["010",
          "010",
          "010",
          "010",
          "010",
          "010",
          "011",
          "000",
          "000"],
}

WORD = "Tidepool"
HEIGHT = 9
## One empty column between letters. Checked by the build: at this size two letters that
## touch read as one shape.
TRACKING = 1

## The tide line, in rows. Rows at or below this are under water. Row 4 puts it across the
## waist of the x-height letters - through the crossbar of `e` and the bowls of `o` - so
## every letter has both materials in it. Higher and the ascenders float; lower and only
## the feet get wet and the idea reads as a shadow instead of water.
WATERLINE = 4


def body_cells() -> dict:
    """The word as {(x, y): letter index}. The single source of the layout: the sprite, the
    width and the build's separation check all read this, so none of them can disagree."""
    cells = {}
    x = 0
    for i, ch in enumerate(WORD):
        rows = GLYPHS[ch]
        for y, bits in enumerate(rows):
            for dx, bit in enumerate(bits):
                if bit == "1":
                    cells[(x + dx, y)] = i
        x += len(rows[0]) + TRACKING
    return cells


def width() -> int:
    return max(x for x, _ in body_cells()) + 1


def render(pal: dict) -> Canvas:
    """Transparent canvas, letters only. Drawn at 1x like every other sprite in the game;
    `title_screen.gd` scales it by an integer, which is what keeps the edges hard."""
    img = Canvas(width(), HEIGHT, (0, 0, 0, 0))
    body = set(body_cells())

    for (x, y) in body:
        img[x, y] = pal["channel_wet"] if y >= WATERLINE else pal["outline"]

    return img


def write(pal: dict, root: str) -> str:
    import os
    out = os.path.join(root, "assets", "ui")
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, "title_wordmark.png")
    render(pal).save(path)
    return path
