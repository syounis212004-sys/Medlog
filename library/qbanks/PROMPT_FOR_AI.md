# Prompt to give an AI (ChatGPT, Gemini) with your bank file

Attach your question file (the .zip or .json that SharqMed reads, or a book pack zip of printed questions) and send this:

```
I will upload a question bank file for the SharqMed app. It is ONE of these two kinds:
  A) a question file: a .zip or .json whose JSON parts have "format":"sharqmed-questions";
  B) a BOOK PACK of printed questions: a .zip that contains NAME.idx, NAME.bin, NAME.local.json and optionally NAME-images.imx / NAME-images.img. The .local.json is only the pack's manifest ({"version":1,"packs":[{...}]}); this is normal and valid, the app converts the pack into questions by itself. Do NOT ask for "format", "id" or "questions" in a book pack.
Prepare it for publishing. Do not change, rewrite, translate or re-send the questions themselves.

Steps:
1. Open the file and say which kind it is (A or B).
2. Kind A: check that the JSON parses; every part has "format":"sharqmed-questions", "version":1, the same "id" and a "questions" array; every question has "id", "text", at least 2 "options", and an "answer" (or "needs_review": true); no question id is repeated. List each problem with part name and question id. If there are problems, stop and show them; do not guess fixes.
   Kind B: read NAME.local.json: its packs[0] gives "id", "title", "source", "count", "license", "desc". Check that NAME.idx and NAME.bin are in the zip. If the images pair is there, say how many figures ("count" of the -images manifest). The bank "id" is the pack "id".
3. Write ONE catalog entry as JSON, exactly in this shape and nothing else around it:

{
  "id": "<kind A: the id in the file; kind B: the pack id; lowercase letters, digits and single hyphens>",
  "title": "<title>",
  "source": "<source>",
  "language": "<en or ar>",
  "count": <number of questions (kind B: the manifest count)>,
  "date": "<today, YYYY-MM-DD>",
  "license": "<the licence I tell you; kind B: copy the licence/copyright text printed in the manifest>",
  "desc": "<one plain sentence: what is inside, how many questions, which topics>",
  "file": "<the file name I uploaded>",
  "bytes": <size of the uploaded file in bytes, if you can read it, else 0>,
  "sha256": "<sha256 of the uploaded file if you can compute it, else an empty string>"
}

4. COPYRIGHT: if the licence or the file carries an "all rights reserved" / copyright notice of a publisher, still write the entry, but put this warning ABOVE it in bold: "Copyrighted: do not upload this file to a public repository." Never refuse to prepare the entry for that reason, and never invent a licence.
5. Under the entry, say which 2 files I upload to GitHub (the bank file, and the edited catalog.json) and that the "id" in the catalog must equal the "id" of the bank (kind B: the pack id).

Never edit the questions.
```


After the AI answers, follow the steps in README.md (upload the file, then paste the entry in catalog.json).
