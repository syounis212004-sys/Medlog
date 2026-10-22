# Clinical Essentials: sources, licenses, what was taken

Pack id: clinical-essentials (files clinical-essentials.idx / .bin, catalog_entry.json). Built 2026-10-22 (rebuild 2: expanded WikEM crawl; 2,386 articles).
All terms below were read on the live sites on 2026-10-22 from this sandbox. Text only; images omitted.
Article titles carry a source suffix (— WikEM, — Wikipedia, — CDC, — NCI, — Project Tulip). Each article carries keys src, lic, u (original URL), au, dt.

## 1. WikEM (1,620 articles) - CC BY-SA 4.0
- License page: https://wikem.org/wiki/WikEM:Copyrights
- Quote: "This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License"
- Crawl rules: https://wikem.org/robots.txt says "Disallow: /w/" (covers index.php and api.php) and "Crawl-delay: 5". action=raw and the API were NOT used. Only public /wiki/<Title> HTML pages and /wiki/Category: pages were fetched, one request per ~5.2 s, User-Agent "MedLog-offline-library (contact: ftreanoure@gmail.com)". The site operators agreed to the reuse (statement by the MedLog owner).
- Taken: 1,834 pages cached in total (800 in rebuild 1, 1,034 more in a 95-minute continuation crawl, 0 failed requests). 1,620 kept; 214 stubs/lab-value/drug-class/index pages dropped (rule: under 700 chars, or fewer than 2 headed sections and under 1,200 chars). Sections: all clinical sections except See Also / External Links / References / Video. Simple tables (up to 8 columns) kept as "tb". Author lists from each page's Authors box go in "au".
- Continuation priority: categories not yet covered first (Cardiology, Neurology, Orthopedics, Toxicology, GI, Pediatrics, Trauma, Critical Care, Pulmonary, Renal, Heme/Onc, OBGYN, ...), proportional to category size, with ID last; pages whose titles look like individual drugs, drug classes, antibiotics or lab values were not fetched unless the title also has a disease/syndrome/approach keyword (287 of the 3,157 category-listed pages skipped this way, plus Kaji/LLSA/ACEP/In-training review pages).
- NOT crawled: 1,323 of the 3,157 listed pages remain (1,036 in the prioritized queue, mostly ID 166, Orthopedics 136, Toxicology 120, GI 111, Cardiology 107, Neurology 96, Dermatology 48, Critical Care 48; the rest 287 are skipped drug/lab-like titles). About 3,200 topic pages exist on WikEM in total.
- Attribution: CC BY-SA 4.0 with link to the page and author list per article; text condensed/reformatted (changes: images, links, templates removed).

## 2. NCI cancer information (PDQ text) (106 articles) - free of copyright
- URL: https://www.cancer.gov/policies/copyright-reuse
- Quote: "Unless otherwise indicated, all text within National Cancer Institute (NCI) products is free of copyright and may be reused without our permission. Credit the National Cancer Institute as the source."
- Constraint in each summary's "Permission to Use": content "cannot be identified as an NCI PDQ cancer information summary unless it is presented in its entirety and is regularly updated." Therefore articles are labeled "National Cancer Institute (adapted from PDQ text)", titled "— NCI", do not use the PDQ name/logo as a product label, and end with a Source section saying it is not an official PDQ summary.
- Taken: health-professional adult treatment (about 75), screening (15) and selected supportive-care (about 16) summaries. Dropped: clinical trial listings, references, "Latest Updates"/"About" blocks, over-long subsections truncated (about 2.6k chars each), AJCC staging tables (credited as reprinted with permission from AJCC/Springer, i.e. third-party copyright) and all images. Graphics/images not used.

## 3. CDC (265 articles) - public domain
- URL: https://www.cdc.gov/other/agencymaterials.html
- Quote: "Most of the information on the CDC and ATSDR websites is not subject to copyright, is in the public domain, and may be freely used or reproduced without obtaining copyright permission. There are, however, a few exceptions."
- Conditions followed: attribution to CDC; non-endorsement disclaimer; no change of substantive content; statement that material is available free on the agency site (all added in a "Source and disclaimer" section to every CDC article).
- Taken: HCP clinical pages (clinical overview/signs/diagnosis/treatment/vaccine recommendation pages) for about 60 infectious-disease topics, the STI Treatment Guidelines pages, and immunization schedule / best-practice pages. Pages containing third-party markers (©, "reprinted/used with permission", photo credits) were skipped: Lyme carditis, infant botulism, tularemia signs, vaccine altered-immunocompetence. Stubs and redirect pages skipped.

## 4. Open RN - SKIPPED (still not reachable, retried 2026-10-22)
- https://wtcs.pressbooks.pub/ and /nursingskills/ and /nursingskills/open/download?type=html|epub: CloudFront-style "403 ERROR / Request blocked" from this sandbox's proxy. https://openrn.wisconsin.edu/ (and /openrn-nursing-skills/): proxy 502 "CONNECT tunnel failed". The proxy was not bypassed.
- archive.org: advanced search for Open RN / Nursing Skills / Wisconsin technical college titles returned no copy; web.archive.org connection was reset (and archive.org rate-limited with 429), so no archived copy could be read.
- The Open RN license text could not be read, so nothing was taken. Re-run from an unrestricted network.

## 4b. OpenStax - SKIPPED (license mismatch)
- openstax.org is reachable (robots.txt: Disallow /apps/archive etc., /books/ pages are not disallowed for general agents). The nursing title checked, "Clinical Nursing Skills", states: "This book uses the Creative Commons Attribution-NonCommercial-ShareAlike License, which means that you can reuse and modify the material only for noncommercial purposes ... This book may not be used in the training of large language models or otherwise be ingested into large language models or generative AI offerings without OpenStax's prior written permission." That is CC BY-NC-SA with an AI-use restriction, not CC BY 4.0, so nothing was taken. OpenStax Microbiology content already reaches the pack only via the Project Tulip chapters. No other OpenStax book was extracted (none gives concise clinical sections quickly).

## 5. Project Tulip (144 articles) - CC BY 4.0
- URLs: https://projecttulip.org/about-us/ ("Everything produced by Project Tulip is published under an open license ... you are free to add, alter, republish and create anything you want") and the footer of each chapter page: "Attribution Creative Commons Attribution 4.0 International License on original content by Project Tulip, unless where otherwise noted" linking http://creativecommons.org/licenses/by/4.0/.
- Parts of chapters contain adapted OpenStax (CC BY 4.0) and StatPearls (CC BY 4.0) text, and some images are third-party; images omitted and caption/credit lines containing permission notices removed. Attribution "Project Tulip Open Internal Medicine authors".
- Taken: Part 2 (Diseases) of Esophagus-Stomach, Kidney, Liver/Biliary/Pancreas, Respiratory, and Part 3 (approach to the patient) symptom chapters of Cardiovascular/Endocrine/Hematology/GI/Renal/Respiratory/Musculoskeletal (the Musculoskeletal and some Part 3 pages were fetched via the listed sitemap). Infectious-diseases (OpenStax microbiology) chapters were not used. robots.txt only disallows /wp-admin/. Sub-license nuance: "unless where otherwise noted", so redistribution carries CC BY 4.0 with attribution.

## 6. Wikipedia essentials (251 articles) - CC BY-SA 4.0
- Source: existing local Kiwix medicine ZIM (/tmp/lib_build/med_nopic.zim). Condensed to Overview, Clinical features, Causes and risk factors, Diagnosis, Treatment, Complications, Prognosis, Prevention (capped lengths). Epidemiology/history/society omitted.
- 494 candidate high-yield conditions; 243 dropped because the larger WikEM set, CDC, NCI or Tulip already cover them (list in wp_dropped.txt); thin ones skipped.
- Each article has src Wikipedia, lic CC BY-SA 4.0, URL, and an authors link to the article history page.
- MedlinePlus: not added; it is already a separate pack (medlineplus) and is patient-level.

## Totals (rebuild 2)
WikEM 1,620 + CDC 265 + Project Tulip 144 + Wikipedia 251 + NCI 106 = 2,386 articles; titles unique; 0 tables over 8 columns; every article has src, lic, u. Files: clinical-essentials.bin 6,611,469 bytes, clinical-essentials.idx 130,236 bytes (pack total 6,741,705 bytes).
