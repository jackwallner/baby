---
paths:
  - "Baby/App.swift"
  - "Baby/Views/UnfoldedSplit.swift"
  - "BabyTests/UnfoldedSplitTests.swift"
---

# iPhone Duo (2026-10-21)

- Unfolded (regular width, at least 720 pt), `BabyHomeView` puts the open tab
  (Log, Upgrade / Reports or Settings, with the capsule under it) on the
  leading side of the fold and History on the trailing side. The History tab
  button leaves the capsule while split; a History request opens Log. Fold
  edges come from `GeometryProxy.verticalFold()` (iOS 27.1
  `reservedRegions(.division)`), else an even split (`UnfoldedSplit`).
  Portrait unfolded and every compact width keep the single screen.
- The tabs are a `ZStack` of visited screens, shown by opacity, not a
  `TabView`, so History can be either a tab or a pane without being rebuilt.
  Folding only moves frames: scroll, settings path and History layout survive.
  Hidden screens are hit-test and accessibility hidden, as the tabs were.
- Each pane gets `horizontalSizeClass = .compact`, so it lays out as on a
  phone. The capsule and the Undo toast are framed to the primary pane, never
  across the fold. History's pane drops the capsule's bottom reservation.
- Captures: DEBUG `-DuoTour` walks Log, History (folded only), Reports, First
  Weeks with History's calendar, Settings and Night light Log on a timer (it
  logs one wet diaper at 6 s for recordings). Run with `-SeedScreenshotData
  -NoCloudKit -DemoPro` through `gh-sim launch --device 'iPhone Duo'` and
  oversample with `--url noop://N`, which fails fast and only spaces shots.
