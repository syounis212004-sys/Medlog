# Clinical Essentials: sources, licenses, what was taken

Pack id: clinical-essentials (files clinical-essentials.idx / .bin, catalog_entry.json). Built 2026-10-22.
All terms below were read on the live sites on 2026-10-22 from this sandbox. Text only; images omitted.
Article titles carry a source suffix (— WikEM, — Wikipedia, — CDC, — NCI, — Project Tulip). Each article carries keys src, lic, u (original URL), au, dt.

## 1. WikEM (698 articles) - CC BY-SA 4.0
- License page: https://wikem.org/wiki/WikEM:Copyrights
- Quote: "This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License"
- Crawl rules: https://wikem.org/robots.txt says "Disallow: /w/" (this covers index.php and api.php) and "Crawl-delay: 5". So action=raw and the API were NOT used. Only public /wiki/<Title> HTML pages and /wiki/Category: pages were fetched, one request per ~5.2 s, User-Agent "MedLog-offline-library (contact: ftreanoure@gmail.com)".
- Taken: 800 pages fetched, round-robin across clinical categories (Cardiology, Critical Care, ID, Toxicology, Trauma, etc.; pharmacology drug stubs excluded). 698 kept; 102 stubs/lab-value/drug-class pages dropped. Sections: all clinical sections except See Also / External Links / References / Video. Simple tables kept as "tb". Author lists from each page's Authors box go in "au". Not all of WikEM (about 3,200 topic pages) was crawled because of the 5 s crawl delay; this is a prioritized subset.
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

## 4. Open RN - SKIPPED (not reachable)
Hosts wtcs.pressbooks.pub and other Pressbooks hosts (opentextbc.ca, open.oregonstate.education) return a CloudFront "403 Request blocked" from this sandbox's proxy, and openrn.wisconsin.edu returns proxy 502 (CONNECT denied). The license text could not be read, so nothing was taken. Re-run from an unrestricted network.

## 5. Project Tulip (144 articles) - CC BY 4.0
- URLs: https://projecttulip.org/about-us/ ("Everything produced by Project Tulip is published under an open license ... you are free to add, alter, republish and create anything you want") and the footer of each chapter page: "Attribution Creative Commons Attribution 4.0 International License on original content by Project Tulip, unless where otherwise noted" linking http://creativecommons.org/licenses/by/4.0/.
- Parts of chapters contain adapted OpenStax (CC BY 4.0) and StatPearls (CC BY 4.0) text, and some images are third-party; images omitted and caption/credit lines containing permission notices removed. Attribution "Project Tulip Open Internal Medicine authors".
- Taken: Part 2 (Diseases) of Esophagus-Stomach, Kidney, Liver/Biliary/Pancreas, Respiratory, and Part 3 (approach to the patient) symptom chapters of Cardiovascular/Endocrine/Hematology/GI/Renal/Respiratory/Musculoskeletal (the Musculoskeletal and some Part 3 pages were fetched via the listed sitemap). Infectious-diseases (OpenStax microbiology) chapters were not used. robots.txt only disallows /wp-admin/. Sub-license nuance: "unless where otherwise noted", so redistribution carries CC BY 4.0 with attribution.

## 6. Wikipedia essentials (330 articles) - CC BY-SA 4.0
- Source: existing local Kiwix medicine ZIM (/tmp/lib_build/med_nopic.zim). Condensed to Overview, Clinical features, Causes and risk factors, Diagnosis, Treatment, Complications, Prognosis, Prevention (capped lengths). Epidemiology/history/society omitted.
- 494 candidate high-yield conditions; 164 dropped because WikEM/CDC/NCI/Tulip already cover them (list in wp_dropped.txt); thin ones skipped.
- Each article has src Wikipedia, lic CC BY-SA 4.0, URL, and an authors link to the article history page.
- MedlinePlus: not added; it is already a separate pack (medlineplus) and is patient-level.
