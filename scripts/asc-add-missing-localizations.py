#!/usr/bin/env python3
"""
Create missing App Store Connect localizations via API.

Apple requires BOTH:
  - POST /v1/appInfoLocalizations        (name, subtitle)
  - POST /v1/appStoreVersionLocalizations (description, keywords, whatsNew, urls)

Template text is copied from fastlane/metadata/<source-locale>/ (default en-US).

Usage:
  ./scripts/asc-add-missing-localizations.py --dry-run
  ./scripts/asc-add-missing-localizations.py --locales pl,no
  ./scripts/asc-add-missing-localizations.py --all-supported
  ASC_APP_VERSION=1.3.0 ./scripts/asc-add-missing-localizations.py --all-supported

Then re-pull:
  ASC_APP_VERSION=1.3.0 ./scripts/pull-appstore-metadata.sh
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import jwt
except ImportError:
    print("error: pip install PyJWT cryptography", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"
LOCALES_JSON = Path(__file__).parent / "asc-supported-locales.json"
API = "https://api.appstoreconnect.apple.com/v1"

sys.path.insert(0, str(Path(__file__).parent))
from asc_lib import (  # noqa: E402
    description_for_locale,
    ensure_draft_version,
    fastlane_locale_dirs,
    find_editable_app_info,
)


def load_credentials() -> tuple[str, str, str]:
    key_id = os.environ.get("ASC_API_KEY_ID")
    issuer_id = os.environ.get("ASC_ISSUER_ID")
    key_path = os.environ.get("ASC_KEY_PATH")
    if not all([key_id, issuer_id, key_path]):
        creds_path = Path.home() / ".baseball_credentials"
        if creds_path.exists():
            for line in creds_path.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                v = v.strip().strip('"').strip("'")
                os.environ.setdefault(k.strip(), v)
        key_id = os.environ.get("ASC_API_KEY_ID")
        issuer_id = os.environ.get("ASC_ISSUER_ID")
        key_path = os.environ.get("ASC_KEY_PATH")
    if not all([key_id, issuer_id, key_path]):
        raise SystemExit("error: set ASC_API_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH")
    return key_id, issuer_id, key_path


def token(key_id: str, issuer_id: str, key_path: str) -> str:
    iat = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": iat, "exp": iat + 1200, "aud": "appstoreconnect-v1"},
        open(key_path).read(),
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


class ASCClient:
    def __init__(self, bearer: str):
        self.bearer = bearer

    def request(self, method: str, path: str, body: dict | None = None) -> dict:
        url = f"{API}{path}"
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.bearer}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                raw = resp.read().decode()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            err = e.read().decode()
            raise RuntimeError(f"{method} {path} -> {e.code}: {err}") from e

    def get(self, path: str) -> dict:
        return self.request("GET", path)

    def post(self, path: str, body: dict) -> dict:
        return self.request("POST", path, body)


def read_meta(locale: str, field: str) -> str:
    p = META / locale / f"{field}.txt"
    return p.read_text(encoding="utf-8").strip() if p.exists() else ""


def template_for_locale(locale: str, source: str) -> dict:
    """Build ASC attributes from fastlane files (fallback source locale)."""
    src = source if (META / source).is_dir() else "en-US"
    return {
        "name": read_meta(src, "name") or read_meta("en-US", "name"),
        "subtitle": read_meta(src, "subtitle") or read_meta("en-US", "subtitle"),
        "description": read_meta(src, "description") or read_meta("en-US", "description"),
        "keywords": read_meta(src, "keywords") or read_meta("en-US", "keywords"),
        "release_notes": read_meta(src, "release_notes") or read_meta("en-US", "release_notes"),
        "support_url": read_meta(src, "support_url") or read_meta("en-US", "support_url"),
        "marketing_url": read_meta(src, "marketing_url") or read_meta("en-US", "marketing_url"),
        "promotional_text": read_meta(src, "promotional_text") or read_meta("en-US", "promotional_text"),
        "privacy_url": read_meta(src, "privacy_url") or read_meta("en-US", "privacy_url"),
    }


def list_all(client: ASCClient, path: str) -> list[dict]:
    items: list[dict] = []
    url_path = path
    while url_path:
        data = client.get(url_path)
        items.extend(data.get("data", []))
        next_url = data.get("links", {}).get("next")
        if next_url:
            url_path = next_url.replace(API, "")
        else:
            break
    return items


def find_app(client: ASCClient, bundle_id: str) -> dict:
    # Brackets in filter[...] must not be percent-encoded (Apple returns 400 otherwise).
    bid = urllib.parse.quote(bundle_id, safe="")
    data = client.get(f"/apps?filter[bundleId]={bid}")
    apps = data.get("data", [])
    if not apps:
        raise SystemExit(f"error: no app for bundle id {bundle_id}")
    return apps[0]


def find_app_info(client: ASCClient, app_id: str) -> dict:
    items = list_all(client, f"/apps/{app_id}/appInfos")
    if not items:
        raise SystemExit("error: no appInfos on app")
    return items[0]


def find_version(client: ASCClient, app_id: str, version_string: str | None) -> dict:
    items = list_all(client, f"/apps/{app_id}/appStoreVersions")
    if not items:
        raise SystemExit("error: no appStoreVersions")

    if version_string:
        for v in items:
            if v.get("attributes", {}).get("versionString") == version_string:
                return v

    prefer = (
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "WAITING_FOR_REVIEW",
        "READY_FOR_SALE",
    )
    for state in prefer:
        for v in items:
            if v.get("attributes", {}).get("appStoreState") == state:
                return v
    return items[0]


def existing_locales(items: list[dict]) -> set[str]:
    return {i.get("attributes", {}).get("locale") for i in items if i.get("attributes", {}).get("locale")}


def create_app_info_loc(client: ASCClient, app_info_id: str, locale: str, t: dict, dry_run: bool) -> None:
    body = {
        "data": {
            "type": "appInfoLocalizations",
            "attributes": {
                "locale": locale,
                "name": t["name"][:30],
                "subtitle": (t["subtitle"] or t["name"])[:30],
            },
            "relationships": {
                "appInfo": {"data": {"type": "appInfos", "id": app_info_id}}
            },
        }
    }
    if t.get("privacy_url"):
        body["data"]["attributes"]["privacyPolicyUrl"] = t["privacy_url"]
    if dry_run:
        print(f"  [dry-run] POST appInfoLocalization {locale}")
        return
    try:
        client.post("/appInfoLocalizations", body)
        print(f"  created appInfoLocalization {locale}")
    except RuntimeError as e:
        if "409" in str(e) or "403" in str(e):
            print(f"  skip appInfoLocalization {locale} (API locked — deliver upload may enable)")
        else:
            raise


def create_version_loc(
    client: ASCClient, version_id: str, locale: str, t: dict, dry_run: bool, source_locale: str
) -> None:
    desc = description_for_locale(locale, source_locale)
    attrs: dict = {
        "locale": locale,
        "description": desc,
        "keywords": (t["keywords"] or "headache,tracker")[:100],
    }
    if t.get("release_notes"):
        attrs["whatsNew"] = t["release_notes"][:4000]
    if t.get("support_url"):
        attrs["supportUrl"] = t["support_url"]
    if t.get("marketing_url"):
        attrs["marketingUrl"] = t["marketing_url"]
    if t.get("promotional_text"):
        attrs["promotionalText"] = t["promotional_text"][:170]
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": attrs,
            "relationships": {
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
            },
        }
    }
    if dry_run:
        print(f"  [dry-run] POST appStoreVersionLocalization {locale}")
        return
    try:
        client.post("/appStoreVersionLocalizations", body)
        print(f"  created appStoreVersionLocalization {locale}")
    except RuntimeError as e:
        if "409" in str(e) or "403" in str(e):
            print(f"  skip appStoreVersionLocalization {locale} (API locked — deliver upload may enable)")
        else:
            raise


def seed_fastlane_folder(locale: str, source: str) -> None:
    """Create local metadata folder so deliver can sync after API create."""
    src_dir = META / source
    dst_dir = META / locale
    if dst_dir.exists():
        return
    if not src_dir.exists():
        return
    dst_dir.mkdir(parents=True, exist_ok=True)
    for name in (
        "name.txt",
        "subtitle.txt",
        "keywords.txt",
        "description.txt",
        "release_notes.txt",
        "support_url.txt",
        "marketing_url.txt",
        "promotional_text.txt",
        "privacy_url.txt",
        "apple_tv_privacy_policy.txt",
    ):
        sp = src_dir / name
        if sp.exists():
            (dst_dir / name).write_text(sp.read_text(encoding="utf-8"), encoding="utf-8")
    print(f"  seeded fastlane/metadata/{locale}/ from {source}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--all-supported", action="store_true", help="All locales from asc-supported-locales.json")
    parser.add_argument("--locales", nargs="*", help="e.g. pl no nb")
    parser.add_argument("--source-locale", default="en-US", help="Copy text from this fastlane locale")
    parser.add_argument("--seed-folders", action="store_true", default=True, help="Create fastlane/metadata/<locale>/ stubs")
    parser.add_argument("--bundle-id", default=None)
    parser.add_argument(
        "--draft-only",
        action="store_true",
        default=False,
        help="Target PREPARE_FOR_SUBMISSION version (required for new version localizations)",
    )
    parser.add_argument(
        "--from-fastlane",
        action="store_true",
        help="Also add any fastlane/metadata/<locale>/ missing on the target version",
    )
    args = parser.parse_args()

    targets: list[str] = []
    if args.all_supported:
        targets.extend(json.loads(LOCALES_JSON.read_text())["locales"])
    if args.locales:
        targets.extend(args.locales)
    if args.from_fastlane:
        targets.extend(fastlane_locale_dirs())
    if not targets:
        raise SystemExit("error: pass --all-supported, --locales, and/or --from-fastlane")
    targets = sorted(set(targets))

    key_id, issuer_id, key_path = load_credentials()
    client = ASCClient(token(key_id, issuer_id, key_path))

    bundle_id = args.bundle_id
    if not bundle_id:
        appfile = ROOT / "fastlane/Appfile"
        if appfile.exists():
            for line in appfile.read_text().splitlines():
                if "app_identifier" in line:
                    bundle_id = line.split('"')[1]
                    break
    if not bundle_id:
        raise SystemExit("error: could not determine bundle id")

    version_string = os.environ.get("ASC_APP_VERSION")
    app = find_app(client, bundle_id)
    app_id = app["id"]
    app_info = (
        find_editable_app_info(client, app_id)
        if args.draft_only
        else find_app_info(client, app_id)
    )
    if not app_info:
        raise SystemExit("error: no appInfo found")
    if args.draft_only or not version_string:
        version = ensure_draft_version(client, app_id, version_string)
        version_string = version["attributes"]["versionString"]
        os.environ["ASC_APP_VERSION"] = version_string
    else:
        version = find_version(client, app_id, version_string)

    app_info_locs = list_all(client, f"/appInfos/{app_info['id']}/appInfoLocalizations")
    version_locs = list_all(client, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")

    have_info = existing_locales(app_info_locs)
    have_version = existing_locales(version_locs)

    print(f"App: {app_id} ({bundle_id})")
    print(f"Version: {version['attributes'].get('versionString')} ({version['attributes'].get('appStoreState')})")
    print(f"Existing appInfo locales: {len(have_info)}")
    print(f"Existing version locales: {len(have_version)}")

    created = 0
    for locale in targets:
        if locale in have_info and locale in have_version:
            continue
        t = template_for_locale(locale, args.source_locale)
        print(f"\n{locale}:")
        if locale not in have_info:
            create_app_info_loc(client, app_info["id"], locale, t, args.dry_run)
            have_info.add(locale)
        if locale not in have_version:
            create_version_loc(client, version["id"], locale, t, args.dry_run, args.source_locale)
            have_version.add(locale)
        if args.seed_folders:
            seed_fastlane_folder(locale, args.source_locale)
        created += 1

    print(f"\nDone. Processed {created} missing locale(s).")
    if not args.dry_run and created:
        print("Next: ASC_APP_VERSION=<ver> ./scripts/pull-appstore-metadata.sh")


if __name__ == "__main__":
    main()
