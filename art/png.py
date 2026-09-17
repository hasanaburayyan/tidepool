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
        self._px = [list(fill) for _ in range(width * height)]

    def __setitem__(self, xy, rgb):
        x, y = xy
        if 0 <= x < self.width and 0 <= y < self.height:
            self._px[y * self.width + x] = list(rgb)

    def __getitem__(self, xy):
        x, y = xy
        return tuple(self._px[y * self.width + x])

    def blit(self, other: "Canvas", ox: int, oy: int) -> None:
        for y in range(other.height):
            for x in range(other.width):
                self[ox + x, oy + y] = other[x, y]

    def save(self, path: str) -> None:
        raw = bytearray()
        for y in range(self.height):
            raw.append(0)  # filter type 0 (None): pixel art does not compress better with filters
            for x in range(self.width):
                raw.extend(self._px[y * self.width + x])
        with open(path, "wb") as fh:
            fh.write(b"\x89PNG\r\n\x1a\n")
            fh.write(_chunk(b"IHDR", struct.pack(">IIBBBBB", self.width, self.height, 8, 2, 0, 0, 0)))
            fh.write(_chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
            fh.write(_chunk(b"IEND", b""))


def _chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def hex_to_rgb(text: str):
    text = text.lstrip("#")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))
