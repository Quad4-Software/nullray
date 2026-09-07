#!/usr/bin/env python3
"""Regenerate logo/nullray-splash.gif and logo/nullray-ascii.txt.

Fixed canvas from the full stacked mark. Letter reveal, then slogan steps,
then hold frames with drifting letter colors. Does not touch other logo assets.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "logo"

CLEAR = (0, 0, 0, 0)
VOID = (6, 8, 14, 255)
SLOGAN = "Simple, Lightweight, Fast"
SLOGAN_COLOR = (180, 200, 220, 255)
WORD = "Nullray"
SCALE = 8
PAD = 4
GAP = 3

# cyan -> blue -> violet -> orange -> gold
HUE_STOPS = (
    (90, 210, 255),
    (70, 160, 230),
    (130, 120, 255),
    (160, 90, 220),
    (255, 140, 70),
    (255, 190, 80),
    (255, 230, 140),
)

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


def pair_gap(prev: str, cur: str) -> int:
    return PAIR_GAP.get((prev.lower(), cur.lower()), BASE_GAP)


def lerp_rgb(
    a: tuple[int, int, int], b: tuple[int, int, int], t: float
) -> tuple[int, int, int]:
    return (
        int(round(a[0] + (b[0] - a[0]) * t)),
        int(round(a[1] + (b[1] - a[1]) * t)),
        int(round(a[2] + (b[2] - a[2]) * t)),
    )


def sample_hue(t: float) -> tuple[int, int, int]:
    stops = HUE_STOPS
    n = len(stops) - 1
    x = (t % 1.0) * n
    i = int(math.floor(x))
    f = x - i
    if i >= n:
        return stops[-1]
    return lerp_rgb(stops[i], stops[i + 1], f)


def scale_rgb(
    rgb: tuple[int, int, int], brightness: float
) -> tuple[int, int, int, int]:
    b = max(0.0, min(1.25, brightness))
    return (
        min(255, int(round(rgb[0] * b))),
        min(255, int(round(rgb[1] * b))),
        min(255, int(round(rgb[2] * b))),
        255,
    )


def letter_color(
    index: int, count: int, phase: float, brightness: float
) -> tuple[int, int, int, int]:
    span = max(1, count - 1)
    t = (index / span) * 0.85 + phase
    return scale_rgb(sample_hue(t), brightness)


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


def render_word(
    text: str = WORD,
    visible: int | None = None,
    phase: float = 0.0,
    brightness: float = 1.0,
    pad: int = 2,
) -> list[list[tuple[int, int, int, int]]]:
    # Layout always uses the full word so revealed letters keep final positions.
    letters = list(text)
    show = len(letters) if visible is None else max(0, min(visible, len(letters)))
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
    for i, ch in enumerate(letters[:show]):
        color = letter_color(i, len(letters), phase, brightness)
        blit(canvas, GLYPHS[glyph_key(ch)], offsets[i], pad, color)
    return canvas


def render_slogan(
    text: str = SLOGAN,
    brightness: float = 1.0,
    pad: int = 1,
) -> list[list[tuple[int, int, int, int]]]:
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
    color = scale_rgb(SLOGAN_COLOR[:3], brightness)
    for i, ch in enumerate(letters):
        if ch == " ":
            continue
        blit(canvas, TINY.get(ch, TINY[" "]), offsets[i], pad, color)
    return canvas


def empty_like(
    src: list[list[tuple[int, int, int, int]]],
) -> list[list[tuple[int, int, int, int]]]:
    return [[CLEAR for _ in range(len(src[0]))] for _ in range(len(src))]


def stack_centered(
    top: list[list[tuple[int, int, int, int]]],
    bottom: list[list[tuple[int, int, int, int]]],
    gap: int = GAP,
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


def upscale(
    px: list[list[tuple[int, int, int, int]]], scale: int
) -> list[list[tuple[int, int, int, int]]]:
    h, w = len(px), len(px[0])
    big = [[VOID for _ in range(w * scale)] for _ in range(h * scale)]
    for y in range(h):
        for x in range(w):
            c = px[y][x]
            for dy in range(scale):
                for dx in range(scale):
                    big[y * scale + dy][x * scale + dx] = c
    return big


def rgba_to_pil(px: list[list[tuple[int, int, int, int]]]) -> Image.Image:
    h, w = len(px), len(px[0])
    img = Image.new("RGBA", (w, h))
    img.putdata([c for row in px for c in row])
    return img


def ascii_frame(canvas: list[list[tuple[int, int, int, int]]]) -> str:
    rows = []
    for row in canvas:
        line = "".join("#" if c != VOID else " " for c in row)
        rows.append(line.rstrip())
    while rows and not rows[0].strip():
        rows.pop(0)
    while rows and not rows[-1].strip():
        rows.pop()
    # Drop trailing spaces only. Keep leading spaces so content stays centered.
    return "\n".join(rows) + "\n"


def pulse(phase: float) -> float:
    return 0.88 + 0.14 * (0.5 + 0.5 * math.sin(phase * math.tau))


def build_mark(
    letters: int,
    slogan: str | None,
    slogan_band: list[list[tuple[int, int, int, int]]],
    phase: float,
    brightness: float,
) -> list[list[tuple[int, int, int, int]]]:
    word = render_word(
        WORD, visible=letters, phase=phase, brightness=brightness
    )
    if slogan is None:
        bottom = empty_like(slogan_band)
    else:
        bottom = render_slogan(slogan, brightness=brightness)
        # Keep slogan band width fixed so partial slogans do not shrink the stack.
        if len(bottom[0]) < len(slogan_band[0]) or len(bottom) < len(slogan_band):
            fixed = empty_like(slogan_band)
            ox = (len(fixed[0]) - len(bottom[0])) // 2
            oy = (len(fixed) - len(bottom)) // 2
            for y, row in enumerate(bottom):
                for x, c in enumerate(row):
                    if c[3]:
                        fixed[oy + y][ox + x] = c
            bottom = fixed
    return stack_centered(word, bottom, gap=GAP)


def build_animation(
    canvas_w: int,
    canvas_h: int,
    slogan_band: list[list[tuple[int, int, int, int]]],
) -> tuple[list[list[list[tuple[int, int, int, int]]]], list[int]]:
    frames: list[list[list[tuple[int, int, int, int]]]] = []
    durations: list[int] = []
    phase = 0.0

    def add(mark, duration_ms: int, advance: float = 0.04):
        nonlocal phase
        card = place_on_canvas(mark, canvas_w, canvas_h, VOID)
        frames.append(card)
        durations.append(duration_ms)
        phase = (phase + advance) % 1.0

    # Letter-by-letter reveal. Empty slogan band keeps height fixed.
    for n in range(1, len(WORD) + 1):
        bright = 1.0
        mark = build_mark(n, None, slogan_band, phase, bright)
        add(mark, 140 if n < len(WORD) else 160, advance=0.05)

    # Slogan words appear after each other.
    slogan_steps = (
        "Simple",
        "Simple, Lightweight",
        "Simple, Lightweight, Fast",
    )
    for step in slogan_steps:
        bright = pulse(phase)
        mark = build_mark(len(WORD), step, slogan_band, phase, bright)
        add(mark, 900, advance=0.08)

    # Complete mark holds with color motion between them (peak-end longer).
    hold_ms = (1200, 1400, 1600)
    for hi, hold in enumerate(hold_ms):
        for _ in range(4):
            bright = pulse(phase)
            mark = build_mark(len(WORD), SLOGAN, slogan_band, phase, bright)
            add(mark, 140, advance=0.06)
        bright = pulse(phase) + (0.04 if hi == len(hold_ms) - 1 else 0.0)
        mark = build_mark(len(WORD), SLOGAN, slogan_band, phase, bright)
        add(mark, hold, advance=0.1)

    return frames, durations


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    full_word = render_word(WORD)
    slogan_band = render_slogan(SLOGAN)
    full_mark = stack_centered(full_word, slogan_band, gap=GAP)

    # Dimensions from the full mark once. Never shrink for partial content.
    canvas_w = len(full_mark[0]) + PAD * 2
    canvas_h = len(full_mark) + PAD * 2

    frames, durations = build_animation(canvas_w, canvas_h, slogan_band)

    ascii_blocks = []
    for i, fr in enumerate(frames):
        ascii_blocks.append(f"; frame {i + 1}\n{ascii_frame(fr)}")
    final = place_on_canvas(full_mark, canvas_w, canvas_h, VOID)
    (OUT / "nullray-ascii.txt").write_text(
        "\n".join(ascii_blocks) + "\n--- final ---\n" + ascii_frame(final),
        encoding="utf-8",
    )

    imgs = []
    for fr in frames:
        scaled = upscale(fr, SCALE)
        imgs.append(
            rgba_to_pil(scaled).convert("P", palette=Image.ADAPTIVE, colors=128)
        )

    out_gif = OUT / "nullray-splash.gif"
    imgs[0].save(
        out_gif,
        save_all=True,
        append_images=imgs[1:],
        duration=durations,
        loop=0,
        disposal=2,
    )

    gif_w = canvas_w * SCALE
    gif_h = canvas_h * SCALE
    print(f"canvas {canvas_w}x{canvas_h} px  gif {gif_w}x{gif_h}  frames {len(frames)}")
    print(f"wrote {out_gif.relative_to(ROOT)}")
    print(f"wrote {(OUT / 'nullray-ascii.txt').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
