# Onboarding trial conversion and zero-shift CTA

Current fleet-wide contract for adding a trial step to onboarding. This supersedes the older migration-only guidance in `ios/archive/paywalls/`.

Source history: `~/OT710.md`, Rev A and Rev B, 2026-07-10. Reference implementation: StatScout. Reusable implementation example: `~/posture/Posture/Views/Components/OnboardingBottomBar.swift`.

## Success criterion

A user advances through onboarding by tapping one fixed thumb position. On the final trial step, the button in that exact frame changes from `Continue` to `Start 7-day free trial`. One tap begins the yearly introductory purchase and presents Apple's confirmation UI.

"Same general area" is not sufficient. The primary CTA frame must be pixel-identical across all onboarding pages:

- Same x and y
- Same width and height
- Same corner radius
- Same horizontal and bottom insets

Verify exact frame equality through AXe. A screenshot-only comparison is not sufficient.

## Flow

1. Show the app's normal value, personalization, and setup pages.
2. Prefetch products and intro-offer eligibility before the trial page.
3. Present the trial as the final onboarding page, using the same background, typography, navigation, and CTA component as prior pages.
4. The primary CTA directly purchases the preferred yearly introductory package.
5. If products fail to load, the fallback may open the existing full paywall.
6. Purchase success or the soft free exit completes onboarding.

Do not insert an intermediate plan picker into the primary trial path. Monthly and lifetime remain available in the full paywall, but the onboarding page is a one-decision yearly-trial surface.

## Bottom-bar geometry

Use one shared bottom-bar component on every onboarding page. The structure is:

```text
variable content expanding upward
  page dots, soft exit, disclosure, errors

fixed primary CTA
  Continue or Start 7-day free trial

fixed-height legal-footer slot
  invisible placeholder on normal pages
  Restore, Terms, Privacy on trial page
```

The fixed footer slot is the critical detail. Reserving it only on the trial page moves the primary CTA upward and breaks the conversion mechanic.

SwiftUI shape:

```swift
struct OnboardingBottomBar<Above: View>: View {
    let primaryTitle: String
    let primaryAction: () -> Void
    let footer: OnboardingLegalFooter
    @ViewBuilder let above: () -> Above

    var body: some View {
        VStack(spacing: 0) {
            above()

            Button(primaryTitle, action: primaryAction)
                .buttonStyle(AppPrimaryButtonStyle())
                .padding(.top, 16)

            footer
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }
}
```

Normal pages render the real footer view with `.opacity(0)`, hit testing disabled, and accessibility hidden. Do not substitute a guessed spacer height. The trial page renders the same footer visibly.

Prefer `.safeAreaInset(edge: .bottom, spacing: 0)` when the page body scrolls. Variable-height body content must scroll or compress upward, never push the bottom bar below the home indicator.

## Trial-page content

Keep the page visually consistent with onboarding, not a dedicated Pro modal.

Recommended content:

- Trial-forward headline
- Two or three personalized benefits
- Optional compact Today / Day 5 reminder / Day 7 billing timeline
- Secondary `Get Started` free exit above the primary CTA
- Explicit billing disclosure above the primary CTA
- Primary `Start 7-day free trial`
- Restore, Terms of Use, and Privacy Policy in the fixed footer

Do not use `Not now` or `Maybe later` for the free exit. The fleet convention is `Get Started`, secondary and de-emphasized.

Avoid:

- Monthly/lifetime cards on the onboarding trial page
- `See all plans` as the primary action
- Large Pro branding, elaborate feature grids, or modal chrome that reveals a separate paywall system
- Price text inside the primary button
- Competing plan badges
- Social proof before the app has at least 25 credible ratings

## Purchase and eligibility

- Prefer yearly for the onboarding CTA.
- Keep monthly free-trial intros active in App Store Connect. They remain available in the full paywall.
- Check introductory-offer eligibility before claiming a free trial.
- If eligible, call the direct purchase method for the yearly package.
- If ineligible, use honest subscription copy or route to the full paywall.
- Canceling Apple's purchase confirmation returns to the trial page without completing onboarding.

## Permission ordering

Do not race an OS permission dialog with the trial surface. Product prefetch can happen in the background, but notification, HealthKit, motion, location, and tracking dialogs must have a deterministic place in the flow.

Preferred ordering depends on the app's setup needs:

- Collect personalization first.
- Present the trial after the value promise.
- Request nonessential permissions after the trial.
- If a permission is essential to setup, wait for its sheet to fully resolve before advancing or presenting another surface.

Never mark a one-shot trial pitch as shown before presentation is confirmed.

## Later pitches and review funnel

The onboarding trial is the primary day-zero conversion surface, not the only conversion opportunity.

Audit each app for:

- Contextual feature gates, session-capped
- A meaningful milestone pitch
- Re-offer behavior after dismissal
- Blind timer-based pitches that should move to a demonstrated-value moment
- Review prompts that occur only after an enjoyment or achievement gate

Do not combine the review ask with the purchase ask. The review flow remains: positive moment, explicit `Rate?`, native review request only after Yes.

## Verification checklist

- [ ] Fresh install reaches every onboarding page.
- [ ] Products and intro eligibility load before the trial claim is rendered.
- [ ] `Get Started` completes onboarding without purchasing.
- [ ] Trial CTA begins the yearly purchase directly.
- [ ] Canceling purchase remains on the trial page.
- [ ] Restore, Terms, and Privacy are available.
- [ ] Billing amount, renewal period, trial conversion, and cancellation language are visible.
- [ ] AXe reports exactly equal primary-button frames on every page.
- [ ] Small-screen content scrolls without clipping the CTA, disclosure, or price.
- [ ] Simulator testing does not configure production RevenueCat or report paywall impressions. See `../revenuecat/simulator-testing.md`.
