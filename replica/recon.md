# Recon map: DigiLogbook: Medical Logbook (Android)

Scope: the whole app as far as the public Play listing shows it: case logging, analytics, follow-up, PDF/CSV export, academic portfolio, thesis tracker.
For: Medlog (SharqMed). Not a clone. DigiLogbook is a reference app for features to adopt. More reference apps will follow and be compared in the same matrix.
Date: 2026-11-09

## Evidence level (read this first)

Only public store material was read. Nobody has installed or used the app, so:
- Screens, flows and fields below come from 6 promotional screenshots (demo data, and marketing renders, not raw captures) and the listing text.
- Anything marked `guess` is inferred.
- Feature claims are the developer's own words and have not been verified in the running app.
- Next step for higher confidence: you install it on your own phone, and we go through each screen together.

## Sources

| # | source | URL | notes |
| --- | --- | --- | --- |
| 1 | Play Store listing (description, screenshots, data safety) | https://play.google.com/store/apps/details?id=com.kiran.digilogbook | main source |
| 2 | Developer site | https://digilogbook.pages.dev/ | not read yet |
| 3 | Developer site / policy | https://sites.google.com/view/digi-logbook | not read yet |

Listing facts: developer "kiranraj" (Kerala, India), category Productivity, version 3.1.1, updated 24 Oct 2026, 10K+ installs, rating 4.5 from 54 ratings, Android 10+. Contains ads. Latest change: "Added follow up notes". Data safety: no data shared with third parties; may collect personal info, photos and videos and 2 other types; encrypted in transit; deletion on request. Permissions include network access, run at startup, prevent sleep.

## Core loop

A doctor logs a clinical case or procedure in a few taps, sees progress against a target, and exports a report.

## Screens

| ID | screen | route / how to reach | purpose | key components | states seen |
| --- | --- | --- | --- | --- | --- |
| S01 | Dashboard ("Dash") | bottom tab 1 | month count, total logs, target progress, recent cases | greeting + settings + profile avatar, "This Month" card with sparkline (47), "Total Logs" card (386), target ring (Spinal Anaesthesia 24/30, 80%, est. completion date), Performance Recap buttons (Last Week / Last Month), Recent Activity list | filled |
| S02 | Academic | bottom tab 2 | see S05 | | |
| S03 | Log / Edit Log (3 steps) | centre "+" | enter a case | step header "Step 3 of 3: Outcome & Notes", role chips (Lead / Observer / Supervised / Assistant), Supervisor field, Emergency and USG-guided checkboxes, Duration (min), Outcome, Custom Data block with "+ Add Field", Finish block with follow-up reminder chips (None / 24h / 48h / 3 Days / ...), Previous and Save buttons | filled; steps 1-2 not seen (guess: procedure + patient/diagnosis) |
| S04 | Analysis | bottom tab 4 | trends | busy/free heatmap, Weekly Load bars (Mon-Sun), Demographics donut (Adult 74% / Paediatric 26%, Age / Gender toggle), filter icon | filled |
| S05 | History | bottom tab 5 | all cases | recent-activity style cards: specialty badge (ANE), procedure, Dx, age, sex, time, role | filled (list seen on S01) |
| S06 | Case Details | tap a case | read one case | duration, priority (Elective), supervisor, Clinical Notes, Follow-up notes list (dated, edit/delete each), "Add follow-up note", edit and delete icons | filled |
| S07 | Academic Portfolio | bottom tab 2 | academic life | Annual Goals (CME 28/50, 56%, Edit Targets), Research & Thesis card with progress, All Activities with type chips (All / Seminar / Journal Club / Case Presentation...), activity cards (type, title, date, role, CME hours) | filled |
| S08 | Project (thesis) Dashboard | tap a thesis card | track a research project | specialty tag, "94 days left", title, guide name, progress bar, Milestones & Data: checklist (Protocol approval, Literature review, Analysis and write-up) and data-collection counter (72/120, 60%) | filled |
| S09 | Settings, backup/restore, export (PDF/CSV), templates, search | not shown | guess | | not seen |

## Flows

```
F01 Log a case
    S01 -> "+" -> S03 step 1 -> step 2 -> step 3 -> Save
    happy path clicks: 5+ (guess), reminder chip is optional
    edge: emergency flag, multiple procedures per case ("Procedure 1: Caudal Block" implies several)
F02 Follow up on a case
    S05 -> S06 -> "Add follow-up note" (dated) -> edit/delete
    edge: reminder fires after 24h/48h/3d (guess)
F03 Track a thesis
    S07 -> thesis card -> S08 -> tick milestones, update data count
F04 Track CME
    S07 -> add activity ("+") -> type, date, role, CME hours -> goal bar updates
F05 Export a report
    S09 (guess) -> PDF (layout + institute branding) or CSV
```

## Components

| component | variants | states | used on |
| --- | --- | --- | --- |
| Target ring | percent + "x / y cases" + est. date | in progress | S01 |
| Stat card with sparkline | month / total | filled | S01 |
| Choice chip | role, reminder delay, activity type filter | selected / unselected | S03, S07 |
| Progress bar | annual CME goal, thesis, data collection | in progress | S07, S08 |
| Heatmap | busy to free gradient | filled | S04 |
| Bar chart / donut | weekly load, demographics | filled | S04 |
| Note card | follow-up note with edit/delete | filled | S06 |
| Activity card | type icon, title, date, role, CME hours | filled | S07 |
| Bottom nav | 5 items, centre "+" | selected | all |
| Custom field row | key: value, "+ Add Field" | filled | S03 |

## Inferred data model

```
Log (case)          id, date_time, specialty, dx, patient age, sex, priority (elective|emergency),
                    duration_min, outcome, clinical_notes, supervisor, role, flags (emergency, usg_guided),
                    custom_data (key/value), reminder_at
                    evidence: S01, S03, S06     confidence: medium
Procedure           log_id, name (e.g. Caudal Block, Spinal Anaesthesia), role, attempts (custom)
                    evidence: "Procedure 1: Caudal Block" on S03   confidence: medium
FollowUpNote        id, log_id, timestamp, text
                    evidence: S06   confidence: high
ProcedureTarget     procedure, goal_count, est_completion
                    evidence: S01   confidence: medium
AcademicActivity    id, type (workshop|seminar|journal club|case presentation|conference|publication),
                    title, date, role (participant|presenter), cme_points, attachments
                    evidence: S07, listing text   confidence: medium
AcademicGoal        year, cme_target
                    evidence: S07   confidence: medium
ResearchProject     id, title, specialty, guide, deadline, milestones[], data_target, data_collected
                    evidence: S07, S08   confidence: high
```

Relationships: Log 1-n Procedure, Log 1-n FollowUpNote, ResearchProject 1-n Milestone, AcademicActivity n-n attachments.

## Feature matrix

See `features.csv` (37 rows). Must: 14, should: 12, could: 8, skip: 2. The `clone` column holds Medlog's status from its README (1.6.0 plus later commits). Treat `partial` as "needs checking in the code".

## Out of scope (cannot or should not be adopted)

- Advertising (the listing says the app contains ads).
- Any developer-run account or cloud collection. Medlog stays local-first with no account.
- Their brand, logo, screenshots, colour renders and wording. The screenshots stay in `replica/screens/` as reference only.
- Exact age and patient demographics beyond Medlog's privacy rules (Medlog stores no exact age; use age bands).

## Size

Screens 8 seen + settings unseen, flows 5, entities 7. Hard parts: custom fields per entry, CME and thesis modules (new data model plus screens), institute branding in the PDF engine. Size to adopt the gaps: M.

## Gaps worth adopting first (Medlog lacks these)

1. Academic activities with CME points and an annual CME goal.
2. Thesis / research tracker with milestones and data-collection counter.
3. Custom fields per entry.
4. Per-case follow-up reminders on save (24h / 48h / 3 days).
5. Weekly load chart and target ring with estimated completion date.
6. Institute branding in the PDF.

## Medlog advantages to keep (DigiLogbook does not list them)

Medical library, AI with identifier stripping, calculators, spaced review, reasoning tools, Arabic RTL, encrypted case sharing, no ads, no account.
