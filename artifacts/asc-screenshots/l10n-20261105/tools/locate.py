#!/usr/bin/env python3
"""Locate a scaled capture by coarse-to-fine NCC, or a dark bezel without a raw."""
from __future__ import annotations

import argparse
import json
import math
import sys
from typing import Dict, List, Tuple

import numpy as np
from PIL import Image, ImageFilter

from common import LANCZOS


def runs(mask: np.ndarray) -> List[Tuple[int, int]]:
    edges = np.diff(np.r_[False, mask, False].astype(np.int8))
    return list(zip(np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)))


def corner_radius(image: Image.Image, box: Tuple[int, int, int, int]) -> int:
    x, y, w, h = box
    a = np.asarray(image.convert('RGB'))
    estimates = []
    limit = max(4, round(min(w, h) * .17))
    for dx_side in [False, True]:
        for dy in range(2, limit, max(1, limit // 35)):
            yy = y + dy
            if yy < 0 or yy >= image.height:
                continue
            xs = x + np.arange(limit) if not dx_side else x + w - 1 - np.arange(limit)
            if xs.min() < 0 or xs.max() >= image.width:
                continue
            row = a[yy, xs].astype(float)
            # A black bezel terminates at the colored screen. Require a sustained edge.
            light = row.max(axis=1) > 75
            starts = [s for s, e in runs(light) if e-s >= 3 and s > 0]
            if not starts:
                continue
            dx = starts[0]
            radius = dx + dy + math.sqrt(2 * dx * dy)
            if dx > 1 and radius < limit * 1.5:
                estimates.append(radius)
    return int(round(float(np.median(estimates)))) if estimates else 0


def bezel(image: Image.Image) -> Dict[str, float]:
    factor = min(1., 1000 / image.height)
    small = image.resize((round(image.width * factor), round(image.height * factor)), LANCZOS)
    a = np.asarray(small.convert('RGB'))
    dark = a.max(axis=2) < 70
    height, width = dark.shape
    current = np.zeros(width, dtype=int)
    longest = current.copy()
    for row in dark:
        current = (current + 1) * row
        longest = np.maximum(longest, current)
    bands = [(s, e) for s, e in runs(longest > height * .28) if 1 <= e-s < width * .12]
    candidates = []
    for left, le in bands:
        for right, re in bands:
            if right - le < width * .35:
                continue
            a0, b0 = (left + le) // 2, (right + re) // 2
            common = dark[:, a0] & dark[:, b0]
            spans = runs(common)
            if not spans:
                continue
            top, bottom = max(spans, key=lambda r: r[1]-r[0])
            if bottom-top < height * .28:
                continue
            candidates.append(((bottom-top) * (right-le), left, le, right, re, top, bottom))
    if not candidates:
        raise ValueError('no continuous dark bezel found')
    _, left, le, right, re, top, bottom = max(candidates)
    # Refine inner edges at native resolution along the straight part of both sides.
    native = np.asarray(image.convert('RGB')).max(axis=2) < 70
    middle_y = round((top + bottom) / (2 * factor))
    segments = runs(native[middle_y])
    left_run = min(segments, key=lambda r: abs(r[0] - left / factor))
    right_run = min(segments, key=lambda r: abs(r[0] - right / factor))
    x, x1 = int(left_run[1]), int(right_run[0])
    mid_start = x + (x1-x) // 3
    mid_end = x1 - (x1-x) // 3
    horizontal = native[:, mid_start:mid_end].mean(axis=1) > .97
    horizontal_spans = runs(horizontal)
    before = [(s, e) for s, e in horizontal_spans if e <= (top / factor + .08 * image.height)]
    after = [(s, e) for s, e in horizontal_spans if s >= (bottom / factor - .08 * image.height)]
    if not before:
        raise ValueError('bezel top is clipped or ambiguous; supply RAW')
    y = int(min(before, key=lambda r: abs(r[1] - top / factor))[1])
    if not after:
        raise ValueError('bezel bottom is clipped; supply RAW to infer its off-canvas extent')
    y1 = int(min(after, key=lambda r: abs(r[0] - bottom / factor))[0])
    if y1-y < image.height * .25:
        raise ValueError('invalid bezel height')
    score = min(1., float((bottom-top) / max(1, (y1-y) * factor)))
    box = (x, y, x1-x, y1-y)
    return dict(x=x, y=y, w=x1-x, h=y1-y, scale=1.0, score=round(score, 5),
                radius=corner_radius(image, box))


def feature(image: Image.Image) -> np.ndarray:
    # A small low-pass makes the coarse scale grid robust to resized text strokes.
    gray = image.convert('L').filter(ImageFilter.GaussianBlur(.8))
    return np.asarray(gray, dtype=np.float64)


def ncc(frame: np.ndarray, template: np.ndarray) -> np.ndarray:
    fh, fw = frame.shape
    th, tw = template.shape
    shape = tuple(1 << (int(n)-1).bit_length() for n in [fh+th-1, fw+tw-1])
    fa = np.fft.rfft2(frame, shape)
    fa2 = np.fft.rfft2(frame * frame, shape)
    fo = np.fft.rfft2(np.ones_like(frame), shape)
    tb = np.fft.rfft2(template[::-1, ::-1], shape)
    tb2 = np.fft.rfft2((template * template)[::-1, ::-1], shape)
    to = np.fft.rfft2(np.ones_like(template), shape)
    def inv(a: np.ndarray) -> np.ndarray:
        return np.fft.irfft2(a, shape)[:fh+th-1, :fw+tw-1]
    count = np.maximum(1, np.rint(inv(fo * to)))
    sa, sb = inv(fa * to), inv(fo * tb)
    va = np.maximum(0, inv(fa2 * to) - sa * sa / count)
    vb = np.maximum(0, inv(fo * tb2) - sb * sb / count)
    denom = np.sqrt(va * vb)
    result = (inv(fa * tb) - sa * sb / count) / np.maximum(1e-8, denom)
    result[(count < th * tw * .40) | (count < fh * fw * .08) | (denom < count * 2)] = -1
    return result


def search(frame: Image.Image, raw: Image.Image, widths: List[int],
           center: Tuple[float, float] = None, window: int = 0) -> Tuple[float, int, int, int]:
    frame_feature = feature(frame)
    best = (-1., 0, 0, 0)
    for width in sorted(set(widths)):
        if width < 12:
            continue
        height = round(width * raw.height / raw.width)
        template = feature(raw.resize((width, height), LANCZOS))
        scores = ncc(frame_feature, template)
        if center is not None:
            cx, cy = center
            xx, yy = round(cx) + width - 1, round(cy) + height - 1
            x0, y0 = max(0, xx-window), max(0, yy-window)
            patch = scores[y0:min(scores.shape[0], yy+window+1), x0:min(scores.shape[1], xx+window+1)]
            if not patch.size:
                continue
            py, px = np.unravel_index(np.argmax(patch), patch.shape)
            px += x0
            py += y0
        else:
            py, px = np.unravel_index(np.argmax(scores), scores.shape)
        candidate = (float(scores[py, px]), int(px-width+1), int(py-height+1), width)
        if candidate[0] > best[0]:
            best = candidate
    return best


def match(frame: Image.Image, raw: Image.Image) -> Dict[str, float]:
    coarse = min(1., 300 / max(frame.size))
    small = frame.resize((round(frame.width * coarse), round(frame.height * coarse)), LANCZOS)
    widths = [round(small.width * v) for v in np.geomspace(.22, 1.8, 45)]
    score, x, y, w = search(small, raw, widths)
    if w <= 0:
        raise ValueError('score 0.000: no overlapping capture')
    middle = min(1., 700 / max(frame.size))
    ratio = middle / coarse
    medium = frame.resize((round(frame.width * middle), round(frame.height * middle)), LANCZOS)
    proposed = w * ratio
    widths = [round(proposed * v) for v in np.linspace(.94, 1.06, 13)]
    score, x, y, w = search(medium, raw, widths, (x*ratio, y*ratio), round(8*ratio))
    if w <= 0:
        raise ValueError('score 0.000: no overlapping capture')
    # Pixel-level local refinement on the full image, with sparse samples.
    guess_x, guess_y, guess_w = x/middle, y/middle, w/middle
    fa = feature(frame)
    best = (-1., 0, 0, 0)
    spread = max(3, math.ceil(1.5/middle))
    for ww in range(round(guess_w)-spread, round(guess_w)+spread+1):
        hh = round(ww * raw.height / raw.width)
        ta = feature(raw.resize((ww, hh), LANCZOS))
        for yy in range(round(guess_y)-spread, round(guess_y)+spread+1):
            for xx in range(round(guess_x)-spread, round(guess_x)+spread+1):
                x0, y0, x1, y1 = max(0, xx), max(0, yy), min(frame.width, xx+ww), min(frame.height, yy+hh)
                if x1 <= x0 or y1 <= y0 or (x1-x0)*(y1-y0) < ww*hh*.4:
                    continue
                aa = fa[y0:y1:6, x0:x1:6].ravel()
                bb = ta[y0-yy:y1-yy:6, x0-xx:x1-xx:6].ravel()
                aa, bb = aa-aa.mean(), bb-bb.mean()
                denom = math.sqrt(float(np.dot(aa, aa) * np.dot(bb, bb)))
                value = float(np.dot(aa, bb)) / denom if denom > 1 else -1
                if value > best[0]:
                    best = (value, xx, yy, ww)
    score, x, y, w = best
    if w <= 0:
        raise ValueError('no overlapping capture found')
    # Confirm fine UI detail separately, so correlated flat gradients cannot pass.
    h = round(w * raw.height / raw.width)
    resized = raw.resize((w, h), LANCZOS).convert('L')
    gray = frame.convert('L')
    af = np.asarray(gray, dtype=float) - np.asarray(gray.filter(ImageFilter.GaussianBlur(3)), dtype=float)
    bf = np.asarray(resized, dtype=float) - np.asarray(resized.filter(ImageFilter.GaussianBlur(3)), dtype=float)
    x0, y0, x1, y1 = max(0, x)+6, max(0, y)+6, min(frame.width, x+w)-6, min(frame.height, y+h)-6
    aa = af[y0:y1:3, x0:x1:3].ravel()
    bb = bf[y0-y:y1-y:3, x0-x:x1-x:3].ravel()
    aa, bb = aa-aa.mean(), bb-bb.mean()
    denom = math.sqrt(float(np.dot(aa, aa) * np.dot(bb, bb)))
    detail = float(np.dot(aa, bb)) / denom if denom > len(aa) else -1
    score = min(score, detail)
    return dict(x=x, y=y, w=w, h=round(w*raw.height/raw.width),
                scale=round(w/raw.width, 8), score=round(score, 5))


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('frame')
    p.add_argument('raw', nargs='?')
    p.add_argument('--bezel', action='store_true')
    p.add_argument('--radius', action='store_true')
    p.add_argument('--min-score', type=float, default=.65)
    args = p.parse_args()
    if args.bezel == bool(args.raw):
        p.error('supply RAW or --bezel')
    with Image.open(args.frame) as im:
        frame = im.convert('RGB')
    if args.bezel:
        result = bezel(frame)
        if not args.radius:
            result.pop('radius')
    else:
        with Image.open(args.raw) as im:
            raw = im.convert('RGB')
        result = match(frame, raw)
        if args.radius:
            box = tuple(int(result[k]) for k in ['x', 'y', 'w', 'h'])
            result['radius'] = corner_radius(frame, box)
    if result['score'] < args.min_score:
        raise ValueError(f"score {result['score']:.3f} below {args.min_score:.3f}")
    print(json.dumps(result, separators=(',', ':')))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print(f'locate: {error}', file=sys.stderr)
        sys.exit(1)
