# Baby Docs design system

One page, and it is enforced rather than remembered: `python3 scripts/design-audit.py`
fails on anything below that has drifted. A system nobody can check is a system
that lasts about three screens.

The tokens themselves live in `Shared/Utilities/AppTheme.swift`, with the
reasoning attached to each one. This file is the short version, plus the parts
that are not expressible as a constant.

## What the app is trying to look like

Trustworthy, in the three seconds before anybody reads a word. This app tells a
parent that a legal window closes in nine days and asks them to believe it. A
screen that looks assembled undoes the citation, the review date and the .gov
link all at once, because a reader who has decided the app is careless does not
then go and check the source footnote.

So: nothing here is decoration, and everything here is a decision somebody can
find the reason for.

## The rules

**One typeface.** SF Pro, which is to say the system font, which is to say never
naming a font at all. Weight and the built-in text styles carry every bit of
hierarchy this app needs. A bundled typeface would be the app announcing itself
on a screen whose whole job is to look like it belongs on the phone.

**One spacing scale, all multiples of four.** `hairSpacing` 4, `tightSpacing` 8,
`spacing` 12, `looseSpacing` 20. No view is allowed a spacing number of its own;
the audit fails on any literal but `0` (no gap is not a decision) and `44`
(Apple's tap target, and a token would hide whose rule it is). Before this the
views held 2, 3, 5, 6, 10, 14, 22 and 28, which is not eight decisions, it is
one decision nobody made eight times.

**One horizontal margin.** `AppTheme.margin`, 20, because that is what
`.insetGrouped` uses on iPhone and Settings will always be a system list. Any
other number guarantees the app has two left edges.

**One radius, and the curve is continuous.** `AppTheme.cardShape` (14) and
`AppTheme.innerShape` (14 − 12, so a card and the thumbnail inside it are
concentric). Never `RoundedRectangle(cornerRadius:)` on its own: its default is
`.circular`, a quarter circle spliced onto a straight edge with a visible break
where they meet, and every corner Apple draws on this phone is continuous. It
costs one argument and it is the most reliable premium tell on the platform.

**Colour means one thing: how close a door is to closing.** Red inside a week or
past due, orange beyond it, grey for no deadline. Categories are grey glyphs,
because recognition is a job a glyph does better than a hue. Child colours are
identity, not urgency, and they only ever appear on an avatar. Nothing else in
this app is allowed to be coloured, and the reason is not taste: the screen this
replaced had three colour systems in one row, so none of them read as
information.

**Every interactive thing answers back.** `.pressableCard()` rather than
`.buttonStyle(.plain)` on anything card- or row-shaped. Plain is correct for a
button that is really a label; it is wrong for the paywall's plan cards, which
were dead under the finger on the one screen where the money is.

**Four haptics, named after what happened.** `Haptics.completed()` when a task
or a document is ticked, `.selected()` for unticking and for choosing between
options, `.purchased()`, and `.failed()`, which fires from `SaveFailureReporter`
before the alert is drawn. Nothing fires for navigation, scrolling or a screen
appearing. The failure mode of haptics is not too few, it is a phone that buzzes
at everything until the buzz stops meaning anything.

**Tabular numerals on anything being compared or counted.** Prices in the
paywall column, "9 of 15 done", section counts. Proportional digits give two
prices different decimal positions, and a price column that does not line up is
read as carelessness on the screen that can least afford it.

**44pt minimum on every tap target**, explicitly framed where the glyph is
smaller, which is every tick box in the app. The person tapping is holding a
baby.

**Large text is a different layout, not the same layout unreadable.**
`BadgeRow` drops to a column when the badges will not share a line, and
`CentredIfItFits` scrolls when the screen it centred on got smaller. Both exist
because the previous version truncated the product's whole promise to an
ellipsis at an accessibility size.

## Where the effort goes

In funnel order, not evenly: the icon and the screenshots, then the intake and
the paywall, then the first ten seconds of the plan screen, then everything
else. The Settings screen does not need to be beautiful.

## The audit

```
python3 scripts/design-audit.py
```

Run it before a release. It reads the tokens out of `AppTheme.swift` rather than
holding its own copy, so changing the scale changes the check.
