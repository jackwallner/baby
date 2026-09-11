# RevenueCat-safe simulator testing

Simulator launches must not create junk customers or bogus paywall impressions in the production RevenueCat project.

## Rule

Never configure RevenueCat with the production `appl_` API key in an iOS simulator build. TestFlight and App Store builds continue to use production RevenueCat.

A production SDK configuration creates an anonymous customer when the app launches. Repeated simulator installs, erased devices, and UI tests can therefore inflate:

- New customer counts
- Active customer counts
- Paywall impressions
- Trial and conversion denominators

## Preferred simulator setup

Use all three controls:

1. A checked-in `.storekit` configuration for local products and transactions.
2. A local Pro or entitlement override for deterministic UI testing.
3. A compile-time simulator guard that does not call `Purchases.configure` with the production key.

Example shape:

```swift
#if targetEnvironment(simulator)
let usesProductionRevenueCat = false
#else
let usesProductionRevenueCat = true
#endif

if usesProductionRevenueCat {
    Purchases.configure(withAPIKey: productionRevenueCatKey)
}
```

Prefer an explicit subscription-service mode over scattering simulator checks through views:

```swift
enum PurchaseEnvironment {
    case localStoreKit
    case revenueCat
}
```

The local mode should provide the same app-facing state and purchase methods as the production service, backed by StoreKit testing or deterministic fixtures.

## Acceptable alternatives

If a flow must exercise the RevenueCat SDK itself, use one of these instead of the production project:

- RevenueCat Test Store
- A separate RevenueCat project and public SDK key dedicated to automated testing

Do not use a production key merely because transactions are sandbox transactions. Sandbox purchases can still create customers and affect dashboard analytics.

## Paywall impression safeguards

For custom paywalls:

- Do not call `trackCustomPaywallImpression` in simulator, screenshot, or UI-test modes.
- Fire sheet impressions once per actual presentation.
- Session-dedupe persistent tab paywalls so switching tabs repeatedly does not multiply impressions.
- Do not use `onAppear` when a hidden paywall remains in the view hierarchy.

Example guard:

```swift
guard !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
#if targetEnvironment(simulator)
return
#else
Purchases.shared.trackCustomPaywallImpression(params)
#endif
```

## Running the simulator

Use the dedicated headless device documented in [Headless agent simulators](../simulators/headless-agent-simulators.md):

```bash
OWNER=<project>
UDID=$(agent-sim checkout "$OWNER")
trap 'agent-sim checkin "$OWNER"' EXIT
agent-sim boot "$OWNER"
xcodebuild -project App.xcodeproj -scheme App -destination "id=$UDID" test
```

Never open Simulator.app, and never share a named simulator destination between projects.

## Cleaning existing test customers

The cleanup tool is conservative by default:

```bash
cd ~/my-app
rc-clean-test-users            # dry run
rc-clean-test-users --delete   # delete classified test customers
```

For every configured app:

```bash
rc-clean-test-users --all-apps
rc-clean-test-users --all-apps --delete
```

The tool preserves customers with a real, non-sandbox purchase. It classifies customers using App Store release state, TestFlight-only versions, and sandbox purchase history. Always inspect the dry run before using `--delete`.

Cleanup is a fallback, not the normal simulator workflow. Prevent production customer creation first.

## Release boundary

Before shipping or uploading TestFlight, verify the non-simulator build:

- Configures the intended production RevenueCat public SDK key
- Uses the correct entitlement and offering identifiers
- Does not enable a local Pro override
- Tracks production paywall impressions at the intended entry points

After TestFlight agent testing, run `rc-clean-test-users` if the test created production RevenueCat customers.
