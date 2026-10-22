---
paths:
  - "Baby/App.swift"
  - "Baby/Views/UnfoldedSplit.swift"
  - "BabyTests/UnfoldedSplitTests.swift"
  - "Baby/Views/NowView.swift"
  - "BabyTests/NowFitTests.swift"
  - "BabyTests/HomeLinkTests.swift"
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
- Unfolded, the capsule is docked (2026-10-22, the shots review rejected
  Reports, First Weeks and Settings with the capsule over a chart, the day
  table and a footer): `CapsuleDock` clips the open tab's pane at the top
  of the capsule's reservation, so its page ends above the capsule instead
  of scrolling beneath it beside a History pane that has no capsule.
  Folded (and on every phone) nothing is clipped and the capsule floats.
- Captures: `babytracker://` is a real scheme. `log`, `history`, `reports`
  and `settings` open that tab in every build (History opens Log while
  split); DEBUG adds `babytracker://tour/<stop>` (`DuoTour`): `wet` logs a
  wet diaper (the recording's tap reaching both panes), `log`, `reports`,
  `firstweeks` (with History's calendar), `settings`, `night` (Night light
  Log) and `history` (folded only). Reports, First Weeks and Settings
  scroll their `tourAnchor` to the bottom of the pane, so each frame ends on
  a whole card. Run with `-SeedScreenshotData -NoCloudKit -DemoPro` through
  `gh-sim all|launch --device 'iPhone Duo'`, one `--url` per stop. Never
  pass unhandled URLs (`noop://`) to space shots; a failed openurl can fail
  the run.
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
  midnight UTC); pick a zone where launch lands in the evening.
- Open (2026-10-21, gh-sim launch-only run on 33cae0e, 1 of 5 runs): every
  leading pane laid out about 84 pt narrower than the split (374 of 457 pt;
  84 is the inner display's trailing status-bar inset, which only History
  should feel), with Now's inline title leading-aligned and First Weeks'
  back button on the right, while the capsule still spanned 457 pt. Same
  fresh relaunch on the inner display as the passing `all` runs; that run
  booted cold and gh-sim logged "simctl io enumerate empty". Reproduce on a
  local Duo before changing code; the likely fix is to stop the primary
  pane inheriting the trailing inset (it ends at the fold, not the edge).
