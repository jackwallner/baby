#!/usr/bin/env python3
"""
Upload fastlane/metadata to App Store Connect via API (PATCH/POST localizations).

Targets an editable draft version by default (see asc-ensure-draft-version.py).
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from asc_lib import (
    ASCClient,
    META,
    bearer_token,
    bundle_id_from_appfile,
    description_for_locale,
    ensure_draft_version,
    fastlane_locale_dirs,
    find_app,
    find_editable_app_info,
    find_version_by_string,
    list_all,
    load_credentials,
    load_state,
    read_meta,
    save_state,
    find_live_version,
)


def patch_version_loc(
    client: ASCClient,
    loc: dict,
    locale: str,
    *,
    include_whats_new: bool,
) -> None:
    attrs: dict = {}
    desc = read_meta(locale, "description")
    kw = read_meta(locale, "keywords")
    rn = read_meta(locale, "release_notes")
    if desc:
        attrs["description"] = desc[:4000]
    if kw:
        attrs["keywords"] = kw[:100]
    if rn and include_whats_new:
        attrs["whatsNew"] = rn[:4000]
    for src, dst in (
        ("support_url", "supportUrl"),
        ("marketing_url", "marketingUrl"),
        ("promotional_text", "promotionalText"),
    ):
        v = read_meta(locale, src)
        if v:
            attrs[dst] = v[:4000] if dst != "promotionalText" else v[:170]
    if not attrs:
        return
    lid = loc["id"]
    client.patch(
        f"/appStoreVersionLocalizations/{lid}",
        {"data": {"type": "appStoreVersionLocalizations", "id": lid, "attributes": attrs}},
    )


def create_version_loc(client: ASCClient, version_id: str, locale: str, source: str) -> dict:
    desc = description_for_locale(locale, source)
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {
                "locale": locale,
                "description": desc,
                "keywords": (read_meta(locale, "keywords") or "headache,tracker")[:100],
            },
            "relationships": {
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
            },
        }
    }
    rn = read_meta(locale, "release_notes")
    if rn:
        body["data"]["attributes"]["whatsNew"] = rn[:4000]
    for src, dst in (("support_url", "supportUrl"), ("marketing_url", "marketingUrl")):
        v = read_meta(locale, src)
        if v:
            body["data"]["attributes"][dst] = v
    return client.post("/appStoreVersionLocalizations", body)["data"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--create-missing", action="store_true", help="POST version localizations missing on draft")
    parser.add_argument("--source-locale", default="en-US")
    args = parser.parse_args()

    version_string = os.environ.get("ASC_APP_VERSION")
    state = load_state()
    if not version_string and state.get("draftVersion"):
        version_string = state["draftVersion"]

    key_id, issuer_id, key_path = load_credentials()
    client = ASCClient(bearer_token(key_id, issuer_id, key_path))
    bundle_id = bundle_id_from_appfile()
    app = find_app(client, bundle_id)
    app_id = app["id"]
    live = find_live_version(client, app_id)

    if not version_string:
        draft = ensure_draft_version(client, app_id, None)
        version_string = draft["attributes"]["versionString"]
    else:
        draft = find_version_by_string(client, app_id, version_string)
        if not draft:
            draft = ensure_draft_version(client, app_id, version_string)
            version_string = draft["attributes"]["versionString"]

    version_id = draft["id"]
    live_vs = live["attributes"]["versionString"] if live else None
    save_state(version_string, live_vs, app_id)
    os.environ["ASC_APP_VERSION"] = version_string

    ver_locs = {
        x["attributes"]["locale"]: x
        for x in list_all(client, f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    }
    draft_info = find_editable_app_info(client, app_id)
    info_locs: dict = {}
    if draft_info and draft_info.get("attributes", {}).get("appStoreState") == "PREPARE_FOR_SUBMISSION":
        info_locs = {
            x["attributes"]["locale"]: x
            for x in list_all(client, f"/appInfos/{draft_info['id']}/appInfoLocalizations")
        }

    locales = fastlane_locale_dirs()
    updated = 0
    created = 0
    print(f"Uploading to version {version_string} ({draft['attributes'].get('appStoreState')})")

    for locale in locales:
        print(f"{locale}:", end=" ")
        if locale not in ver_locs:
            if args.create_missing:
                try:
                    ver_locs[locale] = create_version_loc(client, version_id, locale, args.source_locale)
                    created += 1
                    print("created", end=" ")
                except RuntimeError as e:
                    print(f"create-fail ({e})")
                    continue
            else:
                print("skip (not on ASC — run with --create-missing)")
                continue
        info_ok = False
        if locale in info_locs:
            attrs: dict = {}
            name = read_meta(locale, "name")
            sub = read_meta(locale, "subtitle")
            if name:
                attrs["name"] = name[:30]
            if sub:
                attrs["subtitle"] = sub[:30]
            if attrs:
                try:
                    lid = info_locs[locale]["id"]
                    client.patch(
                        f"/appInfoLocalizations/{lid}",
                        {"data": {"type": "appInfoLocalizations", "id": lid, "attributes": attrs}},
                    )
                    info_ok = True
                except RuntimeError as e:
                    print(f"info-fail ({e})", end=" ")
        try:
            patch_version_loc(
                client,
                ver_locs[locale],
                locale,
                include_whats_new=live is not None,
            )
            print("ok" + (" +info" if info_ok else ""))
            updated += 1
        except RuntimeError as e:
            print(f"fail: {e}")
        time.sleep(0.12)

    print(f"\nPatched {updated} locale(s); created {created} new version localization(s).")
    print(f"Draft: {version_string} · Live: {live_vs or 'n/a'}")
    if info_locs:
        print(f"Draft appInfo locales: {len(info_locs)} (name/subtitle on PREPARE_FOR_SUBMISSION appInfo)")
    else:
        print("appInfo: run ./scripts/upload-appstore-metadata.sh (fastlane 2.234+) to enable draft appInfo")


if __name__ == "__main__":
    main()
