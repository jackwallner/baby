---
paths:
  - "Baby/Views/**"
  - "Shared/Utilities/AppTheme.swift"
  - "Shared/Utilities/Guidance.swift"
  - "BabyUITests/**"
---

# Graphic direction

Jack's September 12 reference establishes bold outlines, simple graphics,
short labels and physical card edges. Its exact colors are optional. Baby uses
warm paper, peach primary actions and the existing feed/diaper/sleep colors.
Keep all tokens in AppTheme and use the shared card and button modifiers.
Flatten translucent fills on the card color. Apply the offset shadow only to
the opaque background shape, never to the complete view with its text.

2026-09-13: the offset shadow is light-only. In dark it was drawn in a grey
lighter than the page, which reads as a glow or misregistered print, not an
edge. Dark and Night light separate surfaces by tone behind a 1pt `edge`
hairline; `outline` stays brighter for strokes inside care graphics. Night
light is dim warm umber with no pure white and no saturated blue (wet is
slate, sleep is mauve); keep the four kinds distinguishable in it.

CareGraphic provides a small consistent vocabulary beside visible labels.
SharedLogGraphic explains two people contributing to one log. Neither graphic
is a control on its own. No decorative marketing panels belong on Now.

Home uses the available height for its stable controls and supports a wider
two-column composition. Accessibility text sizes stack controls and scroll.
Keep substantial home sections in separate View structs so the view tree
remains manageable. Preserve Reduce Motion and minimum touch targets.

Sharing is "Log together" and is written for the second phone: install,
scan the code, both log. The invite is a read/write link, deliberately not a
contact-only invite, because those fail when the partner's Apple ID differs
from the address they were sent to. Say plainly that anyone with the link can
edit. Joining is reachable without a link in hand (onboarding and More), and
the joined list shows only accepted people. Show retry and cancellation;
never imply someone joined because a sheet closed.

# First Weeks reference

The numeric reference comes from NHS Healthier Together's breastfeeding guide,
linked directly in the screen. It is explicitly scoped to the first two weeks.
Formula and mixed feeding may differ. Do not infer milk intake, health status,
or a missed diaper from incomplete logging. Do not restore per-row assessments.
The AAP fever link supplies the age and rectal measurement context.

The reference supports wet counts 1, 2, 3, 4, 5, 6 and dirty counts 1, 1, 2,
2, 2, 2. Any future change needs a specific primary source and matching tests.
