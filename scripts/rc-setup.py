#!/usr/bin/env python3
"""Wire the Baby App Store products into RevenueCat.

This is the one step blocking a real purchase. The `default` offering exists in
the Baby RC project but has **zero packages**, so a device build shows
"Baby+ Plans Unavailable" no matter how healthy the App Store side is.

Usage:
    RC_KEY=sk_... python3 scripts/rc-setup.py            # apply
    RC_KEY=sk_... DRY_RUN=1 python3 scripts/rc-setup.py  # preview

The `sk_` secret key is a RevenueCat **management** key from Dashboard →
Project settings → API keys → Secret keys. It is deliberately not stored on
disk and must never ship in an app binary (App Review 1.4). Pass it in the
environment for this one run.

V2 secret keys are **project-scoped**: every one of the fleet's existing keys
(VO2 Max, Bridge, Cribbage, Mahj, StatScout, Aging, Queasy, DreamCart) returns
exactly its own project from `GET /projects` and 404s on anything else. So no
existing key can reach Baby, and the key for this run has to be created in
the Baby project itself. That also means `find_project` cannot rely on the
name matching: a scoped key returning one project *is* the answer.

Ported from ~/health/scripts/rc-setup.py with one substantive difference: that
version indexes into the offering's existing packages and would raise a
KeyError here, because Baby's offering has none yet. This one creates any
missing package before attaching products to it.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

BASE = "https://api.revenuecat.com/v2"
BUNDLE_ID = "com.jackwallner.baby"
PROJECT_NAMES = {"baby", "baby left"}
# The entitlement that exists in the project has the lookup key "baby";
# "Baby+" is only its display name. Looking it up by the display name found
# nothing and would have created a second entitlement beside the real one,
# leaving the products attached to the copy. It is not "pro" either: that was
# the documented contract for a while, but nothing ever created it.
ENTITLEMENT_KEY = "baby"
ENTITLEMENT_NAME = "Baby+"
# Mirrors RevenueCatConfig.publicSDKKey; the run warns if the project hands back
# a different production key, which would mean the binary talks to another app.
EXPECTED_PUBLIC_KEY = "appl_qiLuKnhdneTEYzRYOtaovXNgZRa"

# (store identifier, display name, RC product type, offering package key)
PRODUCTS = (
    ("com.jackwallner.baby.monthly", "Monthly", "subscription", "$rc_monthly"),
    ("com.jackwallner.baby.yearly", "Yearly", "subscription", "$rc_annual"),
    ("com.jackwallner.baby.pro.lifetime", "Lifetime", "one_time", "$rc_lifetime"),
)

DRY_RUN = os.environ.get("DRY_RUN") == "1"

# Fixed anonymous id for the read-back check, so repeated runs reuse one
# throwaway customer instead of minting a new one each time.
PROBE_SUBSCRIBER = "probe-check"


def request(method: str, path: str, body: dict | None = None) -> dict:
    key = os.environ.get("RC_KEY")
    if not key:
        raise SystemExit(
            "error: set RC_KEY to a RevenueCat secret (sk_...) management key.\n"
            "       Dashboard -> Project settings -> API keys -> Secret keys."
        )
    if DRY_RUN and method != "GET":
        print(f"  [dry-run] {method} {path} {json.dumps(body) if body else ''}")
        # Echo the request body back so callers that read fields off a freshly
        # created object (lookup_key, display_name) survive the preview run.
        return {"id": "dry-run", "items": [], **(body or {})}

    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Authorization", f"Bearer {key}")
    req.add_header("Content-Type", "application/json")
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data=data, timeout=120) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()[:800]
        raise RuntimeError(f"{method} {path} -> {error.code}: {detail}") from error


def find_project() -> dict:
    projects = request("GET", "/projects")["items"]
    for project in projects:
        if project["name"].strip().lower() in PROJECT_NAMES:
            return project
    if len(projects) == 1:
        # Project-scoped key: whatever it can see is the project it belongs to.
        # find_app() below still refuses to write to the wrong one, because it
        # requires an app with Baby's bundle id.
        print(f"note: key is scoped to the single project {projects[0]['name']!r}")
        return projects[0]
    names = ", ".join(repr(project["name"]) for project in projects)
    raise SystemExit(
        f"error: no RevenueCat project matching {sorted(PROJECT_NAMES)}.\n"
        f"       Projects this key can see: {names}\n"
        f"       Add the right name to PROJECT_NAMES and re-run."
    )


def find_app(project_id: str) -> dict:
    apps = request("GET", f"/projects/{project_id}/apps")["items"]
    for app in apps:
        if app.get("app_store", {}).get("bundle_id") == BUNDLE_ID:
            return app
    found = ", ".join(
        repr(app.get("app_store", {}).get("bundle_id") or app["name"]) for app in apps
    )
    raise SystemExit(
        f"error: no app in this project with bundle id {BUNDLE_ID}.\n"
        f"       Apps here: {found}\n"
        f"       Either the key belongs to a different app's project, or the\n"
        f"       App Store app has not been created in RevenueCat yet."
    )


def ensure_products(project_id: str, app_id: str) -> dict[str, dict]:
    existing = request("GET", f"/projects/{project_id}/products?limit=100")["items"]
    by_identifier = {product["store_identifier"]: product for product in existing}

    configured: dict[str, dict] = {}
    for identifier, display_name, product_type, _ in PRODUCTS:
        product = by_identifier.get(identifier)
        if product is None:
            product = request(
                "POST",
                f"/projects/{project_id}/products",
                {
                    "store_identifier": identifier,
                    "app_id": app_id,
                    "type": product_type,
                    "display_name": display_name,
                },
            )
            print(f"  created product  {identifier}")
        else:
            print(f"  product exists   {identifier}")
        configured[identifier] = product
    return configured


def ensure_entitlement(project_id: str) -> dict:
    entitlements = request("GET", f"/projects/{project_id}/entitlements")["items"]
    for entitlement in entitlements:
        if entitlement["lookup_key"] == ENTITLEMENT_KEY:
            print(f"  entitlement ok   {ENTITLEMENT_KEY}")
            return entitlement
    entitlement = request(
        "POST",
        f"/projects/{project_id}/entitlements",
        {"lookup_key": ENTITLEMENT_KEY, "display_name": ENTITLEMENT_NAME},
    )
    print(f"  created entitlement {ENTITLEMENT_KEY}")
    return entitlement


def attach_to_entitlement(project_id: str, entitlement: dict, products: dict[str, dict]) -> None:
    attached = request(
        "GET",
        f"/projects/{project_id}/entitlements/{entitlement['id']}/products?limit=100",
    )["items"]
    attached_ids = {product["id"] for product in attached}
    missing = [
        product["id"] for product in products.values() if product["id"] not in attached_ids
    ]
    if not missing:
        print(f"  entitlement has all {len(products)} products")
        return
    request(
        "POST",
        f"/projects/{project_id}/entitlements/{entitlement['id']}/actions/attach_products",
        {"product_ids": missing},
    )
    print(f"  attached {len(missing)} products to '{ENTITLEMENT_KEY}'")


def ensure_offering(project_id: str) -> dict:
    offerings = request("GET", f"/projects/{project_id}/offerings")["items"]
    for offering in offerings:
        if offering.get("lookup_key") == "default" or offering.get("is_current"):
            if not offering.get("is_current"):
                print(
                    f"  WARNING: offering '{offering['lookup_key']}' is not the current"
                    " offering; the app reads `.current` and will still show no plans."
                    " Mark it current in the dashboard."
                )
            return offering
    offering = request(
        "POST",
        f"/projects/{project_id}/offerings",
        {"lookup_key": "default", "display_name": "Baby+", "is_current": True},
    )
    print("  created offering 'default'")
    return offering


def ensure_packages(project_id: str, offering: dict, products: dict[str, dict]) -> None:
    """Create the three packages if absent, then attach each product to its own.

    This is the step that is actually missing on this project: the offering is
    present and current but empty, which is exactly what makes the paywall show
    its unavailable state on a real device.

    Note the package sub-resource paths are flat (`/projects/{id}/packages/...`),
    *not* nested under the offering. The published v2 reference documents the
    nested form; the live API 404s on it. Verified against the Bridge project,
    where the flat path returns 200 and the nested one 404s. Do not "fix" these
    to match the docs.
    """
    packages = request(
        "GET", f"/projects/{project_id}/offerings/{offering['id']}/packages?limit=100"
    )["items"]
    by_key = {package["lookup_key"]: package for package in packages}

    for identifier, display_name, _, package_key in PRODUCTS:
        package = by_key.get(package_key)
        if package is None:
            package = request(
                "POST",
                f"/projects/{project_id}/offerings/{offering['id']}/packages",
                {"lookup_key": package_key, "display_name": display_name},
            )
            print(f"  created package  {package_key}")
        else:
            print(f"  package exists   {package_key}")

        if package["id"] == "dry-run":
            print(f"  [dry-run] would attach {identifier} -> {package_key}")
            continue

        attached = request(
            "GET", f"/projects/{project_id}/packages/{package['id']}/products?limit=100"
        )["items"]
        attached_ids = {item["product"]["id"] for item in attached}
        product = products[identifier]
        if product["id"] in attached_ids:
            print(f"  already attached {identifier} -> {package_key}")
            continue
        request(
            "POST",
            f"/projects/{project_id}/packages/{package['id']}/actions/attach_products",
            {"products": [{"product_id": product["id"], "eligibility_criteria": "all"}]},
        )
        print(f"  attached         {identifier} -> {package_key}")


def verify(public_key: str) -> bool:
    """Read the offering back through the public SDK endpoint, which is the
    exact call the app makes. Anything the app will see, this sees.

    The subscriber id is fixed on purpose. Hitting this endpoint creates an
    anonymous RevenueCat customer, so reusing one id keeps the count at one
    throwaway rather than one per run.
    """
    req = urllib.request.Request(
        f"https://api.revenuecat.com/v1/subscribers/{PROBE_SUBSCRIBER}/offerings"
    )
    req.add_header("Authorization", f"Bearer {public_key}")
    req.add_header("X-Platform", "ios")
    with urllib.request.urlopen(req, timeout=60) as response:
        payload = json.loads(response.read())

    current = payload.get("current_offering_id")
    ok = False
    for offering in payload.get("offerings", []):
        count = len(offering.get("packages", []))
        marker = " (current)" if offering["identifier"] == current else ""
        state = "OK" if count else "STILL EMPTY"
        print(f"  offering '{offering['identifier']}'{marker}: {count} packages [{state}]")
        if count and offering["identifier"] == current:
            ok = True
    if not ok:
        print(
            "\n  Packages exist in the dashboard but the SDK endpoint returns none.\n"
            "  RevenueCat drops packages whose store product it cannot fetch, so the\n"
            "  usual cause is the App Store Connect link: check the In-App Purchase\n"
            "  key and the app-specific shared secret under the project's App Store\n"
            "  app, and that the products are READY_TO_SUBMIT on the ASC side."
        )
    return ok


def main() -> None:
    project = find_project()
    project_id = project["id"]
    app = find_app(project_id)
    app_id = app["id"]
    print(f"project: {project['name']}")
    print(f"app:     {app['name']} ({BUNDLE_ID})")
    if DRY_RUN:
        print("mode:    DRY RUN, nothing will be written")

    print("\nproducts:")
    products = ensure_products(project_id, app_id)

    print("\nentitlement:")
    entitlement = ensure_entitlement(project_id)
    attach_to_entitlement(project_id, entitlement, products)

    print("\noffering packages:")
    offering = ensure_offering(project_id)
    ensure_packages(project_id, offering, products)

    keys = request("GET", f"/projects/{project_id}/apps/{app_id}/public_api_keys")["items"]
    production_key = next(
        (key["key"] for key in keys if key["environment"] == "production"), None
    )
    if production_key:
        print(f"\npublic SDK key: {production_key}")
        if production_key != EXPECTED_PUBLIC_KEY:
            print(
                f"  WARNING: does not match RevenueCatConfig.publicSDKKey\n"
                f"           ({EXPECTED_PUBLIC_KEY}) in Shared/Services/StoreService.swift"
            )
        else:
            print("  matches RevenueCatConfig.publicSDKKey in Shared/Services/StoreService.swift")

    if DRY_RUN:
        print("\ndry run complete, nothing was written")
        return

    if production_key:
        print("\nverifying through the public offerings endpoint the app uses:")
        if not verify(production_key):
            raise SystemExit(1)

    print("\ndone: the paywall will now render three plans on a device build")


if __name__ == "__main__":
    main()
