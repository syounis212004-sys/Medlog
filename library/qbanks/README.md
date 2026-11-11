# Question banks online (SharqMed)

The app reads `catalog.json` in this folder and lists every bank in **Question bank > cloud icon**. Tapping Download fetches the file named in `file` (next to the catalog) and imports it exactly like a file chosen by hand.

## What a bank file can be
- a `.zip` with one or more `sharqmed-questions` part files (and optional pictures), the same zip you import by hand;
- a single `.json` in the `sharqmed-questions` format;
- a library book pack zip made of printed questions (`.idx`, `.bin`, optional `-images.imx` / `-images.img`).

The file's own `"id"` must be the same as the catalog entry's `"id"`.

## Catalog entry
```json
{
  "id": "emergency-board-review",
  "title": "Emergency Medicine board review",
  "source": "Where the questions come from",
  "language": "en",
  "count": 766,
  "date": "2026-11-11",
  "license": "CC BY 4.0",
  "desc": "One sentence about what is inside.",
  "file": "emergency-board-review.zip",
  "bytes": 3278082,
  "sha256": ""
}
```
`id` (lowercase letters, digits and single hyphens), `title` and `file` are required. `date` makes the app offer **Update** when you raise it. `bytes` and `sha256` are optional (with a `sha256` the app refuses a file that does not match).

## Upload steps (from a phone or computer, on github.com)
1. Open the repository, go to the folder `library/qbanks`.
2. **Add file > Upload files**, choose the bank file (up to 25 MB per file on the web), write a short message, **Commit changes**.
3. Open `catalog.json`, tap the pencil (**Edit**), paste your entry inside `"banks": [ ... ]` (a comma between entries), **Commit changes**.
4. Wait a few minutes (GitHub caches raw files), then in the app: Question bank > cloud icon.
5. To update a bank: upload the new file with the **same name** (Replace), then raise `date` in its catalog entry.

## Copyright
Only upload questions you wrote, or whose licence lets you share them. Copyrighted books must not be published here; import those by hand from your own files instead.
