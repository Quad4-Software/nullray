#!/usr/bin/env python3
"""Write logo/nullray-word.png, logo/nullray-word.svg, and logo/nullray-profile.png.

Wordmark only (no slogan). Reuses glyphs from gen_splash_gif.py.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "logo"
SCRIPT = Path(__file__).resolve().parent / "gen_splash_gif.py"

BLACK = (0, 0, 0, 255)
CLEAR = (0, 0, 0, 0)


def load_splash():
    spec = importlib.util.spec_from_file_location("gen_splash_gif", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def pad_canvas(
    src: list[list[tuple[int, int, int, int]]],
    pad_x: int,
    pad_y: int,
    bg=CLEAR,
) -> list[list[tuple[int, int, int, int]]]:
    h, w = len(src), len(src[0])
    out = [[bg for _ in range(w + pad_x * 2)] for _ in range(h + pad_y * 2)]
    for y, row in enumerate(src):
        for x, c in enumerate(row):
            if c[3]:
                out[y + pad_y][x + pad_x] = c
    return out


def to_svg(
    px: list[list[tuple[int, int, int, int]]],
    cell: int = 12,
    path: Path | None = None,
) -> str:
    h, w = len(px), len(px[0])
    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w * cell}" height="{h * cell}" '
        f'shape-rendering="crispEdges" viewBox="0 0 {w * cell} {h * cell}">'
    ]
    for y, row in enumerate(px):
        for x, c in enumerate(row):
            if not c[3]:
                continue
            r, g, b, a = c
            fill = f"rgba({r},{g},{b},{a / 255:.3f})"
            lines.append(
                f'<rect x="{x * cell}" y="{y * cell}" width="{cell}" height="{cell}" fill="{fill}"/>'
            )
    lines.append("</svg>")
    text = "\n".join(lines) + "\n"
    if path is not None:
        path.write_text(text)
    return text


def save_scaled(
    px: list[list[tuple[int, int, int, int]]],
    path: Path,
    out_w: int,
    out_h: int,
    bg=BLACK,
) -> None:
    h, w = len(px), len(px[0])
    img = Image.new("RGBA", (w, h), bg)
    data = [c if c[3] else bg for row in px for c in row]
    img.putdata(data)
    # Nearest-neighbor so pixel edges stay crisp.
    out = img.resize((out_w, out_h), Image.Resampling.NEAREST)
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path, optimize=True)


def main() -> None:
    g = load_splash()
    word = g.render_word(pad=2)
    word_plate = pad_canvas(word, pad_x=2, pad_y=2, bg=CLEAR)

    # Wordmark plate: ~16x pixels, opaque black.
    wh, ww = len(word_plate), len(word_plate[0])
    save_scaled(word_plate, OUT / "nullray-word.png", ww * 16, wh * 16, bg=BLACK)
    to_svg(word_plate, cell=12, path=OUT / "nullray-word.svg")

    # Square profile/avatar at 512.
    side = max(wh, ww) + 10
    profile = g.place_on_canvas(word_plate, side, side, bg=BLACK)
    save_scaled(profile, OUT / "nullray-profile.png", 512, 512, bg=BLACK)

    raw = Image.new("RGBA", (len(word[0]), len(word)))
    raw.putdata([c if c[3] else CLEAR for row in word for c in row])
    raw.save(OUT / "nullray-word-raw.png", optimize=True)

    print(f"wrote {OUT / 'nullray-word.png'} ({ww * 16}x{wh * 16})")
    print(f"wrote {OUT / 'nullray-word.svg'}")
    print(f"wrote {OUT / 'nullray-profile.png'} (512x512)")
    print(f"wrote {OUT / 'nullray-word-raw.png'}")


if __name__ == "__main__":
    main()
