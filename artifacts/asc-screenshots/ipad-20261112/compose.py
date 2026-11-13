#!/usr/bin/env python3
"""Compose the 13-inch iPad store frames from raw simulator captures.

    python3 compose.py [locale ...]

Reads raw/<locale>/<scene>.png (2064x2752 iPad Pro 13-inch captures), writes
out/<locale>/<NN>_<scene>_APP_IPAD_PRO_3GEN_129.png at 2064x2752: the same
cream gradient, regular Avenir Next headline and black bezel bleeding off the
foot as the iPhone set, with the headlines of that set.
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
CANVAS = (2064, 2752)
SCENES = ["log", "history", "first_weeks", "summary"]
TOP, BOTTOM = (245, 240, 232), (232, 222, 208)
INK = (28, 26, 23)
FONT = "/System/Library/Fonts/Avenir Next.ttc"
HEADER_SIZE = 190
HEADER_TOP = 100
HEADER_WIDTH = 1880
BEZEL = 30
DEVICE_Y, FOOT_MARGIN = 570, 60
STATUS_STRIP = 62
SS = 3


def rounded_mask(size, radius):
    w, h = size
    mask = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w * SS - 1, h * SS - 1), radius * SS, fill=255)
    return mask.resize((w, h), Image.LANCZOS)


def background():
    img = Image.new("RGB", CANVAS)
    px = ImageDraw.Draw(img)
    for y in range(CANVAS[1]):
        t = y / (CANVAS[1] - 1)
        px.line([(0, y), (CANVAS[0], y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return img


def screen_image(path):
    raw = Image.open(path).convert("RGB")
    if raw.size != CANVAS:
        raise SystemExit(f"{path}: expected {CANVAS}, got {raw.size}")
    # The simulator's clock, date and window title are not product evidence.
    paper = raw.getpixel((1000, 6))
    ImageDraw.Draw(raw).rectangle((0, 0, raw.width, STATUS_STRIP), fill=paper)
    # So is iPadOS's window-resize grabber in the bottom right corner, which
    # straddles the History card's edge: fill each side from its own surface.
    edge = 2024
    card, page = raw.getpixel((1980, 2736)), raw.getpixel((2056, 2600))
    pen = ImageDraw.Draw(raw)
    pen.rectangle((2000, 2684, edge - 1, raw.height), fill=card)
    pen.rectangle((edge, 2684, raw.width, raw.height), fill=page)
    # The whole display shows, so no card is cut at the foot.
    inner_h = CANVAS[1] - DEVICE_Y - FOOT_MARGIN - 2 * BEZEL
    return raw.resize((round(raw.width * inner_h / raw.height), inner_h), Image.LANCZOS)


def fit_size(headers):
    """One size for a locale's set: the largest at which every line fits."""
    size = HEADER_SIZE
    while any(ImageFont.truetype(FONT, size, index=7).getlength(line) > HEADER_WIDTH
              for header in headers for line in header.split("\n")):
        size -= 2
    return size


def compose(raw_path, header, out_path, size=HEADER_SIZE):
    img = background()
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, size, index=7)
    draw.multiline_text((CANVAS[0] / 2, HEADER_TOP), header, font=font, fill=INK, anchor="ma", align="center", spacing=-4)
    screen = screen_image(raw_path)
    bezel = Image.new("RGB", (screen.width + 2 * BEZEL, screen.height + 2 * BEZEL), INK)
    bezel.paste(screen, (BEZEL, BEZEL), rounded_mask(screen.size, 62))
    img.paste(bezel, ((CANVAS[0] - bezel.width) // 2, DEVICE_Y), rounded_mask(bezel.size, 92))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path, optimize=True)


def main():
    headers = json.loads((HERE / "headers.json").read_text(encoding="utf-8"))
    locales = sys.argv[1:] or list(headers)
    for locale in locales:
        size = fit_size(headers[locale])
        for number, scene in enumerate(SCENES, start=1):
            raw = HERE / "raw" / locale / f"{scene}.png"
            out = HERE / "out" / locale / f"{number:02d}_{scene}_APP_IPAD_PRO_3GEN_129.png"
            compose(raw, headers[locale][number - 1], out, size)
            print(out.relative_to(HERE))


if __name__ == "__main__":
    main()
