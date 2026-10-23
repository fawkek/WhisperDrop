#!/usr/bin/env python3
"""Renders the WhisperDrop app icon and every size in the asset catalog.

Usage: python3 script/make_icon.py   (needs Pillow)

Follows Apple's macOS icon grid: a 1024 px transparent canvas with an 824 px rounded
tile, so the icon looks right on macOS 14 and later. Palette "Amethyst".
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SCALE = 4                      # supersampling for smooth edges
SIZE = 1024 * SCALE
TILE = 824 * SCALE
INSET = (SIZE - TILE) // 2

VIOLET = (0x6D, 0x4A, 0xFF)
PURPLE = (0xB0, 0x4B, 0xFF)
PINK = (0xFF, 0x5F, 0xA2)


def superellipse_mask(size: int, exponent: float = 5.0) -> Image.Image:
    """Apple-like continuous-corner tile."""
    mask = Image.new("L", (size, size), 0)
    half = size / 2
    points = []
    steps = 2048
    import math
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = half + half * (abs(c) ** (2 / exponent)) * (1 if c >= 0 else -1)
        y = half + half * (abs(s) ** (2 / exponent)) * (1 if s >= 0 else -1)
        points.append((x, y))
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(size: int) -> Image.Image:
    """Violet top-left → purple → pink bottom-right."""
    small = 256
    image = Image.new("RGB", (small, small))
    pixels = image.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            color = lerp(VIOLET, PURPLE, t / 0.55) if t < 0.55 else lerp(PURPLE, PINK, (t - 0.55) / 0.45)
            pixels[x, y] = color
    return image.resize((size, size), Image.BICUBIC)


def radial(size: int, center, radius: float, alpha: float) -> Image.Image:
    """White radial glow as an alpha mask (0…255)."""
    small = 256
    mask = Image.new("L", (small, small), 0)
    pixels = mask.load()
    cx, cy = center[0] * small, center[1] * small
    r = radius * small
    for y in range(small):
        for x in range(small):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / r
            value = max(0.0, 1 - d) ** 1.6
            pixels[x, y] = round(255 * alpha * value)
    return mask.resize((size, size), Image.BICUBIC)


def render() -> Image.Image:
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    tile_mask = superellipse_mask(TILE)

    # Soft drop shadow under the tile.
    shadow = Image.new("L", (SIZE, SIZE), 0)
    shadow.paste(tile_mask, (INSET, INSET + 10 * SCALE))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * SCALE)).point(lambda v: v * 0.32)
    canvas.paste((22, 10, 48, 255), (0, 0), shadow)

    tile = diagonal_gradient(TILE).convert("RGBA")

    # Convex light from the top-left, a little depth in the bottom-right.
    highlight = radial(TILE, (0.18, 0.10), 0.85, 0.42)
    tile = Image.composite(Image.new("RGBA", (TILE, TILE), (255, 255, 255, 255)), tile, highlight)
    shade = radial(TILE, (0.95, 1.0), 0.75, 0.16)
    tile = Image.composite(Image.new("RGBA", (TILE, TILE), (60, 10, 70, 255)), tile, shade)

    # Thin light rim along the top edge.
    rim = Image.new("L", (TILE, TILE), 0)
    inner = superellipse_mask(TILE - 6 * SCALE)
    rim.paste(tile_mask, (0, 0))
    offset_inner = Image.new("L", (TILE, TILE), 0)
    offset_inner.paste(inner, (3 * SCALE, 6 * SCALE))
    rim = ImageChops.subtract(rim, offset_inner).point(lambda v: v * 0.35)
    tile = Image.composite(Image.new("RGBA", (TILE, TILE), (255, 255, 255, 255)), tile, rim)

    # Waveform: five rounded bars, centered.
    bar_width = 54 * SCALE
    gap = 44 * SCALE
    heights = [118, 214, 290, 194, 98]
    alphas = [0.78, 0.92, 1.0, 0.92, 0.78]
    total = len(heights) * bar_width + (len(heights) - 1) * gap
    x = (TILE - total) // 2
    bars = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    bar_shadow = Image.new("L", (TILE, TILE), 0)
    for height, alpha in zip(heights, alphas):
        h = height * SCALE
        top = (TILE - h) // 2
        box = (x, top, x + bar_width, top + h)
        ImageDraw.Draw(bars).rounded_rectangle(box, radius=bar_width // 2, fill=(255, 255, 255, round(255 * alpha)))
        ImageDraw.Draw(bar_shadow).rounded_rectangle(
            (box[0], box[1] + 8 * SCALE, box[2], box[3] + 8 * SCALE), radius=bar_width // 2, fill=70
        )
        x += bar_width + gap
    bar_shadow = bar_shadow.filter(ImageFilter.GaussianBlur(10 * SCALE))
    tile = Image.composite(Image.new("RGBA", (TILE, TILE), (55, 20, 120, 255)), tile, bar_shadow)
    tile = Image.alpha_composite(tile, bars)

    tile.putalpha(tile_mask)
    canvas.alpha_composite(tile, (INSET, INSET))
    return canvas.resize((1024, 1024), Image.LANCZOS)


def main() -> None:
    icon = render()
    icon.save(ROOT / "Assets/AppIcon.png")
    icon.save(ROOT / "Docs/WhisperDrop-icon.png")
    catalog = ROOT / "Assets/Assets.xcassets/AppIcon.appiconset"
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
            icon.resize((pixels, pixels), Image.LANCZOS).save(catalog / name)
    print("icon written")


if __name__ == "__main__":
    main()
