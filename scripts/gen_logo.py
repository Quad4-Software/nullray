#!/usr/bin/env python3
"""Generate a pixel-art Nullray wordmark.

Each letter uses its own color band (void cyan through photon ember).
Writes previews under .logo-preview/ only. Does not touch git.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".logo-preview"

BG = (6, 8, 14, 255)

# Per-letter colors: N u l l r a y
LETTER_COLORS = {
    "N": (90, 210, 255, 255),   # photon cyan
    "u": (70, 160, 230, 255),
    "l": (130, 120, 255, 255),  # violet rim
    "L": (160, 90, 220, 255),   # second l slightly shifted
    "r": (255, 140, 70, 255),   # accretion ember
    "a": (255, 190, 80, 255),
    "y": (255, 230, 140, 255),
}

# 5x7 glyphs, rows top-to-bottom, 1 = on
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
    big = [[BG for _ in range(w * scale)] for _ in range(h * scale)]
    for y in range(h):
        for x in range(w):
            c = px[y][x]
            for dy in range(scale):
                for dx in range(scale):
                    big[y * scale + dy][x * scale + dx] = c
    return big


def render_word(text: str = "Nullray", pad: int = 2, gap: int = 1) -> list[list[tuple[int, int, int, int]]]:
    letters = list(text)
    glyph_w, glyph_h = 5, 7
    width = pad * 2 + len(letters) * glyph_w + gap * (len(letters) - 1)
    height = pad * 2 + glyph_h
    canvas = [[BG for _ in range(width)] for _ in range(height)]

    x0 = pad
    for i, ch in enumerate(letters):
        key = ch
        color_key = ch if ch in LETTER_COLORS else ch.lower()
        # Distinguish the two L's
        if ch == "l":
            color_key = "l" if i == text.lower().find("l") else "L"
        color = LETTER_COLORS.get(color_key, LETTER_COLORS.get(ch.lower(), (200, 200, 200, 255)))
        gkey = ch.upper() if ch.upper() in GLYPHS and ch.isupper() else ch
        if gkey not in GLYPHS:
            gkey = ch.lower()
        glyph = GLYPHS[gkey]
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    canvas[pad + gy][x0 + gx] = color
        x0 += glyph_w + gap
    return canvas


def to_svg(px: list[list[tuple[int, int, int, int]]], scale: int = 12) -> str:
    h, w = len(px), len(px[0])
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w * scale}" height="{h * scale}" '
        f'shape-rendering="crispEdges" viewBox="0 0 {w * scale} {h * scale}">',
        f'<rect width="100%" height="100%" fill="rgb{BG[:3]}"/>',
    ]
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[y][x]
            if (r, g, b, a) == BG:
                continue
            parts.append(
                f'<rect x="{x * scale}" y="{y * scale}" width="{scale}" height="{scale}" '
                f'fill="rgba({r},{g},{b},{a / 255:.3f})"/>'
            )
    parts.append("</svg>")
    return "\n".join(parts)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    mark = render_word("Nullray")
    write_png(OUT / "nullray-word-raw.png", mark)
    write_png(OUT / "nullray-512.png", upscale(mark, 24))
    write_png(OUT / "nullray-128.png", upscale(mark, 8))
    (OUT / "nullray.svg").write_text(to_svg(mark, 16), encoding="utf-8")

    # Social: wordmark centered on wider canvas
    raw_h, raw_w = len(mark), len(mark[0])
    social_w, social_h = max(96, raw_w + 24), max(32, raw_h + 16)
    social = [[BG for _ in range(social_w)] for _ in range(social_h)]
    ox = (social_w - raw_w) // 2
    oy = (social_h - raw_h) // 2
    for y in range(raw_h):
        for x in range(raw_w):
            social[oy + y][ox + x] = mark[y][x]
    write_png(OUT / "nullray-social.png", upscale(social, 10))

    print(f"wrote previews in {OUT}")
    for p in sorted(OUT.iterdir()):
        print(f"  {p.name:24} {p.stat().st_size:7} bytes")


if __name__ == "__main__":
    main()
