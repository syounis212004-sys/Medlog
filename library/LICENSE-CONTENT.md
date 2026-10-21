# MedLog library content

The offline library packs in this folder are **text-only** conversions (no images, no tables) of:

* **Wikipedia** medical articles (WikiProject Medicine selection, from the Kiwix `wikipedia_en_medicine_nopic_2026-10` file).
  Licensed **CC BY-SA 4.0**: https://creativecommons.org/licenses/by-sa/4.0/ .
  Every article keeps its source URL (the page history there lists the authors). Changes made: removal of images, tables,
  references and navigation boxes; text split into sections. Packs built from Wikipedia are shared under the same license.
* **MedlinePlus Health Topics** (National Library of Medicine, USA): US government work, public domain. Copyrighted
  MedlinePlus material (A.D.A.M. encyclopedia, ASHP drug monographs, some images) is not included.

The scripts that built the packs are in `build/`. The content is for learning and may be out of date; it does not replace
hospital protocols or clinical judgement.

Format: `<id>.idx` (gzip JSON index) and `<id>.bin` (one gzip member per article). `catalog.json` lists the packs with SHA-256 checksums.

## Pictures (optional image packs `*-images.*`)

Small (max 360 px) versions of the pictures used in the course articles, taken from **Wikimedia Commons**. A picture is included
only if its file page exists on Commons (Commons hosts free-licensed or public-domain files only); local English-Wikipedia
uploads (which can be non-free) and files marked for deletion or as copyright violations are left out. The author and license
shown with each picture are read from its Commons file page when they could be recognised; otherwise the credit is just
"Wikimedia Commons" and the app links to the file page (tap the picture, then the link icon). Pictures shown over the internet
come from Wikipedia and link to their Commons file page.
