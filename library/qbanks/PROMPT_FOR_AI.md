# Prompt to give an AI (ChatGPT, Gemini) with your bank file

Attach your question file (the .zip or .json that SharqMed reads) and send this:

```
I will upload a question bank file made for the SharqMed app (a .zip with "sharqmed-questions" JSON parts, a single .json, or a book pack). Read it and prepare it for publishing. Do not change, rewrite, translate or re-send the questions themselves.

Do these steps:
1. Open the file. If it is a zip, read every .json part inside; if the parts share one "id", they are one bank.
2. Check that the JSON parses, that every part has "format":"sharqmed-questions", "version":1, the same "id", and a "questions" array; that every question has "id", "text", at least 2 "options", and an "answer" (or "needs_review": true); and that no question id is repeated. List every problem you find with the part name and question id. If there are problems, stop and show them; do not guess fixes.
3. If all is fine, count the questions and the pictures, and write ONE catalog entry as JSON, exactly in this shape and nothing else around it:

{
  "id": "<the bank id from the file, lowercase letters, digits and single hyphens>",
  "title": "<the bank title>",
  "source": "<the source from the file>",
  "language": "<en or ar>",
  "count": <number of questions>,
  "date": "<today, YYYY-MM-DD>",
  "license": "<the licence I tell you; if I did not tell you, ask me before answering>",
  "desc": "<one plain sentence: what is inside, how many questions, which topics>",
  "file": "<the file name I uploaded>",
  "bytes": <size of the uploaded file in bytes, if you can read it, else 0>,
  "sha256": "<sha256 of the uploaded file if you can compute it, else an empty string>"
}

4. Under the entry, write the 3 file names I must upload to GitHub (the bank file, and the edited catalog.json), and remind me that the "id" in the catalog must equal the "id" inside the file.

Rules: never invent a licence, never publish a copyrighted book, never edit the questions.
```

After the AI answers, follow the steps in README.md (upload the file, then paste the entry in catalog.json).
