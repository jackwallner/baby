"""English storefronts other than en-US, which is hand-written in fastlane/metadata/en-US."""

_SUB = ("Baby+ is available as a monthly or yearly subscription, or as a one-time lifetime purchase that never renews. "
        "New subscribers get a one-week free trial. Payment is charged to your Apple Account when the trial ends unless you cancel at least 24 hours before then. "
        "Subscriptions renew automatically for the same period and price unless cancelled at least 24 hours before the end of the current period. "
        "Manage or cancel in Settings, under your Apple Account, then Subscriptions. Prices are shown in the app before you buy and vary by region.")


def _english(diaper: str, diapers: str, pediatrician: str, colour: str, poo: str = "poo") -> dict:
    return {
        "intro": f"Ultra simple baby tracking. One tap logs a feed, a pee or {poo} {diaper}, or sleep. One glance answers the 3am question: when did the baby last eat, and which side.",
        "buttons": f"FOUR BUTTONS THAT NEVER MOVE\nFeed (left, right, bottle), Pee, Poop, Sleep. Prefer Wet and Dirty? One setting renames them. One tap logs it now. A long press sets the time, the side, the bottle amount or the stool {colour}. Undo sits at the top for a few seconds. No confirmation sheets, ever.",
        "outside": "WITHOUT OPENING THE APP\nLock screen and home screen widgets that log with one tap, an Apple Watch app and complication, a Live Activity while a feed or sleep is running, and Siri.",
        "together": "BOTH PARENTS, NO ACCOUNTS\nYour partner, a grandparent or a nanny scans a code from your phone and joins the same log on their own iPhone. No account to create and no server of ours: the records live on your devices and in your own iCloud.",
        "weeks": f"THE FIRST WEEKS\nYour logged {diapers} by day of life, beside a breastfeeding reference for the first two weeks from NHS Healthier Together, with the \"call your {pediatrician} if\" lines under the table. A reference, not a target.",
        "free": "FREE, AND STAYING FREE\nLogging, the first-weeks table, full history, widgets, the Apple Watch app, the Live Activity, logging together, the stain helper and more than one baby.",
        "plus": f"BABY+, OPTIONAL\nA one-page {pediatrician} summary since the last visit to share or print, trends over the weeks, and CSV export of every entry.",
        "sub": _SUB,
        "disc": f"No ads. No AI. Baby Tracker is a log, not medical advice. It does not diagnose, treat or assess your baby, and it is not a medical device. Call your {pediatrician} with any concern.",
        "terms": "Terms of Use (Apple Standard EULA)",
        "privacy": "Privacy Policy",
    }


_GB = _english("nappy", "nappies", "GP or health visitor", "colour")
_GB["disc"] = _GB["disc"].replace("Call your GP or health visitor with any concern.", "Call your GP, midwife or health visitor with any concern.")
_GB["weeks"] = _GB["weeks"].replace("\"call your GP or health visitor if\"", "\"when to get help\"")
_GB["plus"] = _GB["plus"].replace("A one-page GP or health visitor summary", "A one-page summary for the health visitor or GP")

COPY = {
    "en-GB": {
        "name": "Baby Tracker: Feeds & Nappies",
        "subtitle": "Newborn Log & Nappy Count",
        "keywords": "breastfeeding,nursing,bottle,sleep,wee,poo,wet,dirty,feeding,timer,infant,formula,twins,watch,health visitor,red book,nap,midwife",
        "promo": "The first-week nappy sheet, filled in by your taps. Both parents, one list, through iCloud. No ads, no AI, and the four buttons never move.",
        **_GB,
    },
    "en-AU": {
        "name": "Baby Tracker: Feeds & Nappies",
        "subtitle": "Newborn Log & Nappy Count",
        "keywords": "breastfeeding,nursing,bottle,sleep,wee,poo,wet,dirty,feeding,timer,infant,formula,twins,watch,midwife,GP",
        "promo": "The first-week nappy sheet, filled in by your taps. Both parents, one list, through iCloud. No ads, no AI, and the four buttons never move.",
        **_english("nappy", "nappies", "GP or child health nurse", "colour"),
    },
    "en-CA": {
        "name": "Baby Tracker: Feeds & Diapers",
        "subtitle": "Newborn Log & Diaper Count",
        "keywords": "breastfeeding,nursing,bottle,sleep,pee,poop,wet,dirty,pediatrician,timer,infant,formula,twins,watch,doctor",
        "promo": "The first-week diaper sheet, filled in by your taps. Both parents, one list, through iCloud. No ads, no AI, and the four buttons never move.",
        **_english("diaper", "diapers", "doctor", "colour", poo="poop"),
    },
}
