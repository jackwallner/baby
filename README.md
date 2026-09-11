# Baby Tracker (working name)

An iPhone and Apple Watch baby tracker for the first months: one tap to log a
feed, a wet or dirty diaper, or sleep, and one glance to answer "when did she
last eat, and which side".

Not built yet. This repository is the Caffeine Tracker chassis, renamed, plus
the market research and fleet context for the build. Start with `CLAUDE.md` and
`marketreport.md`.

## What makes it different

- The first-week tally sheet from the hospital, as the home screen for weeks one
  and two, with typical ranges and "call your pediatrician if" wording.
- Logging without opening the app: lock screen widget, Watch complication,
  Action Button, Live Activity.
- Partner sync through iCloud sharing, no accounts.
- No ads, no AI, and the four buttons never move.
- Capture is free forever. An optional purchase sells reporting: the
  pediatrician PDF, trends, export.

## Build

```sh
xcodegen generate
agent-sim checkout baby
xcodebuild test \
  -project Baby.xcodeproj \
  -scheme Baby \
  -destination 'id=<LEASED_UDID>'
agent-sim checkin baby
```

Never build against a named simulator destination. See `CLAUDE.md` and the
shared `ios-dev` skill for signing and release conventions.

## Targets

| Target | Bundle ID |
| --- | --- |
| Baby | `com.jackwallner.baby` |
| BabyWidget | `com.jackwallner.baby.widget` |
| BabyWatch | `com.jackwallner.baby.watch` |
| BabyWatchWidget | `com.jackwallner.baby.watch.widget` |
| BabyTests | `com.jackwallner.baby.tests` |

App Group: `group.com.jackwallner.baby`

The privacy policy, support page, and terms are in `docs/` and are served by
GitHub Pages.
