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

CareGraphic provides a small consistent vocabulary beside visible labels.
SharedLogGraphic explains two people contributing to one log. Neither graphic
is a control on its own. No decorative marketing panels belong on Now.

Home uses the available height for its stable controls and supports a wider
two-column composition. Accessibility text sizes stack controls and scroll.
Keep substantial home sections in separate View structs so the view tree
remains manageable. Preserve Reduce Motion and minimum touch targets.

Sharing explains access before opening Apple's invite sheet. Invitations are
private and grant read/write access. Show retry and cancellation. Describe
offline delays honestly; never imply an invitation has been accepted just
because the sharing sheet closed.

# First Weeks reference

The numeric reference comes from NHS Healthier Together's breastfeeding guide,
linked directly in the screen. It is explicitly scoped to the first two weeks.
Formula and mixed feeding may differ. Do not infer milk intake, health status,
or a missed diaper from incomplete logging. Do not restore per-row assessments.
The AAP fever link supplies the age and rectal measurement context.

The reference supports wet counts 1, 2, 3, 4, 5, 6 and dirty counts 1, 1, 2,
2, 2, 2. Any future change needs a specific primary source and matching tests.
