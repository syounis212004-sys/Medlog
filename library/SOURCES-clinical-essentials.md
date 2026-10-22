# MedLog offline library, build 3 (2026-10-22/23): clinical-essentials + drug-reference

Packs: clinical-essentials (2,864 articles, bin 7,599,674 B + idx 158,391 B = 7,758,065 B) and drug-reference (694 articles, bin 912,516 B + idx 20,037 B = 932,553 B).
Catalog date and idx meta date are both 2026-10-23 (the shipped catalog already has clinical-essentials at 2026-10-22, so a later date is needed for the app to offer one update). Entries: catalog_entries.json.
sha256: clinical-essentials.bin 673a4d48febb6557460b476ee70e9a6f69f49e9895d504dd0418400f82dda761; .idx daae1aa169398e0a9b009602094471551425b0069ceb31eae9cac01f5e4d8f7c
drug-reference.bin 4cc969335358dc7e691f76bcb29b9e8afd10d7913c6d0edddd6e8481fa0671e4; .idx 92e730600f28d48420233f041a3592faf177d7b5d9ba065e7e6b69beef5f9cfa
Per-article keys: t, u, s, src, lic, au, dt. Titles unique, suffix " — WikEM" etc. Verified by verify3.py (0 duplicate titles, 0 tables over 8 columns, 0 articles under 300 chars, hashes match).

## 1. WikEM - CC BY-SA 4.0
- License: https://wikem.org/wiki/WikEM:Copyrights ("This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License"). Site operators agreed to the reuse (statement by the MedLog owner).
- Rules followed: robots.txt "Disallow: /w/", "Crawl-delay: 5". Only /wiki/<Title> HTML and /wiki/Category: / Special:Categories pages; one request per 5.2 s; User-Agent "MedLog-offline-library (contact: ftreanoure@gmail.com)". No API, no action=raw.
- This build's crawl (wk_crawl4.py): 1,172 requests in two runs (1,129 + 43; ~106 + 4 min), 0 failures, 0 404s, 41.9 MB. Cache now 2,994 pages. Priority: tier 1 core-checklist topic matches and aliases (298, all done), tier 2 scores/calculators/Quick_Ref/Pharmacology/drug-like titles (638, all done), tier 3 remaining clinical categories by weighted priority (partly done), tier 4 other.
- New categories used: Category:Pharmacology (762 pages), Category:Medical_calculators (56), Category:Quick_Ref (17: Broselow weight-band dose pages, critical care quick reference).
- Kept: 2,745 pages = 2,051 clinical (119 of them scores/calculators/decision rules, in clinical-essentials) + 694 drug pages (drug-reference). Dropped 249 stubs (clinical pages under 700 chars or <2 headed sections under 1,200; scores/drugs under 300 chars; list in skipped_wikem.txt). Redirect duplicates merged by canonical URL.
- Sections: all except See Also/External Links/References/Video; simple tables (<=8 columns) kept as tb; author lists in au.
- NOT crawled: 679 pages remain (541 tier 3 clinical, 138 tier 4 misc; list in remaining_uncrawled.json), plus the original exclusions (Kaji/LLSA/ACEP/In-training review pages, EBQ/prefix namespaces, residency-program and site-admin pages).

## 2. Other previous sources (unchanged from out2)
NCI 106 (free of copyright, labeled "adapted from PDQ text", not an official PDQ summary), CDC 265 (public domain, disclaimer section per article), Project Tulip 144 (CC BY 4.0), Wikipedia essentials 251 (CC BY-SA 4.0). Full license quotes: ../out2/SOURCES.md sections 2, 3, 5, 6.

## 3. New: condensed Wikipedia fill (47 articles) - CC BY-SA 4.0
For core topics still missing after the WikEM crawl: condensed from the local Kiwix ZIM (/tmp/lib_build/med_nopic.zim) with the same condenser as before (clinical sections; drug-class topics use medical uses / adverse effects / interactions / mechanism sections; general topics use capped lead plus main sections). Each has src, lic, URL and authors-history link. Not found or too thin: trauma laparotomy, postoperative complications, cytochrome P450. (Wikipedia pages are the only other source used; no non-open source.)

## 4. Open RN - SKIPPED (retried 2026-10-22)
https://wtcs.pressbooks.pub/ returns 403 (CloudFront "Request blocked") through the proxy; https://openrn.wisconsin.edu/ fails to connect. Proxy not bypassed; nothing taken.

## Core-topic coverage (250 core topics; title match with source suffix removed; strict = exact or word-bounded containment; +syn adds a documented synonym list)
- Before (out2 pack): 180 strict / 188 with synonyms; WikEM-titled 132.
- After (out3 pack): 223 strict / 233 with synonyms; WikEM-titled 178. (Whole 581-topic checklist: 376 -> 437 strict, 384 -> 447 with synonyms.)
- Of the 17 core topics not matched by the title rule, 12 are covered under another title (ARDS = Acute respiratory distress syndrome, variceal bleeding = Esophageal varices, primary hyperaldosteronism = Primary aldosteronism, nephrolithiasis = Kidney stone disease, spontaneous abortion = Miscarriage, cesarean = Caesarean section, perforated viscus = Gastrointestinal perforation, Sjogren, giddiness = Dizziness, health screening = Screening (medicine), preoperative assessment = Preoperative care, developmental milestones = Child development stages) and 2 (aspirin, ACE inhibitor) are in drug-reference. Truly uncovered: trauma laparotomy, postoperative complications, cytochrome P450.
