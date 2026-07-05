# PE OB/GYN manuscript

Source and build files for the mystery-caller manuscript targeting *Obstetrics & Gynecology*.

## Source of truth

Edit **`manuscript_cite.md`** (pandoc markdown). Everything else is generated from it.
Do not hand-edit the output `.docx`; re-render instead.

## Files

| File | Role |
|------|------|
| `manuscript_cite.md` | The manuscript source (prose, tables, `[@citekey]` citations). Edit this. |
| `references.bib` | Bibliography. Every entry verified against a primary source. |
| `ama.csl` | American Medical Association citation style (auto-numbered references). |
| `pandoc-reference.docx` | Style template: 12-point Times New Roman throughout. |
| `Manuscript_PE_OBGYN_GreenJournal_<date>_<time>.docx` | Rendered output (timestamped). |
| `COMIRB_Protocol_PE_OBGYN_2026-07-05.docx` | IRB protocol. |

## Render

Run from this directory:

```sh
pandoc manuscript_cite.md \
  --citeproc \
  --bibliography=references.bib \
  --csl=ama.csl \
  --reference-doc=pandoc-reference.docx \
  -o "Manuscript_PE_OBGYN_GreenJournal_$(date +%Y-%m-%d_%H-%M).docx"
```

This produces 12-point Times New Roman, an auto-numbered AMA reference list, and
dash-free prose in one pass.

## Conventions

- **No en dashes or em dashes in the prose.** Reword with commas, colons, or
  parentheses, or use a hyphen. Dashes are fine in the reference list and in
  citation number ranges (e.g., page ranges, `3-5`).
- **All values in square brackets `[ ]` are dummy placeholders** to be replaced
  with real results after the REDCap calling campaign.
- To add a reference: add the entry to `references.bib`, cite it in the text as
  `[@citekey]`, and re-render. The AMA style renumbers automatically.
