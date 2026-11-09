# Recon map: WardNote (web + Android + iOS)

Scope: what the public landing page says. For: Medlog (reference only, not a clone).
Date: 2026-11-09

## Evidence level

Thin. Only the public landing page https://www.wardnote.com/ was read (rendered like a normal visitor, one page). The app itself is behind `/login` and `/signup`, which I did not use, and no app-store listing was found by search. So there are no real screens, flows or data model here, only the marketing claims. Everything below is the developer's own words, unverified.

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | landing page | https://www.wardnote.com/ | read; screenshot in `screens/wardnote-home.png` (reference only) |
| 2 | how-to-use tutorial video | same page, section "How to use" | exists, not watched |
| 3 | app stores | not found | web search returned nothing |

Facts: made in Hyderabad, India; for medical students; web plus Android and iOS ("watch this tutorial to use WardNote on Android and iOS"); account required (log in / sign up); "Free trial until 5th March" implies paid plans after the trial (pricing not shown); privacy policy, terms and support links are empty placeholders ("#"). Contact: wardnote.com@gmail.com, @Ward_Note on X.

## Core loop

A student logs a case on the ward from a specialty template in seconds, then checks which body systems they have covered and exports a PDF.

## Claimed features

- Specialty-specific templates ("log cases 3x faster"), tuned per rotation.
- Rotations listed: Internal Medicine, General Surgery, Pediatrics, OB/GYN, Psychiatry, Family Medicine, Emergency Medicine, Neurology, Anesthesiology, Radiology.
- Real-time sync across devices (start on mobile, finish on desktop). Needs an account and a server.
- Progress by body system with coverage bars (example: Cardiovascular 85%, Respiratory 60%, GI 45%, Neurological 30%), to show "what's missing".
- Cases organised by rotation, specialty and date, with search and filter.
- Export one case, or a full PDF of all cases with images and documentation.

## Screens, flows, data model

Not observable from the landing page. Inferred only: Case (rotation, specialty, date, template fields, images) and a system-coverage tally. Confidence: guess.

## Feature matrix

See `features-wardnote.csv`.

## What is worth taking

1. **Coverage by body system with a "what's missing" view.** Strongest idea here, and it fits Medlog's learning angle. It can use the case-to-library link Medlog already has.
2. **Template wording per rotation** is already in Medlog; compare the rotation list for gaps (Psychiatry, Neurology, Radiology, Family Medicine).

## What not to take

Account plus cloud sync (against Medlog's local-first privacy policy), paywall, and their branding and copy.

## Next step to improve this

Open the app yourself (the free trial is a real way in) and send screenshots of the case form and the progress screen, or the tutorial video link. I will not create an account on your behalf.
