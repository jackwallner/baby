#!/usr/bin/env python3
"""Build the complete App Store screenshot gallery.

The first two iPhone images are paired-device marketing compositions made
from real iPhone and watch captures. The remaining images are native iPhone
captures with the same brand backdrop and typography.

Raw captures from a pool iPhone 17 Pro live in ``Screenshots/raw``. The Apple
Watch captures are staged in the App Store screenshot directory after being
rendered headlessly on the paired watch simulator.

    python3 scripts/build-screenshots.py [raw-capture-dir]
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

CANVAS = (1320, 2868)
INK = (17, 17, 19)
ORANGE = (255, 126, 30)
MUTED = (116, 116, 122)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "fastlane" / "screenshots" / "en-US"
BACKDROP = ROOT / "scripts" / "assets" / "screenshot-backdrop.png"
WATCH_DIR = OUT

FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial.ttf",
]


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                font = ImageFont.truetype(path, size)
                if bold:
                    try:
                        font.set_variation_by_name("Bold")
                    except Exception:
                        pass
                return font
            except Exception:
                continue
    return ImageFont.load_default()


def wrap(draw: ImageDraw.ImageDraw, text: str, font, max_width: int) -> list[str]:
    words, lines, current = text.split(), [], ""
    for word in words:
        trial = f"{current} {word}".strip()
        if draw.textlength(trial, font=font) <= max_width:
            current = trial
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def backdrop() -> Image.Image:
    generated = Image.open(BACKDROP).convert("RGB")
    fitted = ImageOps.fit(generated, CANVAS, method=Image.Resampling.LANCZOS)
    return Image.blend(fitted, Image.new("RGB", CANVAS, "white"), 0.28).convert("RGBA")


def rounded_image(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1), radius=radius, fill=255
    )
    result = Image.new("RGBA", image.size, (255, 255, 255, 0))
    result.paste(image.convert("RGB"), (0, 0), mask)
    return result


def add_shadow(canvas: Image.Image, image: Image.Image, position: tuple[int, int], blur: int = 32) -> None:
    mask = image.getchannel("A") if "A" in image.getbands() else Image.new("L", image.size, 255)
    shadow_alpha = mask.point(lambda value: round(value * 0.28))
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 255), (0, 0), shadow_alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow, position)


def centered_text(draw: ImageDraw.ImageDraw, center_x: int, y: int, text: str, font, fill) -> None:
    box = draw.textbbox((0, 0), text, font=font)
    draw.text((center_x - (box[2] - box[0]) / 2, y), text, font=font, fill=fill)


def draw_watch(canvas: Image.Image, screen: Image.Image, position: tuple[int, int], width: int = 460) -> tuple[int, int]:
    height = round(screen.height * width / screen.width)
    screen = screen.resize((width, height), Image.Resampling.LANCZOS)
    x, y = position
    case = (x - 18, y - 18, x + width + 18, y + height + 18)
    strap_width = round(width * 0.58)
    strap_x = x + (width - strap_width) // 2
    strap_top = y - 180
    strap_bottom = y + height + 180

    shadow = Image.new("RGBA", (width + 80, height + 400), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (40, 180, width + 40, height + 198),
        radius=92,
        fill=(0, 0, 0, 92),
    )
    shadow_draw.rounded_rectangle(
        (strap_x - x + 40, 0, strap_x - x + strap_width + 40, height + 400),
        radius=44,
        fill=(0, 0, 0, 76),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)), (x - 40, strap_top))

    strap = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    strap_draw = ImageDraw.Draw(strap)
    strap_draw.rounded_rectangle(
        (strap_x, strap_top, strap_x + strap_width, y + 54),
        radius=40,
        fill=(29, 29, 31, 255),
    )
    strap_draw.rounded_rectangle(
        (strap_x, y + height - 54, strap_x + strap_width, strap_bottom),
        radius=40,
        fill=(29, 29, 31, 255),
    )
    canvas.alpha_composite(strap)

    case_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(case_layer).rounded_rectangle(
        case,
        radius=98,
        fill=(13, 13, 15, 255),
        outline=(75, 75, 79, 255),
        width=5,
    )
    canvas.alpha_composite(case_layer)
    canvas.alpha_composite(rounded_image(screen, 88), (x, y))
    return width, height


def place_phone(canvas: Image.Image, raw: Path, position: tuple[int, int], width: int = 740) -> tuple[int, int]:
    phone = Image.open(raw).convert("RGB")
    height = round(phone.height * width / phone.width)
    phone = rounded_image(phone.resize((width, height), Image.Resampling.LANCZOS), 58)
    add_shadow(canvas, phone, position, blur=36)
    canvas.alpha_composite(phone, position)
    return width, height


def draw_header(draw: ImageDraw.ImageDraw, title: str, subtitle: str) -> None:
    title_font = load_font(82, bold=True)
    subtitle_font = load_font(38)
    draw.text((96, 116), title, font=title_font, fill=INK)
    draw.text((100, 246), subtitle, font=subtitle_font, fill=ORANGE)


def compose_pair(
    phone_raw: Path,
    watch_capture: Path,
    title: str,
    subtitle: str,
    watch_label: str,
    watch_caption: str,
    bottom_caption: str,
    output: Path,
) -> None:
    canvas = backdrop()
    draw = ImageDraw.Draw(canvas)
    draw_header(draw, title, subtitle)

    phone_position = (50, 570)
    phone_width, phone_height = place_phone(canvas, phone_raw, phone_position)

    watch_position = (820, 1390)
    watch_screen = Image.open(watch_capture).convert("RGB")
    watch_width, watch_height = draw_watch(canvas, watch_screen, watch_position)

    label_font = load_font(30, bold=True)
    caption_font = load_font(28)
    center_x = watch_position[0] + watch_width // 2
    label_y = watch_position[1] + watch_height + 250
    centered_text(draw, center_x, label_y, watch_label, label_font, ORANGE)
    centered_text(draw, center_x, label_y + 48, watch_caption, caption_font, MUTED)

    bottom_font = load_font(40, bold=True)
    draw.text((96, 2460), bottom_caption, font=bottom_font, fill=INK)
    canvas.convert("RGB").save(output, format="PNG")
    print(f"wrote {output.relative_to(ROOT)} ({CANVAS[0]}x{CANVAS[1]})")


def compose_single(raw: Path, headline: str, output: Path) -> None:
    canvas = backdrop()
    draw = ImageDraw.Draw(canvas)
    title_font = load_font(82, bold=True)
    margin = 96
    band_height = 430
    for line_index, line in enumerate(wrap(draw, headline, title_font, CANVAS[0] - margin * 2)):
        draw.text((margin, 138 + line_index * 98), line, font=title_font, fill=INK)

    shot = Image.open(raw).convert("RGB")
    available_height = CANVAS[1] - band_height - 56
    available_width = CANVAS[0] - margin * 2
    scale = min(available_width / shot.width, available_height / shot.height)
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.Resampling.LANCZOS)
    screen = rounded_image(shot, 52)
    position = ((CANVAS[0] - screen.width) // 2, band_height)
    canvas.alpha_composite(screen, position)
    canvas.convert("RGB").save(output, format="PNG")
    print(f"wrote {output.relative_to(ROOT)} ({CANVAS[0]}x{CANVAS[1]})")


def main() -> None:
    raw_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Screenshots" / "raw"
    OUT.mkdir(parents=True, exist_ok=True)

    phone_today = raw_dir / "shot-today.png"
    watch_face = WATCH_DIR / "9_APP_WATCH_SERIES_10_complication.png"
    watch_today = WATCH_DIR / "5_APP_WATCH_SERIES_10_today.png"
    required = [
        phone_today,
        raw_dir / "shot-sources.png",
        raw_dir / "shot-history.png",
        raw_dir / "shot-paywall.png",
        watch_face,
        watch_today,
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise SystemExit(f"missing capture(s): {', '.join(missing)}")

    compose_pair(
        phone_today,
        watch_face,
        "Baby. At a glance.",
        "Track on iPhone. Glance on your watch.",
        "WATCH FACE",
        "Live total, one glance away.",
        "One number, wherever you need it.",
        OUT / "1_APP_IPHONE_67_today.png",
    )
    compose_pair(
        phone_today,
        watch_today,
        "Log it from your wrist.",
        "One tap, no phone required.",
        "WRIST LOGGING",
        "Add baby in one tap.",
        "Your phone can stay in your pocket.",
        OUT / "2_APP_IPHONE_67_watch.png",
    )
    compose_single(
        raw_dir / "shot-sources.png",
        "Counts baby in Apple Health.",
        OUT / "3_APP_IPHONE_67_sources.png",
    )
    compose_single(
        raw_dir / "shot-history.png",
        "Every day, against your target.",
        OUT / "4_APP_IPHONE_67_history.png",
    )
    compose_single(
        raw_dir / "shot-paywall.png",
        "Logging stays free.",
        OUT / "5_APP_IPHONE_67_paywall.png",
    )


if __name__ == "__main__":
    main()
