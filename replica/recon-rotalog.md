# Recon map: Rotalog (web app + phone)

Scope: what the public landing page https://rotalog.app/ says. For: Medlog (reference only, not a clone).
Date: 2026-11-09

## Evidence level

Landing page only, rendered like a normal visitor (one page, screenshot in `screens/rotalog-home.png`, reference only). The app (https://app.rotalog.app/) was not opened, and the FAQ answers were collapsed and not read. No screens, flows or data model are observed. All below is the developer's own claim, unverified.

## Facts

Product of Virtual Tutors Limited (Kenya, 2021). Web app that works on any phone or computer, nothing to install. Sold to institutions (book a demo, onboarding the first institutions now), so it is a B2B product with three roles: trainee, supervisor, coordinator. Audience: medicine, nursing and midwifery, clinical medicine, radiography, physiotherapy, pharmacy, lab science. Contact: mohamed@rotalog.app.

## Core loop

A trainee logs cases, procedures and attendance, a supervisor signs them on the ward with a one-time code, and the finished logbook is printed with a QR code anyone can verify.

## Claimed features

- Trainee logging: case presentations matched to required conditions, procedures with level of involvement, weekly attendance (one tap a day), teaching/CME sessions, reflections. Shows what the rotation still needs.
- **Signing codes:** supervisor taps the trainee's name and shows a 6-digit code (single use, expires in 5 minutes); trainee types it and entries are signed. Remote alternative: send a signing request to the supervisor's queue. Supervisors can review a trainee's week in one go. Each signature records name, time and a unique reference.
- Attach pictures and slides to case presentations and CME sessions (shrunk on the phone, reminder to crop out names).
- **Verifiable print / PDF:** whole logbook, each signed entry lists supervisor, time, reference; a QR code lets a board or employer check it is genuine.
- Coordinator dashboard: every trainee's progress, overdue signatures, attest late entries, onboard a department from a spreadsheet.
- Requirements per department built from the programme curriculum.
- **RotaLearn:** a daily case with 10 questions at noon, answers and leaderboard next day, points and streaks, hospital and national leaderboards, supervisors can share cases.
- Community posts (learning points, ECGs) inside a hospital, direct messages, discussion on a logbook entry.
- Privacy: patient identifiers off by default, posts with names or IP/OP numbers refused, data visible only inside the institution.

## Feature matrix

See `features-rotalog.csv`.

## Worth taking for Medlog (fits a personal, local-first app)

1. **Requirement tracker per rotation:** list what a rotation requires (conditions, procedures, counts) and show what is still missing. Same idea as WardNote's coverage and DigiLogbook's target ring, so three apps now point to it. Highest priority so far.
2. **Weekly attendance in one tap per day.**
3. **Level of involvement per procedure** (observed / assisted / performed / supervised).
4. **Signature with a code**, adapted offline: the supervisor confirms on the trainee's phone, or the case is shared as a `.medlogpack` the supervisor signs. Needs design; a QR-verified PDF would need a signing key rather than a server.
5. **Daily case challenge** is close to Medlog's quiz and "topic of the day"; a streak counter is cheap to add.

## Not for Medlog

Institution accounts, coordinator dashboards, servers, national leaderboards, community feed and messaging (all need accounts and a backend, against the local-first privacy policy), and their branding and copy.

## Next step

To see real screens, open https://app.rotalog.app/ yourself and send screenshots, or tell me if you want to link a browser (their demo is a free 30-minute call).
