---
paths:
  - "Baby/App.swift"
  - "Baby/Views/UnfoldedSplit.swift"
  - "BabyTests/UnfoldedSplitTests.swift"
  - "Baby/Views/NowView.swift"
  - "BabyTests/NowFitTests.swift"
  - "BabyTests/DuoTourTests.swift"
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
- Every screen gets `horizontalSizeClass = .compact` always, not only once
  split, so it lays out as on a phone (the app is iPhone only). The capsule and the Undo toast are framed to the primary pane, never
  across the fold. History's pane drops the capsule's bottom reservation.
- Unfolded, the capsule is docked (2026-10-22, the shots review rejected
  Reports, First Weeks and Settings with the capsule over a chart, the day
  table and a footer): `CapsuleDock` clips the open tab's pane at the top
  of the capsule's reservation, so its page ends above the capsule instead
  of scrolling beneath it beside a History pane that has no capsule. The
  last 28 pt above the dock fade to paper (`DockFade`), so a page that runs
  on reads as continuing rather than as a card cut by the capsule.
  Folded (and on every phone) nothing is clipped and the capsule floats.
- Captures: DEBUG `-DuoStop <stop>` (`DuoTour`) opens one surface per
  launch: `log`, `reports`, `firstweeks` (with History's calendar),
  `settings`, `night` (Night light Log) or `history` (folded only). Run
  with `-SeedScreenshotData -NoCloudKit -DemoPro -DuoStop <stop>` through
  `gh-sim launch|all --device 'iPhone Duo' --wait 25`, which shoots the
  launch folded and unfolded; one `gh-sim all` with one `--screen
  "-DuoStop <stop>"` per surface covers them all. Every stop shows its page
  from the top. Until 2026-10-24 Reports, First Weeks and Settings scrolled
  an anchor to the dock so the frame ended on a whole card; that put their
  top cards under the translucent inline header, and the review rejected
  it, so the dock fade replaced it. A wet diaper is logged 10 s in, for the
  recording (`--record-seconds 30`; an `all` run loses its launch
  recordings to the test recorder, so record in `launch` runs). Never use
  `--url` to space shots: an unhandled URL (`noop://`) can fail the run,
  and a custom scheme (tried 2026-10-22) only raises iOS's "Open in" prompt
  over every later frame.
- Now on the Duo's short displays (both the folded outer screen and the
  unfolded Log pane) goes tight (`NowFit.make`, tested in `NowFitTests`):
  when 52 pt buttons leave no room for Add an older entry, section gaps
  drop to 8 and both cards lose 4 pt top and bottom (never at the sides, so
  nothing rewraps and the measured fit cannot oscillate), and buttons go
  down to 44 pt. The care graphic shrinks inside a button shorter than 52,
  otherwise the "44 pt" button still draws 52 and the capsule covers the
  totals (the bug gh-sim run 6 showed). `GeometryReader` already excludes
  the capsule's safe-area reservation; never subtract its insets again.
  `olderLinkHeight` starts at the link's 44 pt minimum: at launch the page
  can measure before the link, and a first fit without it showed the
  buttons growing through the launch fade. Only a change in the page's
  fixed part (side chips) animates a refit.
- The seed logs "today" in the hours before launch, so a capture launched
  before about 1 pm local shows a near-empty Today. The capture script
  passes `--env TZ=America/Sao_Paulo` (an evening zone for a run around
  midnight UTC; `Pacific/Auckland` around 07:00 UTC); pick a zone where
  launch lands in the evening.
- Narrow Log pane (fixed 2026-10-22): 4 of 13 gh-sim runs, cold and warm
  boots alike, laid the leading pane out 84 pt short of the fold with Now's
  inline title leading-aligned (UIKit's regular-width bar), while every full
  width run had it centered. The panes started regular (no split before the
  first geometry) and the Log NavigationStack sometimes kept it after the
  switch to compact. Ignoring the fold-edge safe area did not help (gh-sim
  run 223743). A pane's size class must never change at runtime; with
  `.compact` from launch, gh-sim runs 231043 (Log) and 233930 (First Weeks)
  drew centered titles, a leading back button and full panes.
