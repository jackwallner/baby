#!/usr/bin/env python3
"""Point the draft App Store version at the newest VALID TestFlight build.

A draft version keeps whatever build was attached first, so every upload leaves
the listing describing one binary and shipping another: build 8 stayed attached
for two days after logging went free, which left the description promising a
free tap that the attached build charged for. `asc-readiness.py` reports the
drift; this fixes it.

Waits for processing by default, because the build that was just uploaded is
exactly the one you want to attach and it is never VALID yet.

    scripts/asc-attach-build.py            # wait up to 30 min, then attach
    scripts/asc-attach-build.py --no-wait  # attach the requested build if VALID
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import asc_lib as a  # noqa: E402

BUNDLE_ID = "com.jackwallner.baby"


def newest_build(client: a.ASCClient, app_id: str) -> dict | None:
    builds = a.list_all(client, f"/builds?filter[app]={app_id}&limit=200")
    if not builds:
        return None
    # Sorted here rather than by the API: build numbers come back as strings,
    # and "9" sorts above "13".
    return max(builds, key=lambda b: int(b["attributes"]["version"]))


def project_build_version() -> int | None:
    project = Path(__file__).resolve().parent.parent / "project.yml"
    match = re.search(r"CURRENT_PROJECT_VERSION:\s*[\"']?(\d+)", project.read_text())
    return int(match.group(1)) if match else None


def attached_build(client: a.ASCClient, version_id: str) -> dict | None:
    response = client.get(f"/appStoreVersions/{version_id}/build")
    return response.get("data")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-wait", action="store_true", help="do not wait for processing")
    parser.add_argument("--version", type=int, help="build number to attach (defaults to project.yml)")
    parser.add_argument("--timeout", type=int, default=1800, help="seconds to wait (default 1800)")
    args = parser.parse_args()

    key_id, issuer_id, key_path = a.load_credentials()
    client = a.ASCClient(a.bearer_token(key_id, issuer_id, key_path))
    app_id = a.find_app(client, BUNDLE_ID)["id"]

    version = a.find_editable_version(client, app_id)
    if not version:
        print("error: no editable App Store version", file=sys.stderr)
        return 1
    version_id = version["id"]

    wanted_version = args.version or project_build_version()
    deadline = time.time() + (0 if args.no_wait else args.timeout)
    build = None
    while True:
        candidate = newest_build(client, app_id)
        candidate_version = int(candidate["attributes"]["version"]) if candidate else None
        if candidate and wanted_version is not None and candidate_version < wanted_version:
            print(f"waiting for build {wanted_version} to appear (latest {candidate_version})...")
        elif candidate and candidate["attributes"].get("processingState") == "VALID":
            build = candidate
            break
        elif candidate and candidate["attributes"].get("processingState") == "INVALID":
            print(f"error: build {candidate_version} is INVALID", file=sys.stderr)
            return 1
        else:
            state = candidate["attributes"].get("processingState") if candidate else "none"
            print(f"waiting for build {wanted_version or 'the newest'} to become VALID (state {state})...")
        if args.no_wait or time.time() >= deadline:
            break
        time.sleep(60)
        # The token dies at 20 minutes, so it is reminted rather than reused.
        client = a.ASCClient(a.bearer_token(key_id, issuer_id, key_path))

    if build is None:
        print("error: requested build is not VALID", file=sys.stderr)
        return 1

    wanted = build["attributes"]["version"]
    current = attached_build(client, version_id)
    if current and current["id"] == build["id"]:
        print(f"==> build {wanted} is already attached")
        return 0

    client.patch(
        f"/appStoreVersions/{version_id}/relationships/build",
        {"data": {"type": "builds", "id": build["id"]}},
    )
    was = current["attributes"]["version"] if current else "none"
    print(f"==> attached build {wanted} to version {version['attributes']['versionString']} (was {was})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
