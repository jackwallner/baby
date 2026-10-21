# Play Console answers: Data safety and related forms

Answered from the code on 2026-10-21 (Log together on Firebase). Recheck
against the app before submitting; every answer must match
`docs/privacy-policy.html`.

## Data collection and security

- Does the app collect or share any required user data types? **Yes**
  (only when the person turns on Log together, plus purchases).
- Is all user data encrypted in transit? **Yes** (HTTPS to Firebase and
  RevenueCat; release builds forbid cleartext).
- Do you provide a way for users to request that their data is deleted?
  **Yes**: in the app (Settings > Invite someone or leave > Leave shared
  log, which deletes the Firebase Auth user) and by web request.
- Delete account URL: `https://jackwallner.github.io/baby/delete-account.html`
  (Play requires one because Log together creates a sign-in).

## Data types (collected; none shared with third parties for their own use)

| Data type | Collected | Why | Optional | Notes |
|---|---|---|---|---|
| Personal info > Name | Yes | App functionality, Account management | Optional (Log together only) | First name from the Google account, shown to the other members. |
| Personal info > Email address | Yes | Account management | Optional | Held by Firebase Authentication with the Google sign-in. Never shown in the app. |
| Personal info > User IDs | Yes | App functionality, Account management | Optional | Firebase user id; RevenueCat anonymous app user id for purchases (required for buying). |
| Health and fitness > Health info | Yes | App functionality | Optional | The baby's feeds, diapers, stool colour, sleep, weights and notes, stored in Firestore for the shared log. Conservative choice: these are care records about a child. |
| Personal info > Other info | Yes | App functionality | Optional | Baby name and birth date in the shared log. |
| Financial info > Purchase history | Yes | App functionality | Required for purchases | Google Play and RevenueCat, entitlement status only. |

- Processed ephemerally? **No** for the shared log (stored until the last
  member leaves).
- Not collected: location, contacts, photos, audio, files, calendar, messages,
  web history, device ids for ads, crash logs or analytics (no Analytics or
  Crashlytics SDK).
- Shared (transferred to a third party for their own purposes): **none**.
  Firebase and RevenueCat act as service providers.

## Other App content forms

- Ads: **No ads.**
- App access: **All functionality available without special access.** Log
  together needs any Google account; reviewers can use their own. If Play asks
  for credentials, answer that sign-in is optional and uses Google sign-in.
- Health apps declaration: baby care log; not a medical device; no diagnosis.
- Target audience: 18 and over (parents and caregivers). Not designed for
  children.
- Content rating questionnaire: reference app, user-generated content shared
  only with invited people (no public sharing, no chat).
- Account creation: the app creates a Firebase sign-in only through Log
  together, and deletes it on Leave shared log.
