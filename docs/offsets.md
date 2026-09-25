# REUSE_CHECKED: none -- no prior offsets/citation doc existed under docs/
# before DEV-6550.

# Chunk offsets and citations (DEV-6550)

Every chunk `lib/chunk.sh` produces now carries enough metadata to answer
"where exactly does this text live in the source PDF" -- not just "which
file". This is what lets `ingo query` (and `sig norma`, which calls it)
return a citation that a reader can actually go verify.

## Fields on every chunk

| Field | Meaning |
| --- | --- |
| `page` | 1-indexed PDF page number, exactly as `pdftotext -layout` sees it (matches `pdfinfo`'s page count). A chunk never spans two pages: a page boundary always forces a new chunk. |
| `paragraph` | 1-indexed position of this chunk's paragraph within its page (a simple counter, not a legal citation unit by itself -- use `article`/`paragraph_marker`/`numeral_marker` for that). |
| `line_start` / `line_end` | 1-indexed line numbers **within that page**, counting every physical line `pdftotext -layout` produced (including blank separator lines that fall inside the range, though a chunk's own line_start/line_end always land on real content lines, never on a blank). |
| `section` | Most recent `TITULO`/`CAPITULO`/`SECCION` heading seen before this chunk (carried forward). |
| `article` | Most recent `ARTICULO N` heading seen before this chunk. An article heading always starts a new chunk, so one chunk's `article` value is never a guess spanning two different articles. |
| `paragraph_marker` | Most recent `PARAGRAFO` heading within the current article, if any. |
| `numeral_marker` | Most recent enumerated numeral (`1.`, `2.`, `a)`, ...) within the current article/paragraph, if any. |
| `start` / `end` | Legacy flat character offsets within the OCR/extracted `.txt` file (kept for the existing dedupe/id scheme; not page-relative). |
| `text` | The chunk's own text, verbatim (only whitespace-collapsed and JSON-escaped -- never paraphrased). This **is** the "cita textual" the citation rule asks for. |

## What "line N" actually means

`pdftotext -layout` tries to preserve the visual line layout of the PDF, but
it is still text extraction, not a scan of pixel coordinates. For the large
majority of typewritten legal PDFs (the ANLA/IGAC/MADS/CAR corpus this
profile targets) the line numbers line up with what a person counts from the
top of the page. Two known limits:

- Multi-column layouts or heavily justified text can shift line breaks by
  one relative to what a PDF viewer's own line-wrap shows.
- A page with zero extractable text (a scanned image with no OCR text layer,
  or a pure-image figure) produces no chunks at all for that page -- there
  is nothing to cite. `ingo doctor` does not currently flag these; check
  `pdftotext -layout page.pdf - | less` on a source you don't trust.

Because of this, **the verbatim `text` field is the authoritative locator,
not the line numbers.** `sig norma` (and any other consumer) should always
show the quoted text, not just "pagina 4, lineas 10-11" on its own -- a
reader confirms the citation by finding that exact quote, not by counting
lines by hand.

## Why a chunk never crosses a structural boundary

Early versions of this chunker let `INGO_CHUNK_OVERLAP` retain a trailing
slice of one paragraph into the next chunk (character-count based). On
short, blank-line-heavy legal text (numbered lists, `PARAGRAFO` blocks,
`CAPITULO` headers each on their own line) that overlap could chain across
several structural markers before the size or overlap budget reset, so one
chunk's reported `article`/`numeral_marker` could describe text that
actually belonged to a different article. Fixed by treating every
`TITULO`/`CAPITULO`/`SECCION`/`ARTICULO`/`PARAGRAFO`/numeral heading as a
hard chunk boundary (no overlap carried across it), and by tracking the
physical line number of every retained line explicitly (never inferred by
subtracting a line count from the last line seen, which silently assumes no
blank lines were skipped in between -- false as soon as overlap has already
crossed one).

Verified against 5,966 real chunks from 5 public Colombian regulatory PDFs
(Ley 99 de 1993, Decreto 3930 de 2010, Decreto 2041 de 2014, Resolucion ANLA
763 de 2017, Resolucion IGAC 643 de 2018): every chunk's `(page, line_start,
line_end)` opens to text containing that chunk's own verbatim `text`.
