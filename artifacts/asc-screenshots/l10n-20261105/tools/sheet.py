#!/usr/bin/env python3
"""Write a compact English/localized comparison per set."""
from __future__ import annotations

import argparse
import io
import sys
import tempfile
from pathlib import Path

from PIL import Image

from common import LANCZOS, config, headline, source


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', type=Path, required=True)
    p.add_argument('--locale', required=True)
    p.add_argument('--out-root', type=Path, required=True)
    p.add_argument('--base-label', default='en')
    args = p.parse_args()
    data = config(args.config)
    sheets = args.out_root / 'sheets'
    sheets.mkdir(parents=True, exist_ok=True)
    for key, group in data['sets'].items():
        frames = group['frames']
        thumb = 280
        row_height = round(thumb * group['canvas'][1] / group['canvas'][0])
        canvas = Image.new('RGB', (thumb * len(frames), 2 * (row_height + 30)), '#ffffff')
        labels = []
        for row, label in enumerate([args.base_label, args.locale]):
            for col, frame in enumerate(frames):
                path = source(data, frame['base']) if row == 0 else args.out_root / args.locale / key / frame['file']
                with Image.open(path) as im:
                    canvas.paste(im.convert('RGB').resize((thumb, row_height), LANCZOS),
                                 (col * thumb, row * (row_height + 30) + 30))
                labels.append(dict(text=f"{label}  {col+1}", locale=args.locale, font='HelveticaNeue-Bold',
                                   color=[0, 0, 0], box=[thumb, 30], size=14, align='left'))
        with tempfile.TemporaryDirectory() as tmp:
            for i, job in enumerate(labels):
                job['out'] = str(Path(tmp) / f'{i}.png')
            headline(labels)
            for i, job in enumerate(labels):
                row, col = divmod(i, len(frames))
                with Image.open(job['out']) as overlay:
                    canvas.paste(overlay, (col * thumb + 5, row * (row_height + 30)), overlay)
        for quality in range(90, 9, -5):
            encoded = io.BytesIO()
            canvas.save(encoded, format='JPEG', quality=quality, optimize=True)
            if encoded.tell() < 500000:
                break
        if encoded.tell() >= 500000:
            raise ValueError(f'{key}: sheet exceeds 500 KB; split the set')
        path = sheets / f'{args.locale}-{key}.jpg'
        path.write_bytes(encoded.getvalue())
        print(f'{path.name}: {len(frames)} pairs {len(encoded.getvalue()) // 1000} KB')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print(f'sheet: {error}', file=sys.stderr)
        sys.exit(1)
