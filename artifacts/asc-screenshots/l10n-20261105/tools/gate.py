#!/usr/bin/env python3
"""Fail closed on missing frames, unchanged captures, bad headers and English leaks."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import unicodedata
from pathlib import Path
from typing import Any, Dict, List

import numpy as np
from PIL import Image

from common import HERE, LANCZOS, config, destinations, raw_path, read_json, source


def image_hash(path: Path) -> str:
    with Image.open(path) as im:
        im = im.convert('RGB')
        return hashlib.md5(str(im.size).encode() + im.tobytes()).hexdigest()


def unchanged_raw(a: Path, b: Path) -> bool:
    with Image.open(a) as im:
        left = im.convert('RGB')
    with Image.open(b) as im:
        right = im.convert('RGB')
    # Ignore the status bar and tolerate dates/numbers and tiny rendering noise.
    if abs(left.width / left.height - right.width / right.height) > 0.025:
        return False
    size = (400, round(400 * left.height / left.width))
    status_height = 26 if size[1] / size[0] > 1.7 else 10
    aa = np.asarray(left.resize(size, LANCZOS), dtype=np.float32)[status_height:]
    bb = np.asarray(right.resize(size, LANCZOS), dtype=np.float32)[status_height:]
    delta = np.abs(aa - bb)
    return bool(delta.mean() < 2.0 and (delta.max(axis=2) <= 8).mean() > .995)


def normalize(text: str) -> str:
    folded = unicodedata.normalize('NFKC', text).casefold()
    return ''.join(c for c in folded if c.isalnum())


def translated_values(node: Any) -> List[str]:
    if not isinstance(node, dict):
        return []
    values = []
    if 'stringUnit' in node and 'value' in node['stringUnit']:
        values.append(node['stringUnit']['value'])
    for name, child in node.items():
        if name != 'stringUnit' and isinstance(child, dict):
            values.extend(translated_values(child))
    return values


def english_sources(catalog: Path, lang: str) -> Dict[str, str]:
    data = read_json(catalog)
    source_lang = data.get('sourceLanguage', 'en')
    if not source_lang.startswith('en'):
        raise ValueError('catalog sourceLanguage must be English')
    result = {}
    for key, entry in data.get('strings', {}).items():
        locales = entry.get('localizations', {})
        translation = locales.get(lang)
        if translation is None:
            translation = locales.get(lang.split('-')[0], {})
        values = translated_values(translation)
        source_values = translated_values(locales.get(source_lang, {})) or [key]
        if values and any(normalize(v) not in {normalize(s) for s in source_values} for v in values):
            for text in [key] + source_values:
                if normalize(text):
                    result[normalize(text)] = text
    return result


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--config', type=Path, required=True)
    p.add_argument('--raw-root', type=Path, required=True)
    p.add_argument('--headers', type=Path, required=True)
    p.add_argument('--out-root', type=Path, required=True)
    p.add_argument('--locale', required=True)
    p.add_argument('--catalog', type=Path)
    p.add_argument('--lang')
    args = p.parse_args()
    if args.catalog and not args.lang:
        p.error('--catalog requires --lang')
    data, headers = config(args.config), read_json(args.headers)
    english_locale = data.get('english_locale', 'en-US')
    english = headers.get(english_locale, headers.get('en', {}))
    failures = []
    raw_frames = {}
    seen = {}
    other_hashes = {}
    for other in sorted(args.out_root.iterdir()) if args.out_root.exists() else []:
        if not other.is_dir() or other.name in [args.locale, 'sheets']:
            continue
        for candidate in sorted(other.glob('*/*.png')):
            other_hashes.setdefault(image_hash(candidate), []).append(f'{other.name}/{candidate.parent.name}/{candidate.name}')
    for key, group in data['sets'].items():
        output = args.out_root / args.locale / key
        actual = {f.name for f in output.glob('*.png')}
        expected = {f['file'] for f in group['frames']}
        if actual != expected:
            failures.append(f'COUNT {key}: expected {len(expected)}, found {len(actual)}; missing={sorted(expected-actual)} extra={sorted(actual-expected)}')
        for frame in group['frames']:
            name = f"{key}/{frame['file']}"
            text = headers.get(args.locale, {}).get(frame['file'], '')
            if not text.strip():
                failures.append(f'HEADER {name}: empty')
            if len(text.split('\n')) > 2:
                failures.append(f'HEADER {name}: more than 2 lines')
            if any(c in text for c in '.。．｡۔'):
                failures.append(f'HEADER {name}: period')
            if normalize(text) and normalize(text) == normalize(english.get(frame['file'], '')):
                failures.append(f'HEADER {name}: unchanged English')
            if frame['file'] not in english:
                failures.append(f'HEADER {name}: missing English reference ({english_locale})')
            path = output / frame['file']
            if path.is_file():
                with Image.open(path) as im:
                    if im.size != tuple(group['canvas']):
                        failures.append(f'SIZE {name}: {im.size}')
                    if 'A' in im.getbands() or 'transparency' in im.info:
                        failures.append(f'ALPHA {name}')
                digest = image_hash(path)
                if digest in seen:
                    failures.append(f'DUPLICATE {name}: {seen[digest]}')
                seen[digest] = name
                if digest == image_hash(source(data, frame['base'])):
                    failures.append(f'ENGLISH {name}: identical to base')
                for other in other_hashes.get(digest, []):
                    failures.append(f'LOCALE {name}: identical to {other}')
            for target in destinations(frame):
                raw = raw_path(args.raw_root, args.locale, key, target['raw'])
                reference = raw_path(args.raw_root, english_locale, key, target['raw'])
                if not raw.is_file():
                    failures.append(f'RAW {name}: missing {target["raw"]}')
                    continue
                raw_frames.setdefault(raw.resolve(), []).append(name)
                if not reference.is_file():
                    failures.append(f'RAW {name}: missing English reference {target["raw"]}')
                elif unchanged_raw(raw, reference):
                    failures.append(f'RAW {name}: unchanged English {target["raw"]}')
    if args.catalog:
        sources = english_sources(args.catalog, args.lang)
        if not (HERE / 'ocr').is_file():
            raise ValueError('run ./build.sh first')
        jobs = [{'path': str(raw), 'languages': ['en-US']} for raw in raw_frames]
        result = subprocess.run([str(HERE / 'ocr')], input=json.dumps(jobs), text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            raise ValueError(result.stderr.strip())
        leaks = []
        for item in json.loads(result.stdout):
            for line in item['lines']:
                if normalize(line) in sources:
                    for name in raw_frames[Path(item['path'])]:
                        leaks.append(f'LEAK {name}: {line}')
        failures.extend(leaks[:40])
        if len(leaks) > 40:
            failures.append(f'OCR {len(leaks) - 40} additional leaks suppressed')
    for failure in failures:
        print(failure)
    print('FAIL' if failures else 'PASS')
    return int(bool(failures))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError) as error:
        print(f'ERROR {error}\nFAIL')
        sys.exit(1)
