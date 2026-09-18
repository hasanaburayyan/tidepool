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
