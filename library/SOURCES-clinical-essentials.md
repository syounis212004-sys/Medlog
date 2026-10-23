# MedLog offline library, build 4 (2026-10-23): clinical-essentials, drug-reference + 5 new CDC packs

Catalog date and idx meta date are both 2026-10-24 in every pack. The shipped clinical-essentials is dated 2026-10-23 and the sandbox clock is also 2026-10-23, so the date is one day ahead to be strictly later (the app then offers one update). To use the true date, change DATE in build_pack4.py and rebuild (hashes change). Entries: catalog_entries.json. Verified by verify4.py (unique titles, 0 tables over 8 columns, 0 articles under 300 chars, per-article keys only t,u,s,src,lic,au,dt, hashes and sizes match).

| pack | articles | bin B | idx B | pack total B | sha256 bin | sha256 idx |
|---|---|---|---|---|---|---|
| clinical-essentials | 3,402 | 8,431,762 | 183,660 | 8,615,422 | 06f076c0541da3cb0ffb7b30d5dabf5012068cd10155797e94e7396b55a10109 | 30011e059e61aabfbdec78ada36eb02f21a7f22c650fb2799c4b7e18df751d2d |
| drug-reference | 694 | 912,516 | 20,037 | 932,553 | 4cc969335358dc7e691f76bcb29b9e8afd10d7913c6d0edddd6e8481fa0671e4 | 7278bd62d7c6ea2fca56a40998265b405eda055f123aa874a42ab4969f151f56 |
| cdc-infection-control | 204 | 996,744 | 11,661 | 1,008,405 | 34150a32d7bc0ec301e37d807c817770c240d2a551a9761de6c25b50db1b8bcf | 77764c6f91c5832852db57e6b1523c15ad7d9c0118d712db95c1aa0eaef2d65d |
| cdc-vaccines | 128 | 360,596 | 8,056 | 368,652 | a48b6edcf5181eae1209dd32298fb41e41704f53077a44aa6dad9f27c093711f | b8673b77bcd6c4c60bb3fafa7a1a1e9dcbfdea5604903bc0bef628c9e84b456d |
| cdc-infectious-disease | 127 | 320,085 | 8,973 | 329,058 | dfd09c29af45ba8e54a517c37d2437b010bf49a405f852cd1f32b7b05e96e4ba | 2fbeb01483985c9ebafbff3516869c0699f4a95388533ad782138b828e6de664 |
| cdc-clinical-guidance | 127 | 393,646 | 8,831 | 402,477 | 0bdfc5f80721c83d2617faf68f630b42d0a2ec74c9fc938d40ba7cbed1809f2e | c39891c9ced41bc2a1f8eee948e7957ef3790a37929c5dd8e53e2b87571b31a2 |
| cdc-yellow-book | 96 | 846,870 | 8,434 | 855,304 | d9f99b17ac20b42fb717f776e2c8112dbfe16faecda3f9446bcc4355a06eb07d | a84a532c8ae9cd8097f78f74a4ad97a06bb3719a1b41f8954d04b9471313368c |

clinical-essentials by source: WikEM 2,573 (120 scores/calculators), CDC 265, Project Tulip 144, Wikipedia 314 (251 earlier essentials + 63 condensed fill), NCI 106. Note: 134 Project Tulip articles share chapter-page URLs (several articles per Tulip chapter page); this is unchanged from earlier builds.

## 1. WikEM - CC BY-SA 4.0 (2,573 clinical + 694 drug pages)
- License: https://wikem.org/wiki/WikEM:Copyrights ("This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License"). Reuse agreed by the site operators (statement by the MedLog owner). Per article: src, lic, u, au, dt.
- robots.txt re-read at crawl start (out4/robots_checked.txt): "Disallow: /w/", "Disallow: /wiki/Special:", "Crawl-delay: 5". Only /wiki/<Title> HTML; one request per 5.2 s; User-Agent "MedLog-offline-library (contact: ftreanoure@gmail.com)". No API, no action=raw.
- This crawl (wk_crawl5.py): 603 requests, 602 pages stored (+2 hand-fetched later), 0 failures, 0 404s, 20.9 MB, 55.8 min wall clock. Queue = all 541 tier-3 clinical pages + 61 tier-4 pages. Cache now 3,598 pages.
- Not fetched (75, remaining_uncrawled.json): residency-program/hospital pages, documentation templates, site-admin/partnership pages, LLSA review pages, Choosing Wisely/trial pages and similar non-clinical pages. 0 clinical-category pages remain. (Two pages wrongly caught by the filter, Phosphate and CIWA-B, were fetched afterwards.)
- Kept 3,267 = 2,573 clinical + 694 drug pages; 331 skipped as stubs/namespace/duplicates (skipped_wikem.txt; same rules as build 3: clinical under 700 chars or <2 headed sections under 1,200; scores/drugs under 300).

## 2. Previous sources (unchanged)
NCI 106 (free of copyright, "adapted from PDQ text"), CDC 265 (public domain, disclaimer per article), Project Tulip 144 (CC BY 4.0), Wikipedia essentials 251 (CC BY-SA 4.0). Licence quotes: ../out2/SOURCES.md sections 2, 3, 5, 6.

## 3. Wikipedia condensed fill, 63 articles (CC BY-SA 4.0), from /tmp/lib_build/med_nopic.zim
46 core topics still without a title match after the WikEM crawl were filled (ARDS, variceal bleeding, airway management, hip fracture, CBC, ethics, etc.; log in wp_extra_log.json) plus the three known gaps. No single Wikipedia article called "Cytochrome P450", "Postoperative complications" or "Trauma laparotomy" exists in either local ZIM (nopic or maxi), so the closest real articles were condensed instead: Laparotomy, Exploratory laparotomy, Damage control surgery; CYP3A4, CYP2D6, CYP2C9, CYP2C19, CYP1A2, Drug metabolism, Enzyme inhibitor, Drug interaction; Postoperative fever, Wound dehiscence, Postoperative nausea and vomiting, Postoperative cognitive dysfunction, Incisional hernia, Atelectasis, Seroma, Adhesion, Ileus, Complication (medicine). Too thin and not added: Enzyme inducer, Postoperative care.

## 4. Open RN - still blocked, stopped
Retried 2026-10-23: https://wtcs.pressbooks.pub/, /nursingskills/ and /nursingpharmacology/export/ return 403 "ERROR: The request could not be satisfied" (CloudFront) through the proxy; https://openrn.wisconsin.edu/ fails with "CONNECT tunnel failed, response 502". Proxy not bypassed; nothing taken.

## 5. New CDC packs - public domain
- Licence page (read 2026-10-23): https://www.cdc.gov/other/agencymaterials.html. Quote: "Most of the information on the CDC and ATSDR websites is not subject to copyright, is in the public domain, and may be freely used or reproduced without obtaining copyright permission. There are, however, a few exceptions." Required: attribution to CDC, and a non-endorsement disclaimer; both are added as a "Source and disclaimer" section to every article. Pages with ©, "copyright", "used/reprinted with permission", photo credits are dropped (12 pages, e.g. smallpox vaccine-reaction images, Yellow Book heat/cold and high-altitude chapters).
- robots.txt of www.cdc.gov: no Crawl-delay for generic agents, "Disallow: /travel/" and others not touched. Fetch rate 1 page per ~3-4 s. Source URL lists: topic sitemaps (cdc_hcp_urls.txt, cdc_more_sitemaps.json) and https://www.cdc.gov/yellow-book/wcms-auto-sitemap.xml. Only /hcp/ (health-care-provider) pages; Spanish pages, training/CE, toolkits, communication-resource, promo pages excluded (294 skipped, skipped_cdc_new.txt).
- Crawl stats: cdc_crawl5.py 631 ok / 11 404s (mpox lab pages) / 36.9 MB / 34 min; cdc_crawl6.py 249 ok / 16.9 MB / 12 min; yb_crawl.py 123 ok / 10.0 MB. URLs already in clinical-essentials CDC are not repeated.
- Packs: cdc-infection-control 204 (isolation precautions, core practices, HAI, stewardship, sepsis, C. auris/C. diff), cdc-vaccines 128, cdc-infectious-disease 127, cdc-clinical-guidance 127 (US MEC/SPR contraception, overdose/opioid, heat, radiation emergencies, STEADI, TBI, diabetes, tobacco, etc.), cdc-yellow-book 96 (CDC Yellow Book 2026 chapters).
- Yellow Book note: the book's disclaimer page says "All Centers for Disease Control and Prevention (CDC) material in this publication is in the public domain and may be used and reprinted without special permission; citation of source is appreciated." It also says "Contributing authors external to CDC are identified by the editorial staff as experts in their fields" (content cleared by CDC). Chapters are published on cdc.gov under the CDC notice; no per-chapter copyright statements except the 2 excluded chapters. This is the one judgment call; drop cdc-yellow-book if you want to be stricter. The Oxford University Press print edition is a separate product and is not used.

## 6. Checked and skipped (licence text read, 2026-10-23)
- WHO fact sheets: NOT taken. https://www.who.int/about/policies/terms-of-use: "© Copyright World Health Organization (WHO), 2021. All Rights Reserved ... Extracts of the information in the web site may be reviewed, reproduced or translated for research or private study but not for sale or for use in conjunction with commercial purposes ... Reproduction or translation of substantial portions of the web site, or any use other than for educational or other non-commercial purposes, require explicit, prior authorization in writing." The CC BY-NC-SA 3.0 IGO licence (https://www.who.int/about/policies/publishing/copyright) is stated for "publications published by WHO", and the fact-sheet pages themselves only carry "© 2026 WHO" with no CC statement, so it is unclear that it covers web fact sheets and bulk reuse needs written permission.
- NICE: not open for reuse (per instruction), not fetched.
- USPSTF: copyright notice (https://www.uspreventiveservicestaskforce.org/uspstf/recommendation-topics/copyright-notice) permits reuse "provided that it is reproduced without any changes to the work", plus adaptation disclaimers and no endorsement; condensing would be a change. Unclear, skipped.
- AHRQ (ahrq.gov): 403 from the proxy; not read, not taken.
- NHLBI: policy pages returned 404/ no licence text found; skipped. NIDDK ("majority of information ... copyright free"), NIMH ("in the public domain") and NIAID ("most text ... is in the public domain") are open, but patient-level; MedlinePlus is already a separate pack, so not duplicated. NINDS robots.txt 403.
- StatPearls (CC BY-NC-ND) not used (no derivatives). VA/DoD guideline PDFs not pursued.

## Core-topic coverage (250 core / 581 all; title match, strict = exact or word-bounded containment; +syn adds the documented synonym list in coverage.py)
| build | core strict | core +syn | core WikEM-titled | all strict | all +syn |
|---|---|---|---|---|---|
| shipped out2 (2,386 art.) | 180 | 189 | 133 | 376 | 385 |
| out3 (2,864) | 223 | 234 | 179 | 437 | 448 |
| out4 clinical-essentials (3,402) | 223 | 236 | 180 | 437 | 450 |
| out4 essentials + drug-reference | 225 | 239 | 183 | 459 | 473 |
(Out3 numbers here are recomputed with the extended synonym list, so "+syn" is 1-2 higher than reported in build 3.) The WikEM crawl mostly added articles beyond the checklist; the core gain from the 541 pages was small because build 3 had already crawled tier-1 core matches and the Wikipedia fill covered the rest.
Core topics with no title or synonym match in essentials+drug-reference (11): ARDS, variceal bleeding, nephrolithiasis, giddiness, perforated viscus, preoperative assessment, Sjogren, developmental milestones, spontaneous abortion, cesarean section, health screening. All 11 ARE covered under another title (Acute respiratory distress syndrome, Esophageal varices, Kidney stone disease, Dizziness, Gastrointestinal perforation, Preoperative care, Sjögren's disease, Child development stages, Miscarriage, Caesarean section, Screening (medicine)), so nothing is truly absent. Three known gaps: trauma laparotomy and postoperative complications are now covered by synonym through the closest articles (see section 3); cytochrome P450 only through CYP isoform articles and Drug metabolism (no P450 overview article in any open source reachable).
