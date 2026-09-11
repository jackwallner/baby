# Current paywall playbook

Current shared guidance for native RevenueCat paywalls and trial pitches. The May 2026 migration guide remains available under `../archive/paywalls/`, but this document is the active product and layout contract.

## Separate the two surfaces

### Onboarding trial page

A single-decision conversion step that feels like onboarding:

- Preferred yearly trial only
- Direct purchase from the primary CTA
- `Get Started` free path
- No plan cards
- Pixel-identical CTA geometry across onboarding

See [Onboarding trial conversion and zero-shift CTA](../onboarding/trial-conversion-thumb-zone.md).

### Full paywall

The durable plan picker used by Settings, Upgrade tabs, and feature gates:

- Yearly selected by default
- Monthly, yearly, and lifetime available
- Monthly and yearly trial eligibility represented honestly
- Restore, Terms, Privacy, and complete billing disclosure
- App-specific visual design

Do not replace every paywall with the onboarding surface. They solve different decisions.

## Offer hierarchy

Unless an app has an explicit commercial model:

- Lead with yearly and select it by default.
- Keep monthly available, including its existing free-trial intro.
- Keep lifetime available as a one-time purchase.
- Use one clear badge winner, normally yearly.
- Do not place a louder `BEST DEAL` badge on lifetime while trying to drive trial starts.
- The billed annual amount must remain at least as conspicuous as subordinate per-month math.

Product cards should use localized StoreKit or RevenueCat price strings. Never hard-code displayed prices.

## Trial framing

Recommended CTA and reassurance stack:

```text
Start My 7-Day Free Trial
then <localized yearly price> per year
No payment now · Reminder before billing
```

Keep price and disclosure near the CTA, but not inside the CTA label.

When space permits, use a compact transparency timeline:

- Today: full access, no charge
- Day 5: reminder before renewal
- Day 7: annual billing begins unless canceled

Only promise a reminder if the app actually schedules or sends one.

## Thumb zone and bottom purchase area

For sheet and full-screen paywalls:

- Pin the purchase area with `.safeAreaInset(edge: .bottom, spacing: 0)`.
- Keep the primary action above the home indicator.
- Let hero, benefit, and plan content scroll behind or above the purchase area.
- Reserve enough bottom content inset so the final plan or legal text is not hidden by the pinned bar.
- Keep the selected plan and localized billed price visible before purchase.

The bottom area should remain stable while products load, plans change, errors appear, or processing begins. Variable error and disclosure content should expand upward rather than moving the purchase button unpredictably.

## Content density

A full paywall must work on the smallest supported screen and large Dynamic Type.

Prioritize above the fold:

1. Close or back action, when the paywall is dismissible
2. Trial-forward or benefit-forward headline
3. Selected offer and billed price
4. Primary CTA
5. Trial and renewal disclosure

Then include concise benefits and alternate plans. Avoid a 1,000-point static composition that requires the user to find the purchase action after scrolling through a large hero, three feature cards, and three product cards.

Use two or three benefit rows, not a complete feature catalog.

## Eligibility and purchase behavior

- Query RevenueCat offerings and StoreKit-localized prices.
- Check introductory-offer eligibility before showing trial language.
- Update the CTA when the selected package changes.
- Purchase through the existing service abstraction.
- Dismiss on confirmed entitlement activation.
- Expose Restore Purchases at the purchase point.
- Preserve pending, canceled, failed, and restored states without falsely granting Pro.

Lifetime must never use subscription or trial language.

## Entry-point behavior

### Onboarding

Use the zero-shift direct yearly-trial page, not the full picker.

### Feature gate

A compact trial pitch may lead with the locked value and direct yearly trial. Keep `See all plans` secondary if users need other options.

### Settings or Upgrade tab

Use the full plan picker.

### Passive re-offer

Trigger after demonstrated value, not a blind launch timer. Examples include completing a session, seeing real health data, reaching a streak milestone, or attempting a genuinely useful Pro feature.

Session-cap contextual pitches. Do not permanently burn a one-shot flag until the surface actually presents.

## Custom RevenueCat impressions

- Track the actual visible paywall entry point, not view construction.
- Sheet opens count per presentation.
- Persistent paywall tabs should be session-deduped.
- Do not track a hidden view's `onAppear`.
- Skip tracking in simulator, screenshot, and UI-test modes.

See [RevenueCat-safe simulator testing](../revenuecat/simulator-testing.md).

## Apple subscription disclosure

At or immediately adjacent to purchase, show:

- Trial duration, if eligible
- Localized billed amount and billing period after the trial
- Automatic-renewal behavior
- Cancellation requirement before renewal
- Where subscriptions can be managed or canceled
- Restore Purchases
- Privacy Policy
- Apple Standard EULA or the app's applicable Terms of Use

The billed total must not be visually subordinated to a calculated monthly equivalent.

## Health and wellness copy

Do not claim that Pro treats, cures, prevents, or diagnoses a condition. Sell tracking, reminders, patterns, convenience, personalization, complementary techniques, and access to features.

## Verification

- Test no-products, loading, eligible, ineligible, purchase, cancel, pending, restore, and error states.
- Verify every supported plan shows the correct localized price and period.
- Verify the selected plan is obvious and only one badge wins.
- Test the smallest supported iPhone and large Dynamic Type.
- Confirm no disclosure, price, or CTA is clipped.
- Capture simulator screenshots and inspect AXe labels and frames.
- Exercise the direct purchase path with StoreKit configuration.
- Confirm simulator runs do not create production RevenueCat customers or impressions.
- Confirm TestFlight uses the production RevenueCat key and actual StoreKit products.
