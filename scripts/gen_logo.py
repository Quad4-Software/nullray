#!/usr/bin/env python3
"""Generate a transparent pixel-art Nullray wordmark.

Letter placement uses ink bounding boxes so gaps are measured between
visible pixels. The ll pair gets tighter kerning. Previews stay in
.logo-preview/ and are not committed until approved.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".logo-preview"

CLEAR = (0, 0, 0, 0)

LETTER_COLORS = {
    "N": (90, 210, 255, 255),
    "u": (70, 160, 230, 255),
    "l": (130, 120, 255, 255),
    "L": (160, 90, 220, 255),
    "r": (255, 140, 70, 255),
    "a": (255, 190, 80, 255),
    "y": (255, 230, 140, 255),
}

GLYPHS: dict[str, tuple[str, ...]] = {
    "N": (
        "10001",
        "11001",
        "10101",
        "10011",
        "10001",
        "10001",
        "10001",
    ),
    "u": (
        "00000",
        "00000",
        "10001",
        "10001",
        "10001",
        "10011",
        "01101",
    ),
    "l": (
        "11000",
        "01000",
        "01000",
        "01000",
        "01000",
        "01000",
        "11100",
    ),
    "r": (
        "00000",
        "00000",
        "10110",
        "11001",
        "10000",
        "10000",
        "10000",
    ),
    "a": (
        "00000",
        "00000",
        "01110",
        "00001",
        "01111",
        "10001",
        "01111",
    ),
    "y": (
        "00000",
        "00000",
        "10001",
        "10001",
        "01111",
        "00001",
        "01110",
    ),
}

# Base gap between ink edges (pixels). ll uses a tighter pair value.
BASE_GAP = 1
PAIR_GAP = {
    ("l", "l"): 0,
}


def write_png(path: Path, rgba: list[list[tuple[int, int, int, int]]]) -> None:
    h = len(rgba)
    w = len(rgba[0])
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        for x in range(w):
            rows.extend(rgba[y][x])
    compressed = zlib.compress(bytes(rows), 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def upscale(
    px: list[list[tuple[int, int, int, int]]], scale: int
) -> list[list[tuple[int, int, int, int]]]:
    h, w = len(px), len(px[0])
    big = [[CLEAR for _ in range(w * scale)] for _ in range(h * scale)]
    for y in range(h):
        for x in range(w):
            c = px[y][x]
            if c[3] == 0:
                continue
            for dy in range(scale):
                for dx in range(scale):
                    big[y * scale + dy][x * scale + dx] = c
    return big


def glyph_key(ch: str) -> str:
    if ch.upper() == "N" and ch.isupper():
        return "N"
    return ch.lower()


def ink_bounds(glyph: tuple[str, ...]) -> tuple[int, int]:
    left, right = len(glyph[0]), -1
    for row in glyph:
        for i, bit in enumerate(row):
            if bit == "1":
                left = min(left, i)
                right = max(right, i)
    if right < 0:
        return 0, 0
    return left, right


def color_for(text: str, index: int, ch: str) -> tuple[int, int, int, int]:
    if ch == "l":
        first = text.lower().find("l")
        return LETTER_COLORS["l" if index == first else "L"]
    if ch == "N":
        return LETTER_COLORS["N"]
    return LETTER_COLORS.get(ch.lower(), (200, 200, 200, 255))


def pair_gap(prev: str, cur: str) -> int:
    key = (prev.lower(), cur.lower())
    if key in PAIR_GAP:
        return PAIR_GAP[key]
    return BASE_GAP


def render_word(text: str = "Nullray", pad: int = 2) -> list[list[tuple[int, int, int, int]]]:
    """Place letters so spacing is measured between ink edges, not cell boxes."""
    letters = list(text)
    glyph_h = 7
    # First pass: compute x offsets from cumulative ink advance
    offsets: list[int] = []
    cursor = float(pad)
    prev_ch = ""
    prev_right = 0
    for i, ch in enumerate(letters):
        g = GLYPHS[glyph_key(ch)]
        left, right = ink_bounds(g)
        if i == 0:
            x = cursor - left
        else:
            gap = pair_gap(prev_ch, ch)
            # Next left ink sits gap pixels after previous right ink
            x = (prev_right + 1 + gap) - left
        offsets.append(int(math.floor(x + 0.5)))
        prev_ch = ch
        prev_right = offsets[-1] + right
        cursor = prev_right + 1

    width = int(prev_right + 1 + pad)
    height = pad * 2 + glyph_h
    canvas = [[CLEAR for _ in range(width)] for _ in range(height)]

    for i, ch in enumerate(letters):
        g = GLYPHS[glyph_key(ch)]
        color = color_for(text, i, ch)
        x0 = offsets[i]
        for gy, row in enumerate(g):
            for gx, bit in enumerate(row):
                if bit != "1":
                    continue
                xx = x0 + gx
                yy = pad + gy
                if 0 <= xx < width and 0 <= yy < height:
                    canvas[yy][xx] = color
    return canvas


def to_svg(px: list[list[tuple[int, int, int, int]]], scale: int = 12) -> str:
    h, w = len(px), len(px[0])
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w * scale}" height="{h * scale}" '
        f'shape-rendering="crispEdges" viewBox="0 0 {w * scale} {h * scale}">',
    ]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[y][x]
            if a == 0:
                continue
            parts.append(
                f'<rect x="{x * scale}" y="{y * scale}" width="{scale}" height="{scale}" '
                f'fill="rgba({r},{g},{b},{a / 255:.3f})"/>'
            )
    parts.append("</svg>")
    return "\n".join(parts)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*"):
        old.unlink()

    mark = render_word("Nullray")
    write_png(OUT / "nullray-word-raw.png", mark)
    write_png(OUT / "nullray-512.png", upscale(mark, 24))
    write_png(OUT / "nullray-128.png", upscale(mark, 8))
    (OUT / "nullray.svg").write_text(to_svg(mark, 16), encoding="utf-8")

    # Opaque social card still useful for GitHub OG previews
    social_bg = (6, 8, 14, 255)
    raw_h, raw_w = len(mark), len(mark[0])
    social_w, social_h = max(96, raw_w + 24), max(32, raw_h + 16)
    social = [[social_bg for _ in range(social_w)] for _ in range(social_h)]
    ox = (social_w - raw_w) // 2
    oy = (social_h - raw_h) // 2
    for y in range(raw_h):
        for x in range(raw_w):
            if mark[y][x][3] != 0:
                social[oy + y][ox + x] = mark[y][x]
    # upscale social with opaque bg helper
    big = []
    scale = 10
    for y in range(social_h):
        for dy in range(scale):
            row = []
            for x in range(social_w):
                for dx in range(scale):
                    row.append(social[y][x])
            big.append(row)
    write_png(OUT / "nullray-social.png", big)

    print(f"wrote transparent previews in {OUT}")
    for p in sorted(OUT.iterdir()):
        print(f"  {p.name:24} {p.stat().st_size:7} bytes")


if __name__ == "__main__":
    main()
