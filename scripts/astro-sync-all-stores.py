#!/usr/bin/env python3
"""
Sync Astro keywords for all 91 Apple Search Ads countries (Astro stores).

Uses fastlane/metadata/<locale>/ when present; otherwise fallback locales from
scripts/astro-stores-2026.json (see ~/Desktop/astro-global-aso-go-2026.md).

Usage (Astro open, MCP on):
  ./scripts/astro-sync-all-stores.py
  ./scripts/astro-sync-all-stores.py --dry-run
  ./scripts/astro-sync-all-stores.py --store de
  ./scripts/astro-sync-all-stores.py --all-astro-stores   # default: all 91
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from astro_mcp import add_keywords, call, find_app_id, list_apps, ping

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"
SCRIPT_DIR = Path(__file__).parent
CONFIG = SCRIPT_DIR / ".astro-app.json"
STORES_JSON = SCRIPT_DIR / "astro-stores-2026.json"
OUT_DIR = SCRIPT_DIR / "astro-keywords-by-store"
EN_US_CURATED = SCRIPT_DIR / "astro-keywords-us.json"

MCP_URL = "http://127.0.0.1:8089/mcp"
MAX_KEYWORDS = 45
BATCH_SIZE = 3
BATCH_SLEEP = 2.0

# ASC locale → Astro store (direct mapping when folder exists)
LOCALE_TO_STORE: dict[str, str] = {
    "ar-SA": "sa",
    "ca": "es",
    "cs": "cz",
    "da": "dk",
    "de-DE": "de",
    "el": "gr",
    "en-AU": "au",
    "en-CA": "ca",
    "en-GB": "gb",
    "en-US": "us",
    "es-ES": "es",
    "es-MX": "mx",
    "fi": "fi",
    "fr-CA": "ca",
    "fr-FR": "fr",
    "he": "il",
    "hi": "in",
    "hr": "hr",
    "hu": "hu",
    "id": "id",
    "it": "it",
    "ja": "jp",
    "ko": "kr",
    "ms": "my",
    "nl-NL": "nl",
    "no": "no",
    "pl": "pl",
    "pt-BR": "br",
    "pt-PT": "pt",
    "ro": "ro",
    "ru": "ru",
    "sk": "sk",
    "sv": "se",
    "th": "th",
    "tr": "tr",
    "uk": "ua",
    "vi": "vn",
    "zh-Hans": "cn",
    "zh-Hant": "tw",
}


def load_app_id() -> str:
    if CONFIG.exists():
        return str(json.loads(CONFIG.read_text()).get("appId", ""))
    apps = list_apps(MCP_URL)
    name_path = META / "en-US" / "name.txt"
    app_name = name_path.read_text().strip() if name_path.exists() else ""
    app_id = find_app_id(apps, app_name) if app_name else None
    if not app_id:
        raise SystemExit("error: set appId in scripts/.astro-app.json or add app in Astro")
    return app_id


def load_all_stores() -> list[dict]:
    data = json.loads(STORES_JSON.read_text())
    return data["stores"]


def read_field(meta_dir: Path, field: str) -> str:
    p = meta_dir / f"{field}.txt"
    return p.read_text(encoding="utf-8").strip() if p.exists() else ""


def is_cjk(text: str) -> bool:
    return bool(re.search(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]", text))


def tokens_from_keywords(raw: str) -> list[str]:
    raw = raw.replace("，", ",").replace("、", ",")
    return [t.strip().lower() for t in raw.split(",") if t.strip()]


def phrases_from_name_subtitle(name: str, subtitle: str, cjk: bool) -> list[str]:
    out: list[str] = []
    for text in (name, subtitle):
        text = text.strip()
        if not text:
            continue
        low = text.lower()
        for sep in (" - ", " – ", " — ", ":", "|"):
            if sep in text:
                out.extend(p.strip().lower() for p in text.split(sep) if p.strip())
        if cjk:
            if len(text) <= 40:
                out.append(text)
        else:
            if len(low) <= 50:
                out.append(low)
            words = re.findall(r"[\w']+", low, flags=re.UNICODE)
            for i in range(len(words) - 1):
                if len(words[i]) >= 3 and len(words[i + 1]) >= 3:
                    out.append(f"{words[i]} {words[i+1]}")
    return out


def locale_dirs_for_store(store_code: str, store_entry: dict) -> list[Path]:
    dirs: list[Path] = []
    seen: set[str] = set()
    candidates = list(store_entry.get("fallbackLocales", [])) + ["en-US"]
    for locale in candidates:
        d = META / locale
        if d.is_dir() and locale not in seen:
            seen.add(locale)
            dirs.append(d)
    for locale, mapped in LOCALE_TO_STORE.items():
        if mapped == store_code:
            d = META / locale
            if d.is_dir() and locale not in seen:
                seen.add(locale)
                dirs.append(d)
    return dirs


def build_keywords_for_locales(locale_dirs: list[Path], store_code: str) -> list[str]:
    items: list[str] = []
    for meta_dir in locale_dirs:
        kw_raw = read_field(meta_dir, "keywords")
        name = read_field(meta_dir, "name")
        subtitle = read_field(meta_dir, "subtitle")
        cjk = is_cjk(name + subtitle + kw_raw)
        items.extend(tokens_from_keywords(kw_raw))
        items.extend(phrases_from_name_subtitle(name, subtitle, cjk))

    if store_code == "us" and EN_US_CURATED.exists():
        items.extend(json.loads(EN_US_CURATED.read_text()).get("keywords", []))
    elif any(d.name.startswith("en-") for d in locale_dirs):
        items.extend(
            [
                "posture coach",
                "posture reminder",
                "neck pain",
                "slouch alert",
                "desk posture",
                "text neck",
                "ergonomics app",
                "posture tracker",
            ]
        )

    seen: set[str] = set()
    out: list[str] = []
    for k in items:
        k = k.strip()
        if not k or len(k) > 60:
            continue
        kl = k.lower() if not is_cjk(k) else k
        if kl not in seen:
            seen.add(kl)
            out.append(kl if not is_cjk(k) else k)
        if len(out) >= MAX_KEYWORDS:
            break
    return out


def build_store_plan(app_id: str) -> dict[str, dict]:
    plan: dict[str, dict] = {}
    for entry in load_all_stores():
        code = entry["code"]
        dirs = locale_dirs_for_store(code, entry)
        locales = [d.name for d in dirs]
        keywords = build_keywords_for_locales(dirs, code) if dirs else []
        plan[code] = {
            "country": entry["country"],
            "locales": locales,
            "fallbackLocales": entry.get("fallbackLocales", []),
            "keywords": keywords,
            "source": "fastlane" if dirs else "none",
        }
    return plan


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--store", help="Sync only this Astro store code")
    args = parser.parse_args()

    if not STORES_JSON.exists():
        raise SystemExit(f"error: missing {STORES_JSON}")

    if not ping(MCP_URL):
        raise SystemExit("error: Astro MCP not reachable — open Astro and enable MCP")

    app_id = load_app_id()
    plan = build_store_plan(app_id)

    if args.store:
        if args.store not in plan:
            raise SystemExit(f"error: unknown store {args.store}")
        plan = {args.store: plan[args.store]}

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    summary: dict = {
        "syncedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "appId": app_id,
        "storeCount": len(plan),
        "stores": {},
    }

    for store, info in sorted(plan.items()):
        keywords = info["keywords"]
        locales = info["locales"]
        payload = {
            "store": store,
            "country": info["country"],
            "locales": locales,
            "keywordCount": len(keywords),
            "keywords": keywords,
        }
        (OUT_DIR / f"{store}.json").write_text(
            json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
        )

        print(f"\n==> {store} ({info['country']}) locales=[{', '.join(locales) or 'fallback'}] — {len(keywords)} kw")
        if not keywords:
            print("    skip: no fastlane locale data")
            summary["stores"][store] = {"skipped": True, "reason": "no locale data"}
            continue

        if args.dry_run:
            for k in keywords[:10]:
                print(f"    {k}")
            if len(keywords) > 10:
                print(f"    ... +{len(keywords)-10}")
            summary["stores"][store] = {"planned": len(keywords), "added": 0}
            continue

        existing: set[str] = set()
        try:
            kws = call(MCP_URL, "get_app_keywords", {"appId": app_id, "store": store})
            existing = {k["keyword"].lower() for k in kws if isinstance(k, dict)}
        except Exception:
            pass

        missing = [k for k in keywords if k.lower() not in existing]
        added_total = 0
        for i in range(0, len(missing), BATCH_SIZE):
            batch = missing[i : i + BATCH_SIZE]
            try:
                r = add_keywords(MCP_URL, app_id, store, batch)
                added_total += sum(
                    b.get("added", 0) for b in r["batches"] if isinstance(b, dict)
                )
            except Exception as e:
                print(f"    batch fail: {e}")
            time.sleep(BATCH_SLEEP)

        print(f"    added ~{added_total} new ({len(existing)} existing)")
        summary["stores"][store] = {
            "locales": locales,
            "planned": len(keywords),
            "added": added_total,
        }

    (OUT_DIR / "_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    cfg = json.loads(CONFIG.read_text()) if CONFIG.exists() else {"appId": app_id}
    cfg.update(
        {
            "appId": app_id,
            "allAstroStores": sorted(plan.keys()),
            "syncedAt": summary["syncedAt"],
        }
    )
    CONFIG.write_text(json.dumps(cfg, indent=2) + "\n")
    print(f"\nWrote {OUT_DIR}/ ({len(plan)} stores) — playbook: astro-global-aso-go-2026.md")


if __name__ == "__main__":
    main()
