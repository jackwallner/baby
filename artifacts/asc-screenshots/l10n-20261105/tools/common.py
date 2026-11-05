"""Shared paths and image operations. All config paths are config-relative."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Tuple

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
LANCZOS = Image.Resampling.LANCZOS


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def config(path: Path) -> Dict[str, Any]:
    data = read_json(path)
    if not isinstance(data.get("sets"), dict) or not data["sets"]:
        raise ValueError("config needs nonempty sets")
    for key, group in data["sets"].items():
        if not group.get("frames"):
            raise ValueError(f"{key}: empty frames")
        names = [f["file"] for f in group["frames"]]
        if len(set(names)) != len(names):
            raise ValueError(f"{key}: duplicate configured filename")
        if any(Path(n).name != n or not n.lower().endswith('.png') for n in names):
            raise ValueError(f"{key}: file must be a PNG basename")
        canvas = group["canvas"]
        if len(canvas) != 2 or any(int(v) != v or v <= 0 for v in canvas):
            raise ValueError(f"{key}: invalid canvas")
    data["_root"] = path.resolve().parent
    return data


def source(data: Dict[str, Any], value: str) -> Path:
    return data["_root"] / value


def raw_path(root: Path, locale: str, key: str, raw: str) -> Path:
    name = raw if raw.lower().endswith('.png') else raw + '.png'
    return root / locale / key / name


def destinations(frame: Dict[str, Any]) -> List[Dict[str, Any]]:
    return [{"raw": frame["raw"], "rect": frame["screen"], "radius": frame.get("radius", 0)}] + frame.get("pastes", [])


def rect(value: List[float]) -> Tuple[int, int, int, int]:
    if len(value) != 4 or any(int(v) != v for v in value) or min(value[2:]) <= 0:
        raise ValueError(f"invalid integer rect {value}")
    return tuple(map(int, value))


def paste_screen(canvas: Image.Image, raw: Image.Image, box: List[int], radius: float) -> None:
    x, y, w, h = rect(box)
    if radius < 0 or radius > min(w, h) / 2:
        raise ValueError(f"invalid screen radius {radius}")
    # Crop after resize, so negative origins preserve the raw's coordinate system.
    resized = raw.convert("RGB").resize((w, h), LANCZOS)
    mask = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w * 4 - 1, h * 4 - 1), radius=radius * 4, fill=255)
    mask = mask.resize((w, h), LANCZOS)
    canvas.paste(resized, (x, y), mask)


def erase_header(base: Image.Image, box: List[int], plate: Image.Image = None) -> None:
    x, y, w, h = rect(box)
    if x < 0 or y < 0 or x + w > base.width or y + h > base.height:
        raise ValueError("header_box must be inside canvas")
    if plate is not None:
        if plate.size != base.size:
            raise ValueError("plate must have the canvas dimensions")
        base.paste(plate.convert("RGB").crop((x, y, x + w, y + h)), (x, y))
        return
    if x == 0 or x + w == base.width:
        raise ValueError("header_box needs background pixels on both sides; provide plate")
    pixels = np.asarray(base, dtype=np.float32)
    left, right = pixels[y:y+h, x-1:x], pixels[y:y+h, x+w:x+w+1]
    t = (np.arange(w, dtype=np.float32) + 1) / (w + 1)
    patch = np.rint(left * (1 - t[None, :, None]) + right * t[None, :, None]).clip(0, 255).astype(np.uint8)
    base.paste(Image.fromarray(patch, "RGB"), (x, y))


def headline(jobs: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    binary = HERE / "headline"
    if not binary.exists():
        raise ValueError("run ./build.sh first")
    result = subprocess.run([str(binary)], input=json.dumps(jobs, ensure_ascii=False),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError(result.stderr.strip())
    return json.loads(result.stdout)


def header_job(frame: Dict[str, Any], text: str, locale: str) -> Dict[str, Any]:
    return {"text": text, "locale": locale, "font": frame["font"], "color": frame["color"],
            "box": frame["header_box"][2:], "maxSize": frame["max_size"], "minSize": 1,
            "align": frame.get("align", "center")}
