# Baby release and market audit

Date: 2026-09-12

Scope: read-only review of the Baby repository, App Store Connect metadata and
official competitor material. No build upload, submission, CloudKit mutation,
or external account change was performed. `laudit912.md` is a Pitchcrier audit;
only its general graphic, CTA, and accessibility observations are relevant here.

## Verdict

Baby has a credible focused position: a private, calm, one-screen newborn log
for the last feed, side, diaper, and sleep event. It should compete on speed,
low cognitive load, no account, iCloud caregiver sharing, and the first-weeks
tally, rather than chase Huckleberry or Nara feature breadth, AI, or prediction.

The API-visible App Store Connect checks are clean. The release is staged for a
later submission pass, with a few manual checks and product-safety decisions
still to close. `READY_TO_SUBMIT` products and zero review submissions are
expected before the owner chooses to stage and submit the first release, not
ASC readiness failures.

1. Before an actual submit, use ASC web UI to attach the subscription group,
   both subscriptions, and lifetime IAP to the draft version. The public API
   does not provide the first-release IAP attachment path. After staging,
   verify the products are `WAITING_FOR_REVIEW` and the draft has five review
   items. This is a pre-submit procedure, not a current API-readiness failure.
2. Complete the two-account CloudKit acceptance test. Production schema and
   owner-side sharing are verified, but the repository explicitly records that
   accepting an invitation from a second iCloud account is unverified.
3. Revise the first-weeks guidance presentation before release. The current
   disclaimer is appropriately non-diagnostic. The table can remain a clearly
   labeled breastfeeding reference, but must not read as universal personal
   targets or assess an incomplete log. Details below. No clinician sign-off is
   asserted here as an App Review requirement.
4. Manually confirm the ASC regulated-medical-device declaration is `No`. Apple
   does not expose that declaration through the public API. The RevenueCat
   default offering has now been confirmed read-only with three package
   mappings; its lack of a dashboard paywall is expected because Baby renders a
   native SwiftUI paywall instead of RevenueCatUI.
5. Verify the production-shaped paywall in the StoreKit Testing scheme for
   monthly, yearly, lifetime, restore, trial eligibility, failed product load,
   and legal-link layout. The static ASC check cannot prove those states.

## App Store Connect evidence

Read-only `python3 scripts/asc-readiness.py` reported no gaps:

- app `6811133796`, version 1.0, build 8 attached and current;
- version state `PREPARE_FOR_SUBMISSION`;
- name, subtitle, keywords, description, subscription disclosure, review
  details, contact fields, age rating, and category present;
- six iPhone screenshots and one Apple Watch screenshot;
- monthly, yearly, and lifetime products exist, but each is
  `READY_TO_SUBMIT`;
- privacy, support, and marketing URLs returned HTTP 200.

The absence of a review submission and the `READY_TO_SUBMIT` product states are
normal staging state before the owner starts a submission. The first-release
ASC workflow still requires the web UI's Monetization “Add for Review” step
when submission is authorized. The repository's `asc-submit-for-review.py
--dry-run` confirmed version 1.0 and build 8, then exited without creating or
submitting anything because no `READY_FOR_REVIEW` submission exists.

A direct read-only ASC query found zero review submissions. This is normal while
the owner has not started a submission. The first-IAP attachment remains a
required ASC web step when submission is authorized. Do not run the repository's
submit or TestFlight scripts for this audit.

Metadata currently has one `en-US` locale. That is internally complete and has
no hardcoded price figures. If more locales are added, replicate the EULA and
subscription disclosures in every description. The local legal pages use
`jackwallner.com`, while ASC points to the equivalent GitHub Pages URLs. Both
variants returned 200, but using one canonical family would reduce review
ambiguity.

Documentation hygiene: `README.md` still says the app is not built, and
`.claude/rules/release-verification.md` still describes build 5 and an
undeployed schema. Update those before handoff so release instructions do not
send the next operator down a stale path.

## Guidance.swift safety review

Relevant source: [`Shared/Utilities/Guidance.swift`](../Shared/Utilities/Guidance.swift).
The current copy does several things correctly: it says the ranges are general
guidance for healthy full-term newborns, directs parents to their pediatrician,
states that the app does not diagnose, treat, or assess, and keeps medical
device classification at `NONE` in the ASC readiness output.

The current risk is primarily presentation and scope, with one clear source
alignment issue. The NHS Healthier Together breastfeeding ladder supports the
wet progression 1, 2, 3, 4, 5, 6 and stool progression 1, 1, 2, 2, 2, 2. Baby
currently matches the wet progression but uses dirty minima 1, 2, 3, 3, 3, 3.
The app should either align those values to the cited source or document the
different source, then label the table as a breastfeeding reference rather than
a universal target. It should not infer health from an incomplete log.

The following `Guidance.swift` lines should be revised or clearly contextualized
before App Review:

- Lines 38-43 apply `8-12` feeds to every newborn. AAP describes roughly
  10-12 sessions for breastfed newborns and at least 8 for bottle-fed newborns.
  Keep the range only under an explicit breastfeeding-reference label, or split
  the copy by feeding mode.
- Lines 38-43 present wet minimums of 1, 2, 3, 4, 5, then 6 as a universal day-of-life
  ladder. The NHS breastfeeding reference supports that progression, while AAP
  also describes variation. Label it as a reference and do not call it a
  personal minimum.
- Lines 38-43 present dirty minima 1, 2, 3, 3, 3, 3 as universal, while the
  cited NHS breastfeeding reference uses 1, 1, 2, 2, 2, 2. Line 53 says no
  dirty diaper in 24 hours during the first week. AAP describes substantial
  stool variation, distinguishes breastfed and formula-fed patterns, and gives
  more specific urgency around no meconium in 48 hours and early feeding
  concerns.
  Remove the per-row `comparison` warning at lines 61-69: a missing tap is not
  health data, and an incomplete log should not be described as below range.
- Line 55 says to call for brick-dust or reddish staining after day four. AAP notes pink or brick-red
  staining can occur in the first week and emphasizes contacting the clinician
  when it persists or is concerning. Qualify the line with persistence or
  concern instead of making it an unconditional alarm.
- Line 56 has the right 100.4 F / 38 C threshold, but should say
  who needs immediate advice and how the temperature was measured. AAP's
  threshold is for a baby under 3 months and a rectal temperature. Link the AAP
  fever guidance rather than presenting the number as a universal warning.

Suggested disposition: keep the non-diagnostic disclaimer, label the table
“Breastfeeding reference, first 14 days,” remove per-row below-range assessment,
and add direct NHS and AAP links. Align the stain and fever wording with the
source context. This is a safety-copy improvement, not a request for diagnosis,
treatment, predictions, or an unrequired clinician sign-off.

Proposed replacement copy for the parent to adapt:

```text
Intro: Breastfeeding reference for the first 14 days. These day-of-life
examples are for keeping a tally, not targets or a health assessment. Follow
the plan your pediatrician gave your baby.

Reference label: BREASTFEEDING REFERENCE

Call card title: When to call

Call lines:
- For a baby 3 months or younger, call right away for a rectal temperature of
  100.4°F (38°C) or higher.
- Call if your baby is hard to wake for feeds, too weak to suck, or is not
  feeding.
- Call if your baby has fewer wet diapers than your pediatrician expects, or no
  urine for 8 hours.
- If there has been no meconium in the first 48 hours, call your pediatrician.
- Pink or brick-red stains can happen in the first week. Call if they continue
  or you are concerned.

Disclaimer: Baby Tracker is a log, not medical advice. It does not diagnose,
treat, or assess your baby. A missing entry does not mean there is a problem.
Call your pediatrician with any concern.

Source line: Breastfeeding reference adapted from NHS Healthier Together and
American Academy of Pediatrics parent guidance. Your pediatrician's advice
comes first.
```

The proposed copy deliberately describes what to record and when to seek advice;
it does not interpret a count as normal, abnormal, or diagnostic.

Official clinical references reviewed:

- [NHS Healthier Together breastfeeding day-by-day reference](https://www.swlondon-healthiertogether.nhs.uk/new-baby/keeping-your-child-safe-2-1/breastfeeding-your-baby)

- [How Often and How Much Should Your Baby Eat?](https://www.healthychildren.org/English/ages-stages/baby/feeding-nutrition/Pages/how-often-and-how-much-should-your-baby-eat.aspx)
- [Fever and Your Baby](https://www.healthychildren.org/English/health-issues/conditions/fever/Pages/Fever-and-Your-Baby.aspx)
- [Baby's First Days: Bowel Movements and Urination](https://www.healthychildren.org/English/ages-stages/baby/Pages/Babys-First-Days-Bowel-Movements-and-Urination.aspx)
- [Bringing Baby Home](https://www.healthychildren.org/English/ages-stages/prenatal/delivery-beyond/Pages/Bringing-Baby-Home.aspx)
- [Breast-Feeding Questions, AAP Symptom Checker](https://www.healthychildren.org/English/tips-tools/Symptom-Checker/IFrame/Pages/symptomviewer.aspx?symptom=Breast-Feeding%20Questions)

## Official market comparison

| App | Official evidence | What it means for Baby |
| --- | --- | --- |
| [Huckleberry tracking](https://huckleberrycare.com/product/tracking) and [App Store listing](https://apps.apple.com/us/app/huckleberry-baby-tracker/id1169136078) | Free essentials, one-touch sleep/feed/diaper logging, custom tracking, multi-child profiles, caregiver sync, reminders, Apple Watch, and paid sleep plans, insights, and AI. | Do not match its breadth. Make the four primary actions faster, explain the private/no-account boundary, and position First Weeks as a focused newborn discharge companion. |
| [Nara Baby](https://nara.com/pages/nara-baby-tracker-app), [FAQ](https://nara.com/pages/nara-baby-tracker-faq), and [App Store listing](https://apps.apple.com/us/app/nara-baby-pregnancy-tracker/id1444639029) | Free and ad-free, shared caregiver hub, timers, Live Activities, Watch, Siri, multiple children, trends, exports, and AAP/CDC-based guides. | This is the closest calm, free, caregiver-friendly comparator. Baby needs a crisp reason to pay for PDF/trends, while keeping free logging, history, and sharing obvious. Privacy/no account and the deliberately narrow control set are useful differentiators. |
| [Baby Tracker by Nighp](https://www.nighp.com/), [App Store listing](https://apps.apple.com/us/app/baby-tracker-newborn-log/id779656557), and [FAQ](https://nighp.com/babytracker/FAQ.html) | Broad feeds, pumping, solids, sleep, growth, health, medication, charts, CSV/PDF, caregiver and device sync, Watch, widgets, and a free 3-day Plus preview. | Generic search language and feature breadth are its advantage. Keep “Feeds & Diapers” in the title/subtitle, lead with the last-event answer and first-weeks tally, and avoid implying Baby is a full medical record. |

The differentiator to repeat in product copy is: “The quiet newborn log that
answers what happened last, keeps the essentials free, and shares privately
through iCloud.” Validate that every part of this sentence is true in the
production build before using it in metadata.

## Fleet patterns and UX translation

Local reference apps inspected read-only:

- `../babydocs/design.md` and `../babydocs/BabyDocs/Views/PlusPurchaseView.swift`:
  one type system, 4pt spacing, tokenized geometry, 44pt targets, pressed card
  feedback, explicit accessibility values, a visible “Free, and staying free”
  boundary, and a sticky purchase footer that repeats selected price, period,
  renewal, restore, and legal links. Baby's paywall has most legal elements,
  but could borrow the visible free boundary and plan-specific CTA where trial
  eligibility is known.
- `../vitals/Vitals/Views/PaywallView.swift` and its UI tests: focus-specific
  benefit copy, product-load retry/recovery, a fixed checkout footer, and tests
  that keep all plans visible and legal links accessible. Add equivalent Baby
  edge-state tests if the runtime owner has time.
- `../simpleglp/SimpleGLP/Utilities/AppTheme.swift`: calm cream, sage, teal,
  and coral tokens demonstrate a restrained wellness palette. Borrow the
  restraint, not its domain language.

For the requested bold-outline direction, the current screenshots already have
strong black outer frames, large short headers, simple icons, and calm fills.
The runtime controls are softer rounded cards. If polishing before submission,
apply one consistent 2px ink outline or outlined symbol treatment to the four
primary categories and one meaningful focal graphic on onboarding or First
Weeks. Pair every icon with its short label, preserve the current one-screen
logging flow, and do not add decorative mascots, a fifth primary action, or
color-only meaning. This is polish, not a release blocker.

## SwiftUI source audit of the current UI diff

Read-only review of `Components.swift`, `AppTheme.swift`, `NowView.swift`,
`LogButtons.swift`, `OnboardingView.swift`, and `SharingView.swift` found no
recursive view declaration or obvious layout feedback loop:

- `graphicBorder()` (Components.swift:18-23) is a finite opaque modifier. It
  does not call itself or `card()`. Applying it after an existing background
  creates nested shape layers, but no recursion or stack path.
- `NowView` (lines 15-42) measures the parent with `GeometryReader`, then uses
  that fixed measurement to choose a finite wide or compact branch. The
  `GeometryReader` is outside the `ScrollView`, so the child does not feed its
  measured height back into the reader.
- `NowStatusCard`, `LoggingControls`, and `TodayTotalsView` are separate small
  view types. `LogButtons` has a three-item `ForEach` and one conditional
  `TimelineView` only while sleep is running, not a timer per row.
- Onboarding's `ViewThatFits` evaluates two finite header arrangements. Sharing
  has a finite `Group` state machine and an extracted `SharedLogGraphic`; there
  is no route from either view back into itself.
- The remaining cost is ordinary observation fan-out: the status card, logging
  controls, and totals read the shared `EventStore`. A newborn log is small, so
  this is not a clear performance or stack fault. The summary equality includes
  a bounded recent-ID list, also not large enough to explain a SIGSEGV.

The reported first-build `NowView.nowCard.getter` SIGSEGV points at a symbol
that no longer exists after extraction. With concurrent `NowSummary` edits, a
mixed incremental object or stale ABI is more likely than source recursion.
Perform a clean DerivedData rebuild before attributing the crash to this view.
If a clean build still reproduces it, isolate the `GeometryReader` branch and
the `contentTransition` modifiers separately. No source evidence currently
justifies removing the one-screen layout.

## RevenueCat read-only verification

Using `rc` 0.1.1 with project `Baby Placeholder` (`proj0b545ae2`):

- `rc offerings list` shows one active current offering, lookup key `default`.
- `rc offerings verify` shows three packages in order: `$rc_monthly`,
  `$rc_annual`, and `$rc_lifetime`, with the Baby+ entitlement attached to the
  three App Store product identifiers.
- `rc offerings preview app53361f54f1` shows the SDK-facing current offering
  `default` with all three platform product mappings:
  `com.jackwallner.baby.monthly`, `com.jackwallner.baby.yearly`, and
  `com.jackwallner.baby.pro.lifetime`.
- `rc offerings verify` reports `offering has no attached paywall`. This is not
  a defect for the current binary: `BabyPaywallView` is a native SwiftUI
  paywall and the project does not use RevenueCatUI. It would matter only if
  the app were changed to load a dashboard RevenueCat paywall.
- The repository's `scripts/rc-setup.py` still says the offering has zero
  packages. That comment is stale and should be corrected in a future docs-only
  cleanup, but no external configuration change is needed based on this check.

Independent screenshot pass: the five checked iPhone captures have no obvious
clipping, overlap, or unreadable system text. The first two communicate the
one-screen promise particularly well, with a large headline, a clear last-event
card, and a visible undo confirmation. The black phone outline and restrained
category colors already carry the requested graphic-first tone. The First Weeks
capture makes the AAP copy/range issue highly visible, so it should be recaptured
after any guidance revision. The Summary capture shows the PDF as a small
preview, which is understandable as a concept but could be made more legible if
there is time. None of these screenshot observations is an ASC submission
blocker.

## Read-only verification log

- `python3 scripts/asc-readiness.py`: passed with no reported gaps.
- Direct ASC GETs: version 1.0 is `PREPARE_FOR_SUBMISSION`; review submissions
  count is 0; build 8 is attached; all three products are `READY_TO_SUBMIT`.
- `python3 scripts/asc-submit-for-review.py --dry-run`: confirmed the version
  and build, then made no changes because no submission is open.
- `rc offerings list`, `verify`, and `preview`: current `default` offering has
  three SDK-facing package mappings; no dashboard paywall is attached, which is
  expected for Baby's native paywall.
- Direct ASC `/appInfos/{id}` attribute inspection: no medical, device, or
  regulatory declaration field is exposed. The separate age-rating API's
  `medicalOrTreatmentInformation` field is not the regulated-device question.
- URL HEAD checks: ASC privacy, support, marketing, and GitHub Pages legal URLs
  returned 200.
- `python3 scripts/design-audit.py`: 0 drifted, 2 “worth a look” findings,
  both plain-style watch/widget controls, not Baby's primary iPhone logging
  flow.
- No mutating TestFlight, submit, CloudKit, metadata, code, or external account
  command was run. The only pre-existing untracked repository file was
  `laudit912.md`.
