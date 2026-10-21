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

Small (320 px) versions of the lead picture of some articles, taken from **Wikimedia Commons**. Only pictures whose Commons
page shows a free license (CC BY, CC BY-SA, CC0 or public domain) are included, and the author and license of each picture
are stored with it and shown under the picture in the app (tap it to open the file page). Pictures shown over the internet
come from Wikipedia and show a link to their Commons file page.
