"""Shared App Store Connect API helpers for ASO scripts."""
from __future__ import annotations

import json
import http.client
import os
import re
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import jwt
except ImportError:
    jwt = None  # type: ignore

API = "https://api.appstoreconnect.apple.com/v1"
ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane/metadata"
STATE_FILE = Path(__file__).parent / ".asc-state.json"

EDITABLE_STATES = frozenset(
    {
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "WAITING_FOR_REVIEW",
    }
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
                k = k.strip()
                # The file is meant to be sourced by a shell, so every line is
                # `export NAME=value`. Without stripping the keyword the whole
                # fallback silently set variables named "export ASC_KEY_PATH"
                # and every script here died on "set ASC_API_KEY_ID".
                if k.startswith("export "):
                    k = k[len("export "):].strip()
                if not k:
                    continue
                v = v.strip().strip('"').strip("'")
                # Same reason: `ASC_KEY_PATH="$HOME/.appstoreconnect/..."` is a
                # shell expansion, and Python opens the literal path otherwise.
                v = os.path.expandvars(os.path.expanduser(v))
                os.environ.setdefault(k, v)
        key_id = os.environ.get("ASC_API_KEY_ID")
        issuer_id = os.environ.get("ASC_ISSUER_ID")
        key_path = os.environ.get("ASC_KEY_PATH")
    if not all([key_id, issuer_id, key_path]):
        raise SystemExit("error: set ASC_API_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH")
    return key_id, issuer_id, key_path


def bearer_token(key_id: str, issuer_id: str, key_path: str) -> str:
    if jwt is None:
        raise SystemExit("error: pip install PyJWT cryptography")
    iat = int(time.time())
    return jwt.encode(
        {"iss": issuer_id, "iat": iat, "exp": iat + 1200, "aud": "appstoreconnect-v1"},
        open(key_path).read(),
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


class ASCClient:
    """App Store Connect client that keeps its own bearer token fresh.

    Apple caps the JWT lifetime at 20 minutes. Scripts that touch every
    territory (intro offers, price schedules) routinely run longer than that,
    and a client holding a single token dies partway through with a 401 having
    already made hundreds of writes. Pass the credentials and the token is
    minted on demand instead.
    """

    #: Re-mint this many seconds before Apple's 20-minute expiry.
    REFRESH_MARGIN = 300

    #: Statuses that mean "Apple is busy", not "the request was wrong".
    RETRY_STATUSES = frozenset({429, 500, 502, 503, 504})

    #: Enough attempts, with the backoff below, to cover about two minutes.
    MAX_ATTEMPTS = 8

    def __init__(self, token: str | None = None, credentials: tuple[str, str, str] | None = None):
        self._credentials = credentials
        self._token = token
        self._minted_at = time.time() if token else 0.0
        if token is None and credentials is None:
            raise ValueError("ASCClient needs a token or credentials")

    @classmethod
    def from_credentials(cls, credentials: tuple[str, str, str] | None = None) -> "ASCClient":
        return cls(credentials=credentials or load_credentials())

    @property
    def token(self) -> str:
        expired = time.time() - self._minted_at > (1200 - self.REFRESH_MARGIN)
        if self._token is None or (self._credentials and expired):
            self._token = bearer_token(*self._credentials)  # type: ignore[misc]
            self._minted_at = time.time()
        return self._token

    def _force_refresh(self) -> bool:
        """Mint a new token after a 401. False when there is nothing to mint from."""
        if not self._credentials:
            return False
        self._token = bearer_token(*self._credentials)
        self._minted_at = time.time()
        return True

    def request(self, method: str, path: str, body: dict | None = None, _retried: bool = False) -> dict:
        url = f"{API}{path}"
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
            },
        )
        try:
            for attempt in range(self.MAX_ATTEMPTS):
                try:
                    with urllib.request.urlopen(req, timeout=120) as resp:
                        raw = resp.read().decode()
                        return json.loads(raw) if raw else {}
                except urllib.error.HTTPError as e:
                    # Apple answers a long write run with 500s and 429s that
                    # clear on their own. Four tries inside eight seconds was
                    # not enough to ride one out: setting up two subscriptions
                    # means several hundred POSTs, and the intro-offer loop died
                    # partway through every time. Back off far enough to
                    # outlast the throttle, and leave every other status to the
                    # handler below.
                    if e.code not in self.RETRY_STATUSES or attempt == self.MAX_ATTEMPTS - 1:
                        raise
                    time.sleep(min(2 ** attempt, 60))
                except (http.client.RemoteDisconnected, urllib.error.URLError, socket.timeout):
                    if attempt == self.MAX_ATTEMPTS - 1:
                        raise
                    time.sleep(min(2 ** attempt, 60))
        except urllib.error.HTTPError as e:
            # A 401 on a long run is an expired token, not a bad key. Mint a new
            # one and retry once before giving up.
            if e.code == 401 and not _retried and self._force_refresh():
                return self.request(method, path, body, _retried=True)
            err = e.read().decode()
            raise RuntimeError(f"{method} {path} -> {e.code}: {err}") from e

    def get(self, path: str) -> dict:
        return self.request("GET", path)

    def post(self, path: str, body: dict) -> dict:
        return self.request("POST", path, body)

    def patch(self, path: str, body: dict) -> dict:
        return self.request("PATCH", path, body)

    def delete(self, path: str) -> dict:
        return self.request("DELETE", path)


def list_all(client: ASCClient, path: str) -> list[dict]:
    items: list[dict] = []
    url_path = path
    while url_path:
        data = client.get(url_path)
        items.extend(data.get("data", []))
        next_url = data.get("links", {}).get("next")
        url_path = next_url.replace(API, "") if next_url else ""
    return items


def bundle_id_from_appfile() -> str:
    appfile = ROOT / "fastlane/Appfile"
    if appfile.exists():
        for line in appfile.read_text().splitlines():
            if "app_identifier" in line:
                return line.split('"')[1]
    raise SystemExit("error: could not read app_identifier from fastlane/Appfile")


def find_app(client: ASCClient, bundle_id: str) -> dict:
    bid = urllib.parse.quote(bundle_id, safe="")
    data = client.get(f"/apps?filter[bundleId]={bid}")
    apps = data.get("data", [])
    if not apps:
        raise SystemExit(f"error: no app for bundle id {bundle_id}")
    return apps[0]


def list_versions(client: ASCClient, app_id: str) -> list[dict]:
    return list_all(client, f"/apps/{app_id}/appStoreVersions")


def find_version_by_string(client: ASCClient, app_id: str, version_string: str) -> dict | None:
    for v in list_versions(client, app_id):
        if v.get("attributes", {}).get("versionString") == version_string:
            return v
    return None


def find_editable_version(client: ASCClient, app_id: str) -> dict | None:
    for state in EDITABLE_STATES:
        for v in list_versions(client, app_id):
            if v.get("attributes", {}).get("appStoreState") == state:
                return v
    return None


def find_editable_app_info(client: ASCClient, app_id: str) -> dict | None:
    """Prefer PREPARE_FOR_SUBMISSION appInfo (created by deliver 2.234+ on draft versions)."""
    infos = list_all(client, f"/apps/{app_id}/appInfos")
    if not infos:
        return None
    for state in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "METADATA_REJECTED"):
        for info in infos:
            if info.get("attributes", {}).get("appStoreState") == state:
                return info
    return infos[0]


def find_live_version(client: ASCClient, app_id: str) -> dict | None:
    live = [v for v in list_versions(client, app_id) if v.get("attributes", {}).get("appStoreState") == "READY_FOR_SALE"]
    if not live:
        return None
    return sorted(live, key=lambda x: x["attributes"].get("versionString", ""), reverse=True)[0]


def bump_version(version_string: str) -> str:
    parts = version_string.split(".")
    while len(parts) < 3:
        parts.append("0")
    try:
        parts[-1] = str(int(parts[-1]) + 1)
    except ValueError:
        parts.append("1")
    return ".".join(parts)


def create_draft_version(client: ASCClient, app_id: str, version_string: str) -> dict:
    body = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version_string},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    }
    return client.post("/appStoreVersions", body)["data"]


def ensure_draft_version(client: ASCClient, app_id: str, preferred: str | None = None) -> dict:
    editable = find_editable_version(client, app_id)
    if editable:
        return editable
    live = find_live_version(client, app_id)
    base = preferred or (live["attributes"]["versionString"] if live else "1.0.0")
    if preferred and find_version_by_string(client, app_id, preferred):
        return find_version_by_string(client, app_id, preferred)  # type: ignore
    candidate = bump_version(base)
    for _ in range(8):
        if find_version_by_string(client, app_id, candidate):
            candidate = bump_version(candidate)
            continue
        try:
            return create_draft_version(client, app_id, candidate)
        except RuntimeError as e:
            if "already been used" in str(e) or "ENTITY_ERROR" in str(e):
                candidate = bump_version(candidate)
                continue
            raise
    raise SystemExit("error: could not create a new draft ASC version")


def save_state(draft_version: str, live_version: str | None, app_id: str) -> None:
    STATE_FILE.write_text(
        json.dumps(
            {
                "appId": app_id,
                "draftVersion": draft_version,
                "liveVersion": live_version,
                "updatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            },
            indent=2,
        )
        + "\n"
    )


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def read_meta(locale: str, field: str) -> str:
    p = META / locale / f"{field}.txt"
    return p.read_text(encoding="utf-8").strip() if p.exists() else ""


def fastlane_locale_dirs() -> list[str]:
    skip = {"review_information"}
    return sorted(
        d.name
        for d in META.iterdir()
        if d.is_dir() and d.name not in skip and not d.name.endswith(".txt")
    )


def description_for_locale(locale: str, source: str = "en-US") -> str:
    desc = read_meta(locale, "description") or read_meta(source, "description")
    if len(desc) < 10:
        desc = (
            read_meta("en-US", "description")
            or "VO2 Max Daily Tracker shows Apple Health cardio fitness estimates and trends."
        )
    return desc[:4000]
