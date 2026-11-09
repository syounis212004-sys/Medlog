# Recon map: LogEM: EM Logbook & POCUS (Android; iOS look in screenshots)

Scope: Play Store listing https://play.google.com/store/apps/details?id=com.brightwellmedical.logbook (description plus 8 promo screenshots, reference only in `screens/logem-3..10.png`).
For: Medlog (reference only, not a clone). Date: 2026-11-09

## Evidence level

Listing text and promo screenshots (demo data, marketing renders). App not installed or used. Claims are the developer's own.

## Facts

By Brightwell Medical Limited (UK, a UK emergency medicine trainee). Emergency medicine only, built around the RCEM curriculum (ACCS, Intermediate, Higher), for ARCP and CESR portfolio; says it is independent of RCEM. 10+ installs (very new), updated 5 Nov 2026, no rating found. Data safety: no data shared with third parties. Contact support@logem.co.uk.

Business model: **Standard is free** (unlimited entries). **Pro is an optional subscription** with a 14-day trial on the yearly plan.

## Core loop

Log a procedure or POCUS scan in seconds, see which curriculum targets are signed off, export an ARCP-ready report.

## Screens seen

| ID | screen | what it shows |
| --- | --- | --- |
| S01 | Summary | bottom nav (Summary / Logbook / Progress / Reports / Account + FAB "+"); training post + stage (ST5); 12-month activity heatmap with All / POCUS / Procedure filter and per-week legend; "POCUS targets" rings (Peripheral IV access 5/5 ticked, Central IV 4/5, Fascia iliaca block 8/10, AAA 25/25 ticked, E-FAST 26/25, Echo in life support 10/10, Shock assessment 18/25); link "Tracker" and "All goals" |
| S02 | Procedure picker | search box + curriculum list by stage (Higher specialty training: sedation, airway, NIV, chest drain, thoracotomy, canthotomy, DC cardioversion, pacing, pericardiocentesis, ...) |
| S03 | Progress | POCUS / Procedures toggle, ACCS / Higher (HST) toggle, "8 of 19 signed off" segmented bar, checklist rows (name, "9 logged, Signed off 18 Oct 2026") |
| S04 | Reports | date range, Post filter, document list (Procedure logbook, POCUS logbook, Combined, POCUS ...), Export menu: PDF / Excel / CSV / Choose columns |
| S05 | New POCUS scan (Pro) | role (Primary operator), date, supervisor (optional); "Remove anything identifying": drag a line to cover the top part of the image, "Top 12% removed", Use this crop / Discard |
| S06 | Edit entry (Pro) | notes, "Add ultrasound image or clip", "Send for review: ask a supervisor to review the images", reply card from a consultant with image quality + feedback, Save to logbook / Dismiss |
| S07 | AI dictation (Pro) | speak: "Shoulder reduction ... age 32, primary operator, performed independently, Penthrox, modified Kocher"; entry fields fill with chips (date, role, independence, drug) |
| S08 | Encrypted sync (Pro) | one logbook across devices |

## Flows

```
F01 Quick log        FAB "+" -> pick procedure (search) -> role, date, supervisor, notes -> save
F02 Dictate          FAB "+" -> mic -> speech -> fields prefilled -> confirm        (Pro)
F03 Review a scan    new POCUS scan -> crop identifiers -> send review link -> supervisor reply -> save to logbook   (Pro)
F04 ARCP report      Reports -> range + post -> Export PDF / Excel / CSV (+ columns)
F05 Import           from spreadsheet, CSV, Word or other logbook apps (listing text)
```

## Inferred data model

```
Procedure entry   id, procedure_id (curriculum), date, role, independence level, supervisor?, notes, post   confidence: medium
POCUS scan entry  id, scan_type, date, role, supervisor?, notes, images[] (anonymised), entrustment level, sign-off date   confidence: medium
CurriculumItem    stage (ACCS|Intermediate|Higher), name, target count, signed_off_on   confidence: medium
ReviewRequest     entry_id, link, reviewer, quality, feedback   confidence: guess
```

## Worth taking for Medlog

1. **Curriculum targets with sign-off dates**: the same requirement tracker that DigiLogbook, WardNote and Rotalog also point to (now 4 of 4 apps). Per stage: items, target count, logged count, signed-off date. Top priority.
2. **Import from CSV / spreadsheet / Word** (and other logbook apps): lets users bring years of records. Strong switching feature.
3. **Choose columns on export + Excel format.**
4. **Post (job) filter** on reports.
5. **AI dictation that fills fields** (date, role, independence, drug): fits Medlog's voice input and AI, with identifier stripping already built.
6. **Send a case for review and bring the feedback back** into the entry: fits a share-pack flow without a server (supervisor replies in a file).
7. Freemium idea: core free, extras paid. Owner decision, Medlog has no accounts.

Medlog already does well: image identifier cover (permanent), heatmap, POCUS log, local backup, no data collected.

## Not for Medlog

Encrypted cloud sync and accounts (against the local-first policy), RCEM-specific lists as such (Medlog serves internship; use a curriculum file format so any college's list can be loaded), their branding.

## Next step

Matrix: `features-logem.csv`. Four apps now. Say the word and I build the comparison table and a ranked add list.
