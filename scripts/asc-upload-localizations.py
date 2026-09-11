#!/usr/bin/env python3
"""Push `fastlane/metadata/<locale>/` text to the editable App Store version.

Text only, on purpose. `upload-appstore-metadata.sh` runs fastlane deliver,
which also walks the screenshot tree and has double-uploaded a set on retry;
the 5 iPhone and 5 Apple Watch screenshots live on the en-US localization and
every other storefront falls back to them (the fleet shape, VO2 Max has
screenshot sets on 1 of its 50 localizations). So this script never touches
`appScreenshotSets`.

    python3 scripts/asc-upload-localizations.py [--dry-run] [--all-locales]
        [--locales de-DE,ja]

Validates before it writes, against the same bands `asc-readiness.py` enforces
per localization: name and subtitle 24-30 characters, keywords 94-100, promo
text at most 170, description over 200 and free of any hardcoded price. A
locale that fails is reported and skipped rather than half-written.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc_lib as A  # noqa: E402

BUNDLE_ID = "com.jackwallner.baby"
META = Path(__file__).resolve().parent.parent / "fastlane" / "metadata"

#: field -> (inclusive minimum, inclusive maximum) in characters.
LIMITS = {
    "name": (24, 30),
    "subtitle": (24, 30),
    "keywords": (94, 100),
    "promotional_text": (1, 170),
    "description": (200, 4000),
}
PRICE = re.compile(r"[$€£¥₹]\s*\d")

#: Locales whose script carries a word in one or two characters. Apple's cap is
#: still 30, but the 24-character floor is a Latin-script rule: it exists so a
#: name does not waste the field on three short words. Held against Chinese,
#: Japanese, or Korean it forces padding a finished name with filler, which
#: reads worse and ranks no better, so those locales only keep the ceiling.
DENSE_SCRIPT_LOCALES = {"ja", "ko", "zh-Hans", "zh-Hant"}
DENSE_SCRIPT_MINIMUM = 10


def read(locale: str, field: str) -> str | None:
    path = META / locale / f"{field}.txt"
    return path.read_text().strip() if path.exists() else None


def problems(locale: str) -> list[str]:
    found = []
    for field, (low, high) in LIMITS.items():
        if locale in DENSE_SCRIPT_LOCALES and field in ("name", "subtitle"):
            low = DENSE_SCRIPT_MINIMUM
        # The keyword floor is script-dependent for the same reason: 94
        # characters of Japanese or Chinese is several times the term list the
        # field holds, and only filler can reach it.
        if locale in DENSE_SCRIPT_LOCALES and field == "keywords":
            low = 0
        value = read(locale, field)
        if value is None:
            found.append(f"{field}: missing")
            continue
        if not low <= len(value) <= high:
            found.append(f"{field}: {len(value)} chars, want {low}-{high}")
    description = read(locale, "description") or ""
    if PRICE.search(description):
        found.append("description: hardcoded price")
    return found


def upsert(client: A.ASCClient, kind: str, existing: dict | None, parent: tuple[str, str, str],
           locale: str, attributes: dict, dry_run: bool) -> str:
    """Patch the localization when it exists, create it when it does not."""
    if existing:
        current = existing["attributes"]
        if all(current.get(key) == value for key, value in attributes.items()):
            return "unchanged"
        if not dry_run:
            client.patch(f"/{kind}/{existing['id']}",
                         {"data": {"type": kind, "id": existing["id"], "attributes": attributes}})
        return "updated"
    relationship, parent_type, parent_id = parent
    if not dry_run:
        client.post(f"/{kind}", {"data": {
            "type": kind,
            "attributes": {**attributes, "locale": locale},
            "relationships": {relationship: {"data": {"type": parent_type, "id": parent_id}}},
        }})
    return "created"


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    only = {"en-US"}
    if "--all-locales" in sys.argv:
        only = None
    for index, argument in enumerate(sys.argv):
        if argument == "--locales" and index + 1 < len(sys.argv):
            only = {x.strip() for x in sys.argv[index + 1].split(",")}

    # `review_information` is a fastlane directory, not a storefront, and it
    # carries a description.txt like a locale does. Filtering on that file
    # alone sent it to ASC, which 400s on filter[locale]=review_information.
    locales = [l for l in A.fastlane_locale_dirs()
               if (META / l / "description.txt").exists()]
    if only:
        locales = [l for l in locales if l in only]

    client = A.ASCClient.from_credentials()
    app_id = A.find_app(client, BUNDLE_ID)["id"]
    version = A.find_editable_version(client, app_id)
    if not version:
        print("no editable app store version", file=sys.stderr)
        return 1
    info = A.find_editable_app_info(client, app_id)

    version_locs = {x["attributes"]["locale"]: x for x in A.list_all(
        client, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")}
    info_locs = {x["attributes"]["locale"]: x for x in A.list_all(
        client, f"/appInfos/{info['id']}/appInfoLocalizations")}

    skipped = []
    for locale in locales:
        found = problems(locale)
        if found:
            skipped.append(locale)
            print(f"{locale}: SKIPPED: {'; '.join(found)}")
            continue

        info_result = upsert(
            client, "appInfoLocalizations", info_locs.get(locale),
            ("appInfo", "appInfos", info["id"]), locale,
            {"name": read(locale, "name"),
             "subtitle": read(locale, "subtitle"),
             "privacyPolicyUrl": read(locale, "privacy_url")},
            dry_run,
        )
        # Adding a language to the app info also creates that locale's version
        # localization, so the map read before the call above is already stale
        # and a blind create answers 409 DUPLICATE.
        existing_version = version_locs.get(locale)
        if existing_version is None:
            found = client.get(
                f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations"
                f"?filter[locale]={locale}"
            )["data"]
            existing_version = found[0] if found else None

        version_result = upsert(
            client, "appStoreVersionLocalizations", existing_version,
            ("appStoreVersion", "appStoreVersions", version["id"]), locale,
            {"description": read(locale, "description"),
             "keywords": read(locale, "keywords"),
             "promotionalText": read(locale, "promotional_text"),
             "marketingUrl": read(locale, "marketing_url"),
             "supportUrl": read(locale, "support_url")},
            dry_run,
        )
        print(f"{locale}: appInfo {info_result}, version {version_result}")

    print(f"\n{len(locales) - len(skipped)} of {len(locales)} locales "
          f"{'checked' if dry_run else 'pushed'}"
          + (f", skipped: {', '.join(skipped)}" if skipped else ""))
    return 1 if skipped else 0


if __name__ == "__main__":
    raise SystemExit(main())
