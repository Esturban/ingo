# ingo

Minimal shell runtime for Spanish legal PDFs into Upstash Vector, with both ingestion and query in one CLI.

## Project Scope

- `ingo` is the canonical runtime.
- `rag-redis` is deprecated and can be removed.
- For query-only devices, set `INGO_ROLE="query"` so ingest/OCR commands are blocked.
- For ingest workers, use `INGO_ROLE="all"` and run fetch/ocr/chunk/embed.
- Both roles must share the same `UPSTASH_VECTOR_REST_URL`, `UPSTASH_VECTOR_REST_TOKEN`, and `INGO_NAMESPACE`.

Ingestion stages:
1. fetch PDF to inbox
2. OCR with `tesseract -l spa`
3. chunk by legal boundaries
4. embed/index via Upstash REST
5. cleanup intermediates

## Requirements

- bash
- curl
- jq
- awk
- tesseract (with `spa` language data)
- poppler (`pdftotext`, `pdftoppm`)

## Setup

```bash
cp .env.example .env
```

Set required values in `.env`:
- `UPSTASH_VECTOR_REST_URL`
- `UPSTASH_VECTOR_REST_TOKEN`

## Usage

```bash
bin/ingo doctor
bin/ingo fetch --dir data/ingest
bin/ingo ocr --dir data/ingest
bin/ingo chunk --strict
bin/ingo embed
bin/ingo cleanup
```

Single command:

```bash
bin/ingo run --dir data/ingest --strict
```

Download + ingest in one shot:

```bash
bin/ingo run --url "https://example.com/doc.pdf" --strict
```

Query from same CLI:

```bash
bin/ingo query "¿Qué exige la licencia ambiental para vertimientos?" --top-k 8
```

Manual drop flow:

1. Copy PDFs into `~/ingest` (or `INGO_INBOX`)
2. Run:

```bash
bin/ingo run --dir data/ingest --strict
```

## Notes

- Upstash ingestion uses `POST /upsert` with `{id,data,metadata,namespace}` where `data` is the chunk text.
- For minimal disk usage, set `INGO_CLEANUP_TEXT=1` (default) so OCR/chunk files are deleted after embed.
- Relevance gate defaults to strict mode and rejects low-signal text into `data/rejected/` before embedding.
- Tune relevance using `INGO_RELEVANCE_TERMS` and `INGO_MIN_TERM_MATCHES`.
- For this device, set `INGO_ROLE="query"` to disable all ingest commands and keep only query behavior.
