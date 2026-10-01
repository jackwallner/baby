---
paths:
  - "BabyWatch/**"
  - "BabyWatchWidget/**"
  - "BabyWatchUITests/**"
  - "Shared/Services/WatchStore.swift"
  - "Shared/Services/WatchSyncService.swift"
  - "Shared/Services/NowSummary.swift"
---

# Watch app and complications

Rebuilt 2026-09-30 (Jack: "make it really good").

Two vertical pages on the crown. **Now**: a two-column glance ("Fed · Left
/ 2h 14m" beside the last diaper), then Left / Right / Bottle, Pee / Poop and
Sleep (Wake shows how long she has slept). It fits a 46mm screen without a
navigation title; smaller watches scroll a little. The side to offer next
(`suggestedSide`: the other breast, or Bottle after a bottle) is filled
stronger and answers the watchOS 11 double tap. A clock button at top left
opens Log earlier: a crown wheel (5 minute steps to an hour, then quarter
hours to six) above the same grid. **Today**: the baby's name as title, the
phone's totals window, counts, the sleep state and the recent entries.
Always-on dims the buttons and keeps the glance lit.

Every tap shows a banner with Undo for 10 seconds (the widgets' window) and a
haptic. Undo is a `WatchLogPayload` of action `.undo` naming `targetID` and
`targetAction`, queued like any tap. `NowSummary.applying` takes it back out
using `recent` (the 24 newest entries the phone now sends), so it works
whether or not the phone has the tap yet and is a no-op once the phone has
deleted it. The phone's `EventStore.apply` deletes the entry, reopens a feed
timer it ended or the sleep a Wake closed, and records the target as applied
so a tap that lands after its Undo is acknowledged and dropped.

`WatchStore` keeps the phone's summary (`AppGroup.Key.phoneSummary`) apart
from the displayed one and always shows `phone.applyingPending(pending)`.

Complications (`BabyWatchWidget`, one bundle): Last feed (kind kept as
`BabyWatchComplication` so placed faces survive), Last diaper, Log pee, Log
poop, Sleep and wake. Timelines carry an entry a minute for three hours, then
every five minutes to twelve. The three action complications set
`widgetURL(babywatch://log/<kind>)`; the app logs on `onOpenURL` with Undo,
and ignores the same kind again inside 3 seconds. There is no Feed action
complication on purpose: a feed needs a side, and Last feed opens the app
with the sides one tap away. `simctl openurl` cannot open custom schemes on
the watch simulator, so the link is unit-tested (`testWatchLinksRoundTripTheirKind`)
and the tap itself needs a device check.

DEBUG: `-WatchDemo` seeds a night three log; `-WatchPage 1` opens Today.
`BabyWatchUITests` (scheme `BabyWatch`, lease `baby-watch --watch`) covers
log, Undo, next side, sleep, Log earlier and Today. `axe` cannot drive the
watch simulator (missing SimulatorKit), so use the UI tests.
