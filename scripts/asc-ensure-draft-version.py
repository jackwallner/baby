#!/usr/bin/env python3
"""Find or create an editable ASC app store version; write scripts/.asc-state.json."""
from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_lib import (
    ASCClient,
    bearer_token,
    bundle_id_from_appfile,
    ensure_draft_version,
    find_app,
    find_live_version,
    load_credentials,
    load_state,
    save_state,
)


def main() -> None:
    preferred = os.environ.get("ASC_DRAFT_VERSION") or os.environ.get("ASC_APP_VERSION")
    state = load_state()
    if preferred is None and state.get("draftVersion"):
        preferred = state["draftVersion"]

    key_id, issuer_id, key_path = load_credentials()
    client = ASCClient(bearer_token(key_id, issuer_id, key_path))
    bundle_id = bundle_id_from_appfile()
    app = find_app(client, bundle_id)
    live = find_live_version(client, app["id"])
    draft = ensure_draft_version(client, app["id"], preferred)

    vs = draft["attributes"]["versionString"]
    st = draft["attributes"].get("appStoreState")
    live_vs = live["attributes"]["versionString"] if live else None
    save_state(vs, live_vs, app["id"])

    print(f"draftVersion={vs} ({st})")
    if live_vs:
        print(f"liveVersion={live_vs}")
    print(f"export ASC_APP_VERSION='{vs}'")


if __name__ == "__main__":
    main()
