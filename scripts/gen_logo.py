#!/usr/bin/env python3
"""Generate nullray branding assets under logo/.

Wordmark uses ink-box kerning. Slogan sits centered below in a tighter
pixel face. Also writes OG/social cards, ASCII frames, and a splash GIF.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "logo"
CLEAR = (0, 0, 0, 0)
VOID = (6, 8, 14, 255)
SLOGAN = "Simple, Lightweight, Fast"
SLOGAN_COLOR = (180, 200, 220, 255)

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

# 3x5 caps + punctuation for slogan
TINY: dict[str, tuple[str, ...]] = {
    "A": ("010", "101", "111", "101", "101"),
    "C": ("011", "100", "100", "100", "011"),
    "E": ("111", "100", "110", "100", "111"),
    "F": ("111", "100", "110", "100", "100"),
    "G": ("011", "100", "101", "101", "011"),
    "H": ("101", "101", "111", "101", "101"),
    "I": ("111", "010", "010", "010", "111"),
    "L": ("100", "100", "100", "100", "111"),
    "M": ("101", "111", "111", "101", "101"),
    "P": ("110", "101", "110", "100", "100"),
    "S": ("011", "100", "010", "001", "110"),
    "T": ("111", "010", "010", "010", "010"),
    "W": ("10001", "10101", "10101", "01010", "01010"),
    "Y": ("101", "101", "010", "010", "010"),
    ",": ("000", "000", "000", "010", "100"),
    " ": ("000", "000", "000", "000", "000"),
}

BASE_GAP = 1
PAIR_GAP = {("l", "l"): 0}
TINY_GAP = 1


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
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )


def upscale(
    px: list[list[tuple[int, int, int, int]]], scale: int, fill=CLEAR
) -> list[list[tuple[int, int, int, int]]]:
    h, w = len(px), len(px[0])
    big = [[fill for _ in range(w * scale)] for _ in range(h * scale)]
    for y in range(h):
        for x in range(w):
            c = px[y][x]
            if c[3] == 0 and fill[3] == 0:
                continue
            for dy in range(scale):
                for dx in range(scale):
                    big[y * scale + dy][x * scale + dx] = c if c[3] else fill
    return big


def glyph_key(ch: str) -> str:
    if ch == "N":
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
        return 0, max(0, len(glyph[0]) - 1)
    return left, right


def color_for(text: str, index: int, ch: str) -> tuple[int, int, int, int]:
    if ch == "l":
        first = text.lower().find("l")
        return LETTER_COLORS["l" if index == first else "L"]
    if ch == "N":
        return LETTER_COLORS["N"]
    return LETTER_COLORS.get(ch.lower(), (200, 200, 200, 255))


def pair_gap(prev: str, cur: str) -> int:
    return PAIR_GAP.get((prev.lower(), cur.lower()), BASE_GAP)


def blit(
    canvas: list[list[tuple[int, int, int, int]]],
    glyph: tuple[str, ...],
    x0: int,
    y0: int,
    color: tuple[int, int, int, int],
) -> None:
    h = len(canvas)
    w = len(canvas[0])
    for gy, row in enumerate(glyph):
        for gx, bit in enumerate(row):
            if bit != "1":
                continue
            xx, yy = x0 + gx, y0 + gy
            if 0 <= xx < w and 0 <= yy < h:
                canvas[yy][xx] = color


def render_word(text: str = "Nullray", pad: int = 2) -> list[list[tuple[int, int, int, int]]]:
    letters = list(text)
    glyph_h = 7
    offsets: list[int] = []
    prev_ch = ""
    prev_right = 0
    for i, ch in enumerate(letters):
        g = GLYPHS[glyph_key(ch)]
        left, right = ink_bounds(g)
        if i == 0:
            x = float(pad) - left
        else:
            x = (prev_right + 1 + pair_gap(prev_ch, ch)) - left
        offsets.append(int(math.floor(x + 0.5)))
        prev_ch = ch
        prev_right = offsets[-1] + right

    width = int(prev_right + 1 + pad)
    height = pad * 2 + glyph_h
    canvas = [[CLEAR for _ in range(width)] for _ in range(height)]
    for i, ch in enumerate(letters):
        blit(canvas, GLYPHS[glyph_key(ch)], offsets[i], pad, color_for(text, i, ch))
    return canvas


def render_slogan(text: str = SLOGAN, pad: int = 1) -> list[list[tuple[int, int, int, int]]]:
    letters = list(text.upper())
    glyph_h = 5
    offsets: list[int] = []
    prev_right = pad - 1
    for i, ch in enumerate(letters):
        g = TINY.get(ch, TINY[" "])
        left, right = ink_bounds(g)
        if ch == " ":
            x = prev_right + 1 + 2
            offsets.append(x)
            prev_right = x + 2
            continue
        x = prev_right + 1 + TINY_GAP - left
        offsets.append(int(x))
        prev_right = offsets[-1] + right

    width = int(prev_right + 1 + pad)
    height = pad * 2 + glyph_h
    canvas = [[CLEAR for _ in range(width)] for _ in range(height)]
    for i, ch in enumerate(letters):
        if ch == " ":
            continue
        blit(canvas, TINY.get(ch, TINY[" "]), offsets[i], pad, SLOGAN_COLOR)
    return canvas


def stack_centered(
    top: list[list[tuple[int, int, int, int]]],
    bottom: list[list[tuple[int, int, int, int]]],
    gap: int = 3,
    pad_x: int = 2,
    pad_y: int = 2,
) -> list[list[tuple[int, int, int, int]]]:
    tw, th = len(top[0]), len(top)
    bw, bh = len(bottom[0]), len(bottom)
    width = max(tw, bw) + pad_x * 2
    height = th + gap + bh + pad_y * 2
    canvas = [[CLEAR for _ in range(width)] for _ in range(height)]

    def place(src, ox, oy):
        for y, row in enumerate(src):
            for x, c in enumerate(row):
                if c[3]:
                    canvas[oy + y][ox + x] = c

    place(top, (width - tw) // 2, pad_y)
    place(bottom, (width - bw) // 2, pad_y + th + gap)
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


def rgba_to_pil(px: list[list[tuple[int, int, int, int]]]):
    assert Image is not None
    h, w = len(px), len(px[0])
    img = Image.new("RGBA", (w, h))
    img.putdata([c for row in px for c in row])
    return img


def place_on_canvas(
    mark: list[list[tuple[int, int, int, int]]],
    width: int,
    height: int,
    bg=VOID,
) -> list[list[tuple[int, int, int, int]]]:
    canvas = [[bg for _ in range(width)] for _ in range(height)]
    mh, mw = len(mark), len(mark[0])
    ox = (width - mw) // 2
    oy = (height - mh) // 2
    for y in range(mh):
        for x in range(mw):
            if mark[y][x][3]:
                canvas[oy + y][ox + x] = mark[y][x]
    return canvas


def ascii_frame(mark: list[list[tuple[int, int, int, int]]], letters: int | None = None) -> str:
    # Approximate letter columns from wordmark geometry for progressive reveal
    word = render_word("Nullray")
    # Use full mark if letters is None
    rows = []
    for y, row in enumerate(mark):
        line = []
        for x, c in enumerate(row):
            line.append("#" if c[3] else " ")
        rows.append("".join(line).rstrip())
    # Trim empty edges
    while rows and not rows[0].strip():
        rows.pop(0)
    while rows and not rows[-1].strip():
        rows.pop()
    return "\n".join(rows) + "\n"


def progressive_marks(full: list[list[tuple[int, int, int, int]]]) -> list[list[list[tuple[int, int, int, int]]]]:
    """Build reveal frames by enabling letters left to right on the stacked mark."""
    frames = []
    # Rebuild stacked mark letter by letter for cleaner animation
    for n in range(1, 8):
        word = render_word("Nullray"[:n] if n <= 7 else "Nullray")
        # For partial "Nullray", slice text properly
        text = "Nullray"[:n]
        word = render_word(text)
        if n >= 7:
            stacked = stack_centered(word, render_slogan(), gap=3)
        else:
            # Keep canvas height stable: pad with empty slogan space
            slogan = render_slogan()
            empty = [[CLEAR for _ in range(len(slogan[0]))] for _ in range(len(slogan))]
            stacked = stack_centered(word, empty, gap=3)
        frames.append(stacked)
    # Final hold with slogan
    frames.append(full)
    frames.append(full)
    return frames


def write_ascii_and_gif(full: list[list[tuple[int, int, int, int]]]) -> None:
    frames_px = progressive_marks(full)
    ascii_blocks = []
    for i, fr in enumerate(frames_px):
        block = ascii_frame(fr)
        ascii_blocks.append(f"; frame {i + 1}\n{block}")
    (OUT / "nullray-ascii.txt").write_text("\n".join(ascii_blocks), encoding="utf-8")
    (OUT / "nullray-ascii.txt").write_text(
        "\n".join(ascii_blocks) + "\n--- final ---\n" + ascii_frame(full),
        encoding="utf-8",
    )

    if Image is None:
        print("PIL missing: skipped GIF")
        return

    imgs = []
    for fr in frames_px:
        # opaque void background for GIF (no alpha in GIF palette easily)
        card = place_on_canvas(fr, max(len(fr[0]) + 8, 48), len(fr) + 8, VOID)
        scaled = upscale(card, 8, VOID)
        imgs.append(rgba_to_pil(scaled).convert("P", palette=Image.ADAPTIVE, colors=64))

    imgs[0].save(
        OUT / "nullray-splash.gif",
        save_all=True,
        append_images=imgs[1:],
        duration=[120] * (len(imgs) - 2) + [400, 800],
        loop=0,
        disposal=2,
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*"):
        if old.is_file():
            old.unlink()

    word = render_word("Nullray")
    slogan = render_slogan()
    stacked = stack_centered(word, slogan, gap=3)

    write_png(OUT / "nullray-word-raw.png", word)
    write_png(OUT / "nullray-mark.png", stacked)
    write_png(OUT / "nullray-128.png", upscale(stacked, 6))
    write_png(OUT / "nullray-512.png", upscale(stacked, 16))
    (OUT / "nullray.svg").write_text(to_svg(stacked, 12), encoding="utf-8")

    # Social ~ 1200x630-ish via upscale of a void card
    social_base_w, social_base_h = 120, 63
    social = place_on_canvas(stacked, social_base_w, social_base_h, VOID)
    write_png(OUT / "nullray-social.png", upscale(social, 10, VOID))

    # OG same aspect, slightly taller mark scale
    og = place_on_canvas(stacked, social_base_w, social_base_h, VOID)
    write_png(OUT / "nullray-og.png", upscale(og, 10, VOID))

    write_ascii_and_gif(stacked)

    # Drop preview dir if present
    preview = ROOT / ".logo-preview"
    if preview.exists():
        for p in preview.glob("*"):
            p.unlink()
        try:
            preview.rmdir()
        except OSError:
            pass

    print(f"wrote branding in {OUT}")
    for p in sorted(OUT.iterdir()):
        print(f"  {p.name:24} {p.stat().st_size:7} bytes")


if __name__ == "__main__":
    main()
