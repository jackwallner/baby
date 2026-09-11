#!/usr/bin/env python3
"""
Analyze Astro keyword portfolio (popularity / difficulty / rank) and prune junk.

Usage (Astro must be running):
  ./scripts/astro-optimize.py                    # default store from .astro-app.json (us)
  ./scripts/astro-optimize.py --store de
  ./scripts/astro-optimize.py --store de --json
  ./scripts/astro-optimize.py --all-stores       # analyze each of 91 stores (slow)
  ./scripts/astro-optimize.py --store us --prune
  ./scripts/astro-optimize.py --store de --prune --prune-list "bad kw" "other"
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from astro_mcp import call, ping, remove_keywords

DEFAULT_CONFIG = Path(__file__).parent / ".astro-app.json"
STORES_JSON = Path(__file__).parent / "astro-stores-2026.json"
MCP_URL = "http://127.0.0.1:8089/mcp"

# US-specific junk (Phase A)
DROP_US = {
    "дневник",
    "headache tracker test phrase",
    "csv export headache",
    "siri log headache",
    "lock screen widget headache",
    "watch complication headache",
    "proactive migraine alerts",
    "weather migraine",
    "local headache journal",
    "neurologist headache log",
    "migraine app",
    "migraine specialist",
    "migraine patterns",
    "migraine alert",
    "migraine log",
    "pain diary",
    "barometric pressure headache",
}

# English phrases that are usually wrong on non-English storefronts (Phase B heuristic)
DROP_EN_ON_NON_US = {
    "headache tracker test phrase",
    "csv export headache",
    "siri log headache",
    "lock screen widget headache",
    "watch complication headache",
    "proactive migraine alerts",
    "weather migraine",
    "local headache journal",
    "neurologist headache log",
    "calorie tracker",
    "step counter",
    "pedometer",
    "daily burn",
}


def classify(k: dict) -> str:
    kw = k["keyword"].lower()
    if kw in DROP_US:
        return "drop"
    rank = k.get("currentRanking", 1000)
    pop = k.get("popularity") or 0
    diff = k.get("difficulty") or 50
    if rank <= 50:
        return "defend"
    if rank <= 150:
        return "push"
    if pop >= 40 and diff <= 80:
        return "aspirational"
    if pop >= 8 and diff <= 50:
        return "opportunity"
    return "monitor"


def drop_set_for_store(store: str, extra: list[str]) -> set[str]:
    base = set(DROP_US) if store == "us" else set()
    if store != "us":
        base |= DROP_EN_ON_NON_US
        # Cyrillic on non-ru/ua stores
        if store not in ("ru", "ua"):
            base |= {k for k in extra if re.search(r"[\u0400-\u04ff]", k)}
    base |= {x.strip().lower() for x in extra if x.strip()}
    return base


def analyze_store(app_id: str, store: str) -> dict:
    kws = call(MCP_URL, "get_app_keywords", {"appId": app_id, "store": store})
    kws = [k for k in kws if isinstance(k, dict)]
    portfolio: dict[str, list] = {
        t: [] for t in ("defend", "push", "opportunity", "aspirational", "monitor", "drop")
    }
    for k in kws:
        tier = classify(k)
        if tier != "drop" and store != "us":
            kw = k["keyword"]
            # Heuristic: pure ASCII English long phrase on non-us without local chars
            if (
                store not in ("us", "gb", "au", "ca", "nz", "ie", "sg", "ph", "in")
                and re.match(r"^[a-z0-9\s\-']+$", kw.lower())
                and " " in kw
                and kw.lower() in DROP_EN_ON_NON_US
            ):
                tier = "drop"
        portfolio[tier].append(k)
    return {"store": store, "total": len(kws), "portfolio": portfolio}


def print_report(data: dict, store: str) -> None:
    print(f"Store: {store} — {data['total']} keywords\n")
    for tier in ("defend", "push", "opportunity", "aspirational", "monitor", "drop"):
        items = sorted(data["portfolio"][tier], key=lambda x: x.get("currentRanking", 1000))
        print(f"=== {tier.upper()} ({len(items)}) ===")
        for k in items:
            pop = k.get("popularity", "?")
            diff = k.get("difficulty", "?")
            rank = k.get("currentRanking", 1000)
            ratio = (pop / max(diff, 1)) if isinstance(pop, int) and isinstance(diff, int) else 0
            print(f"  #{rank:4}  ratio={ratio:.2f}  pop={str(pop):>3}  diff={str(diff):>3}  {k['keyword']}")
        print()


def portfolio_json(data: dict) -> dict:
    return {
        data["store"]: {
            t: [
                {
                    "keyword": k["keyword"],
                    "rank": k.get("currentRanking"),
                    "popularity": k.get("popularity"),
                    "difficulty": k.get("difficulty"),
                }
                for k in sorted(v, key=lambda x: x.get("currentRanking", 1000))
            ]
            for t, v in data["portfolio"].items()
        }
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--store", default=None, help="Astro store code (us, de, …)")
    parser.add_argument("--all-stores", action="store_true", help="Analyze all 91 stores")
    parser.add_argument("--prune", action="store_true")
    parser.add_argument(
        "--prune-list",
        nargs="*",
        default=[],
        help="Extra keywords to remove (exact match, case-insensitive)",
    )
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    args = parser.parse_args()

    if not ping(MCP_URL):
        raise SystemExit("error: Astro MCP not reachable")

    cfg = json.loads(Path(args.config).read_text())
    app_id = str(cfg["appId"])

    if args.all_stores:
        stores = [s["code"] for s in json.loads(STORES_JSON.read_text())["stores"]]
        out = {}
        for i, store in enumerate(stores):
            try:
                data = analyze_store(app_id, store)
                out.update(portfolio_json(data))
                if not args.json:
                    print_report(data, store)
            except Exception as e:
                out[store] = {"error": str(e)}
                print(f"{store}: ERROR {e}", file=sys.stderr)
            if i < len(stores) - 1:
                time.sleep(1.2)
        if args.json:
            print(json.dumps(out, indent=2, ensure_ascii=False))
        return

    store = args.store or cfg.get("store", "us")
    data = analyze_store(app_id, store)

    if args.prune:
        drops = drop_set_for_store(store, args.prune_list)
        tracked = {k["keyword"].lower(): k["keyword"] for k in data["portfolio"]["drop"]}
        # Also scan all tiers for explicit prune-list + drop heuristics
        for tier in data["portfolio"].values():
            for k in tier:
                kl = k["keyword"].lower()
                if kl in drops:
                    tracked[kl] = k["keyword"]
        to_remove = list(tracked.values())
        if not to_remove:
            print(f"No keywords to prune for store={store}")
            return
        print(f"Removing {len(to_remove)} keywords from {store}...")
        result = remove_keywords(MCP_URL, app_id, store, to_remove)
        removed = sum(b.get("removed", 0) for b in result["batches"] if isinstance(b, dict))
        for kw in to_remove:
            print(f"  - {kw}")
        print(f"Removed {removed}.")
        return

    if args.json:
        print(json.dumps(portfolio_json(data), indent=2, ensure_ascii=False))
        return

    print_report(data, store)


if __name__ == "__main__":
    main()
