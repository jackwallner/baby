# Pre-submit review, 2026-11-07 (1.4.3 build 81)

Scope: app sources changed since the live version, 1.4.2. Base is `afa02f0`
(the last commit at `MARKETING_VERSION` 1.4.2, build 77), head is `216741c`
(origin/main, 1.4.3 build 81). Docs, fastlane, qa and tests excluded.

Changed app files: `Baby/App.swift`, `Baby/Info.plist`,
`Baby/Views/FirstWeeksView.swift`, `Baby/Views/RemindersView.swift`,
`Baby/Views/SettingsView.swift`, `Shared/Localizable.xcstrings`,
`Shared/Services/EventStore.swift`, `Shared/Services/NowSummary.swift`,
`Shared/Services/Reminders.swift`, `project.yml`.

No purchase, paywall, RevenueCat, onboarding or Core Data model code changed
in this range.

## Findings

| Severity | Location | What happens | Status |
|---|---|---|---|
| P2 | `Baby/Views/SettingsView.swift:319` | The new Language row uses `HStack(spacing: 6)`. `python3 scripts/design-audit.py` reports it as drift and exits 1, and AGENTS.md asks for a passing audit before a release. No runtime effect. | Not fixed: changing the spacing is a design call. Swap in an existing token (`hairSpacing` 4 or `tightSpacing` 8) or add a 6pt token, then rerun the audit. |
| P2 | `Baby/Views/SettingsView.swift:311` | The Language row opens `openSettingsURLString`. The simulator lands on Settings' root, so the per-app Language page (which needs `UIPrefersShowingLanguageSettings`, present in `Baby/Info.plist`) has not been proven by automation. | Not fixed: needs a real-iPhone check, per `.claude/rules/localization.md`. |
| P2 | `Shared/Services/Reminders.swift:91` | Cleanup now removes only the IDs in `ownedIDs` instead of every pending request with the feed or checkup prefix. Correct today (the IDs have not changed since 1.4), but a future reminder ID that is not added to this list would never be cleared. | Not fixed: no defect in this build. |

## Checked and clean

- `NowSummary.counted` (Last 24 hours aging): optional and `Codable`, so
  summaries saved by 1.4.2 and summaries from an older Watch decode. The
  `break` to `continue` change in `make` only skips the append, since the
  switch is the last statement in the loop. Counts and `counted` move together
  in `make`, `applying` and `undoing`, and `agingOut` clamps at zero. Widgets
  (`BabyWidget.swift:51`), Watch Today and complications all read through
  `current(now:)`, so the aging reaches every surface.
- `Reminders.reschedule`: stale removal is now synchronous, so a late
  pending-list callback can no longer delete a newer plan's feed reminder.
  Removal and add use disjoint ID sets. Checkup IDs match `ownedIDs`
  (`checkupPrefix + "entered"`, `day4/14/30`). Past dates are filtered before
  the calendar trigger is built, so a `UNCalendarNotificationTrigger` never
  points at a time that will not come.
- `EventStore.returnToForeground`: `refresh` is synchronous, so the explicit
  reschedule uses the fresh summary; `lastPlanned` dedups it against the one
  `publish()` may already have made. Skipped while the store is a stand-in,
  as in `publish()`. Main actor throughout (the widget's reschedule path is
  `@MainActor` too).
- `RemindersSection` rereads notification permission on the new
  `Reminders.foregrounded` post.
- New strings (`Language`, `Opens iOS Settings`) are translated in all four
  catalog languages; `Tools/Localization/check.py` reports 0 problems.
- No placeholder or debug UI, hard-coded prices, other-platform links or
  health claims added.

## Tests

No code changed in this review, so there was nothing new to test. `gh-sim test --scheme Baby --only BabyTests` (run `baby@20261107-230013-ddb9-claude-mbpro8b2d-1107-230737-30940`, GitHub Actions 42457497997) sat queued on GitHub for 85 minutes without starting and was cancelled at the 90 minute limit. The unit tests were not run. `Tools/Localization/check.py` passed. `scripts/design-audit.py` failed on the finding above.
