"""Minimal PNG writer. Standard library only - Pillow is not installed on the build box
and a 60-line encoder is a smaller dependency than a package install.

Writes 8-bit truecolour (colour type 2), no interlace, one IDAT. That is all pixel art
needs, and it keeps the files byte-identical between runs so a regenerate shows an empty
diff when nothing changed.
"""

import struct
import zlib


class Canvas:
    """A fixed-size RGB pixel buffer addressed as canvas[x, y] = (r, g, b)."""

    def __init__(self, width: int, height: int, fill=(0, 0, 0)):
        self.width = width
        self.height = height
        self._px = [_rgba(fill) for _ in range(width * height)]

    def __setitem__(self, xy, rgb):
        x, y = xy
        if 0 <= x < self.width and 0 <= y < self.height:
            self._px[y * self.width + x] = _rgba(rgb)

    def __getitem__(self, xy):
        x, y = xy
        return tuple(self._px[y * self.width + x])

    def blit(self, other: "Canvas", ox: int, oy: int) -> None:
        """Copy, alpha and all. Use this to lay a tile into a contact sheet."""
        for y in range(other.height):
            for x in range(other.width):
                self[ox + x, oy + y] = other[x, y]

    def over(self, other: "Canvas", ox: int = 0, oy: int = 0) -> None:
        """Composite, skipping transparent pixels. Use this to drop an overlay on a tile.

        Alpha here is 1-bit on purpose: a pixel is either part of the sprite or it is not.
        Partial alpha would put in-between colours on the edge of a 32px sprite, which is
        the same softening that nearest-neighbour filtering exists to prevent.
        """
        for y in range(other.height):
            for x in range(other.width):
                px = other[x, y]
                if px[3]:
                    self[ox + x, oy + y] = px

    def save(self, path: str) -> None:
        # Truecolour when nothing is transparent, truecolour+alpha when something is. A
        # tile that gained no alpha writes the same bytes it always did, so adding overlay
        # support to the pipeline did not churn a single already-shipped sprite.
        has_alpha = any(px[3] != 255 for px in self._px)
        stride = 4 if has_alpha else 3
        raw = bytearray()
        for y in range(self.height):
            raw.append(0)  # filter type 0 (None): pixel art does not compress better with filters
            for x in range(self.width):
                raw.extend(self._px[y * self.width + x][:stride])
        with open(path, "wb") as fh:
            fh.write(b"\x89PNG\r\n\x1a\n")
            colour_type = 6 if has_alpha else 2
            fh.write(_chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, colour_type, 0, 0, 0)))
            fh.write(_chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
            fh.write(_chunk(b"IEND", b""))


TRANSPARENT = (0, 0, 0, 0)


def _rgba(colour) -> list:
    return list(colour) if len(colour) == 4 else [colour[0], colour[1], colour[2], 255]


def _chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def hex_to_rgb(text: str):
    text = text.lstrip("#")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


## ---------------------------------------------------------------------------
## Reading
##
## The encoder existed so I could generate art. This exists so rule 1 can be checked on
## a *screenshot* rather than only on the sprites I made: "a greyscale board must stay
## solvable" is a claim about what the engine draws, and until now I could only test it
## against my own contact sheets. An in-engine screenshot is the real evidence.
## ---------------------------------------------------------------------------


def load(path: str) -> "Canvas":
    """Read an 8-bit truecolour PNG, with or without alpha. Standard library only."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % path)

    pos, idat, width, height, colour_type = 8, bytearray(), 0, 0, 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, colour_type = struct.unpack(">IIBB", body[:10])
            if depth != 8 or colour_type not in (2, 6):
                raise ValueError("only 8-bit truecolour PNGs, got depth %d type %d" % (depth, colour_type))
        elif tag == b"IDAT":
            idat += body            # a large PNG is split across several IDATs; concatenate first
        elif tag == b"IEND":
            break
        pos += 12 + length          # length + tag + body + crc

    stride = 4 if colour_type == 6 else 3
    raw = zlib.decompress(bytes(idat))
    img = Canvas(width, height)
    prev = bytearray(width * stride)
    at = 0
    for y in range(height):
        filt = raw[at]
        line = bytearray(raw[at + 1:at + 1 + width * stride])
        at += 1 + width * stride
        # Undo the per-scanline filter. Godot picks these per row, so all five must work;
        # my own encoder only ever writes 0, which is why this is the half that needed care.
        for i in range(len(line)):
            a = line[i - stride] if i >= stride else 0
            b = prev[i]
            c = prev[i - stride] if i >= stride else 0
            if filt == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filt == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
            elif filt != 0:
                raise ValueError("unknown PNG filter %d on row %d" % (filt, y))
        for x in range(width):
            px = line[x * stride:(x + 1) * stride]
            img[x, y] = tuple(px) if stride == 4 else (px[0], px[1], px[2], 255)
        prev = line
    return img
