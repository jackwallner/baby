# Caffeine Tracker: Bedtime

Caffeine intake and bedtime forecasting. XcodeGen project and scheme:
`Caffeine`. Simulator lease owners: `caffeine` and `caffeine-watch`.

## Product

The app answers three separate questions:

1. How much caffeine did I consume today?
2. How much may remain in my system now and at bedtime?
3. What would another drink do before I log it?

The third question is the distinctive interaction. Every quick-log drink opens
a preview first. The user can change the drink, dose, and time, compare the
current and proposed bedtime estimates, see the dose-specific latest modeled
time, and then choose whether to log it. The same sheet edits an entry that is
already logged, so there is one place that answers "what would this drink do?".

A fourth question is answered by the Cutoff tab, and it is the one the product
is now positioned on: at what bedtime estimate did this person's own recorded
sleep actually run shorter? Nothing else in the category derives a per-person
cutoff from that person's own sleep record, so it is both the reason to choose
this app and the 4.3 answer. Every statement there is an observation about what
Apple Health recorded alongside the intake, never a causal or clinical claim.

Estimates use an exponential half-life model. They are not blood measurements,
medical advice, or safety cutoffs. The default half-life is 5 hours and the UI
also shows a 4 to 6 hour range.

## Stack and identifiers

- Swift 6, SwiftUI, SwiftData, HealthKit, WidgetKit, WatchConnectivity
- iOS 17+, watchOS 10+
- App: `com.jackwallner.caffeine`
- Widget: `com.jackwallner.caffeine.widget`
- Watch app: `com.jackwallner.caffeine.watch`
- Watch widget: `com.jackwallner.caffeine.watch.widget`
- Tests: `com.jackwallner.caffeine.tests`
- App Group: `group.com.jackwallner.caffeine`
- App Store Connect app: `6805950103`
- RevenueCat entitlement: `Caffeine+`

## Architecture

HealthKit dietary caffeine is the durable shared record. App entries are saved
as `HKQuantitySample` values in milligrams, tagged `HKMetadataKeyWasUserEntered`
and with the drink name in `HKMetadataKeyFoodType`. A denied or unavailable
HealthKit write falls back to `LocalCaffeineEntry`, which the originating device
retries on every foreground; the Now screen shows a banner naming the count so
the fallback is never silent. A successful retry deletes the queue row rather
than stamping it, so the local store stays a queue. SwiftData is a read-through
cache for widgets and complications.

Body insights are a second, optional HealthKit authorization, requested only
when the user turns them on. `HealthInsightsService` owns those reads so
declining them cannot affect logging or the bedtime forecast. Requested types
and the shipped feature each one feeds:

| Type | Feature |
|---|---|
| `sleepAnalysis` | time asleep, onset latency, wake-ups; the personal cutoff |
| `restingHeartRate`, `heartRateVariabilitySDNN`, `respiratoryRate`, `oxygenSaturation` | overnight comparisons |
| `heartRate` | heart rate before against after each logged dose |
| `stepCount`, `activeEnergyBurned` | same-day activity comparisons |
| `workoutType` | caffeine modeled on board at workout starts |
| `bodyMass` | intake per kilogram |
| `dateOfBirth`, `biologicalSex` | suggested starting half-life |

Nothing is requested that no surface reads. Keep that table true when changing
`HealthInsightsService.readTypes` or `BodyMetric`, because it is the 5.1.3
justification.

The phone sends settings to the watch with WatchConnectivity. It does not queue
intake entries because HealthKit synchronizes those records.

The calculation layer is pure Swift in
`Shared/Utilities/CaffeineClearance.swift`. It owns remaining-dose calculations,
bedtime forecasts, half-life ranges, source reconciliation, daily summaries,
and latest modeled drink times. Keep model tests independent of HealthKit and
SwiftUI.

Key files:

- `Shared/Utilities/CaffeineClearance.swift`
- `Shared/Utilities/CaffeineInsights.swift`
- `Shared/Utilities/DrinkPresets.swift`
- `Shared/Services/HealthKitService.swift`
- `Shared/Services/HealthInsightsService.swift`
- `Shared/Services/CaffeineLogService.swift`
- `Shared/Services/WatchSyncService.swift`
- `Shared/Services/StoreService.swift`
- `Caffeine/Views/CaffeineViews.swift`
- `Caffeine/Views/OnboardingView.swift`
- `Caffeine/Views/PaywallView.swift`
- `Caffeine/Views/BodyInsightsView.swift`
- `Caffeine/Views/SettingsView.swift`

## Onboarding

Five steps in `CaffeineOnboardingView`: what the app does, bedtime, the caffeine
Apple Health permission, the optional body-data permission, and one Caffeine+
step that can purchase in place.

Every step renders through the same `page(...)` builder, which is what keeps the
primary button in a pixel-identical frame across all five. Step-specific content
(a soft exit, the price disclosure, an error) goes in `aboveButton` and is
absorbed by the scrolling region; a fixed-height legal slot is reserved under the
button on every step and carries real Terms, Privacy, and Restore links on the
Caffeine+ step. Do not add anything between the button and the bottom of the
screen, and do not make a step's footer conditional on its content: both move the
button.

The Caffeine+ step is a point of purchase, so it renders the billed amount, the
3.1.2 disclosure, and that legal footer. Products failing to load falls back to
the full paywall rather than a dead button.

`-OnboardingStep <n>` (DEBUG) opens a step directly, which is the only way to
check the button frame headlessly. `-StartTab <n>` (DEBUG) opens a tab without
entering screenshot mode, which screenshot mode would empty of products.

## Navigation

Four tabs: Now, Cutoff, Timeline, and Upgrade (titled `Caffeine+` for a
subscriber). The second tab was called Body; it is named for its output now,
because the tab bar is in every screenshot and a reviewer scanning the set has
to be able to see what this app does that the category does not.

Settings is a gear in the Now toolbar, matching the rest of the fleet. There is
no Planner tab; that surface folded into the drink preview, which was already
reachable from Now.

The Now card names its own inputs. `CaffeineClearance.contributions` breaks the
running estimate into per-dose shares, the card summarises them in one line, and
`RemainingBreakdownSheet` lists them. A first launch frequently shows a non-zero
estimate before the user has tapped anything, because Apple Health already held
dietary caffeine from another app, and an unattributed number there reads as one
the app invented.

The Upgrade tab renders `CaffeinePaywallView` inline with no close button. The
tab bar stays visible over it, so nothing traps the user on a purchase screen,
and a subscriber gets a permanent place to see and manage what they bought.

## Access model

Logging, previewing a drink, current and bedtime estimates, Apple Health source
controls, widgets, complications, and seven days of history are free.

Caffeine+ unlocks the Cutoff tab's metric-by-metric comparisons, full history
and trends, editable quick-log drinks, and the bedtime reminder. A lapsed
subscriber keeps saved preset values, but cannot edit them until access is
restored. The locked range in Timeline shows a lock panel; it never renders
seven days under a `30D` label.

The cutoff verdict is free, and that is a reversal. It was moved behind the
lock because meeting the feature as the words "No clear difference" gave people
no reason to want more of it. Apple rejected 1.0 under 4.3, and the decisive
fact was that a reviewer on a fresh install could not reach the one screen that
distinguishes this app from a half-life calculator: it was behind both a
purchase and 21 nights of history. Conversion tuning does not get to hide the
differentiator. The verdict renders for everyone; the comparisons underneath it
are still Caffeine+, pitched with the person's real findings rendered blurred.
Nothing under that blur is invented; it is the same view Caffeine+ unblurs.

While the first 21 nights accumulate, `cutoffExample` renders a fixed worked
example under the progress bar, headed "EXAMPLE OF THE FINDING - NOT YOUR DATA".
It exists so the feature is legible on day one, to a new user and to a reviewer
who will never have 21 nights. Its numbers are constants and must stay
unmistakably labelled; the moment it could read as a measurement of the person
looking at it, it is a 1.4.1 problem instead of an explanation.

`PlusFeature` is the single list of what Caffeine+ includes. Paywall bullets and
in-app locked rows both read from it so they cannot drift, and it must not list
the cutoff: a paywall bullet selling something that renders free is its own
3.1.2 problem.

Store products:

- `com.jackwallner.caffeine.monthly`, $5.99 with a one-week trial
- `com.jackwallner.caffeine.yearly`, $29.99 with a one-week trial
- `com.jackwallner.caffeine.pro.lifetime`, $59.99

## App Review constraints

- Never describe a modeled estimate as a measurement of caffeine in the body.
- Never claim that a displayed time guarantees sleep or safety.
- Use `may remain`, `modeled`, `estimate`, and `preference` consistently.
- Body insights describe what was recorded alongside the caffeine. Never phrase
  one as an effect caffeine caused, and never present the personal cutoff as a
  limit, a target, or a recommendation.
- A comparison with too little data says so. `CaffeineInsights` withholds a
  result rather than reporting a confident-looking number from a small or
  lopsided sample, and "no measurable difference" is a shipped answer.
- Every paywall state, including loading and failure, renders Restore, Terms of
  Use, and Privacy Policy (3.1.2). So does the Caffeine+ onboarding step.
- The buy screen is one viewport: hero, three `PlusFeature` lines, three plans,
  the billed amount, the CTA, the disclosure, and the footer. There is no full
  feature list on it; that belongs to the subscriber state. Anything added here
  pushes Restore and the two required links under the tab bar, so measure the
  bottom of the screen after changing it.
- Do not include prices, `free`, or discounts in screenshots or screenshot headers.
- App Store name: `Caffeine Tracker: Bedtime`.
- Subtitle: `Your Sleep Sets The Cutoff`. It carries the differentiator, because
  the name cannot: `Caffeine Cutoff` sits too close to the shipping competitor
  `Caffeine Curfew` and would argue Apple's 4.3 case for them.
- Keywords: `coffee,tea,intake,calculator,energy,drink,log,timer,metabolism,widget,watch,mg,half-life,decaf,focus`.
  `sleep` and `cutoff` moved into the subtitle, which freed both slots.
- All 50 locales carry native copy. Name and subtitle target 24-30 characters
  and keywords 94-100, except `ja`, `ko`, `zh-Hans`, and `zh-Hant`, where a word
  is one or two characters and the floor would only buy filler; those keep
  Apple's ceiling alone on all three fields. `asc-readiness.py` and
  `asc-upload-localizations.py` both encode that exception. The keyword half of
  it was missing until the 4.3 rework, so those four storefronts silently
  skipped every localization upload.
- `scripts/aso-apply-cutoff-repositioning.py` rewrites the positioning lines of
  all 49 non-en-US descriptions from `aso-cutoff-strings.json`. The localized
  files share a fixed 40-line shape, so it addresses lines by index rather than
  matching native prose. Apple's description ceiling is 4000 characters and the
  Romance and Dravidian storefronts sit within ~100 of it, so any line that
  grows there has to be paid for by shortening another.
- `scripts/asc-replace-iphone-screenshots.py` swaps the iPhone set in place and
  leaves the Watch set alone. Use it instead of `deliver`, which walks the whole
  tree and has double-uploaded on retry.

## Release

Run `xcodegen generate`, tests on a leased simulator UDID, then
`./scripts/testflight.sh`. App Store scripts target ASC app `6805950103`.
The rejected Protein app has ASC ID `6797089333` and must not be reused for this
submission.
