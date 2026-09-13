# Baby Tracker

An iPhone and Apple Watch baby tracker for the first months: one tap to log a
feed, a wet or dirty diaper, or sleep, and one glance to answer "when did she
last eat, and which side".

Native SwiftUI apps for iPhone and Apple Watch, with widgets, Live Activities,
and iCloud sharing. Start with `CLAUDE.md` for project conventions and
`.claude/rules/release-verification.md` for verified release evidence.

## What makes it different

- One stable home screen for the last feed, quick logging, and today's totals.
- First Weeks in More, with a clearly scoped breastfeeding diaper reference,
  source links, and guidance to contact a pediatrician when concerned.
- Logging without opening the app: lock screen widget, Watch complication,
  Action Button, Live Activity.
- Partner sync through iCloud sharing, without a separate Baby account.
- No ads, no AI, and the four buttons never move.
- Capture is free forever. An optional purchase sells reporting: the
  pediatrician PDF, trends, export, and additional baby profiles.

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
