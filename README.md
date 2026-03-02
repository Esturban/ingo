# ingo

Minimal shell runtime to ingest Spanish legal PDFs into Upstash Vector and query them from the same CLI.

## What This Repo Does

`ingo` runs an end-to-end ingest pipeline (fetch -> OCR -> chunk -> embed -> cleanup) and exposes a query command over the same Upstash Vector namespace. It supports two deployment roles: `INGO_ROLE=all` for ingest/query workers and `INGO_ROLE=query` for query-only devices where ingest commands are blocked.

## Features

- Single CLI for ingest and retrieval (`bin/ingo`).
- Ingest stages: `fetch`, `ocr`, `chunk`, `embed`, `cleanup`, plus `run` orchestration.
- Query endpoint integration via `query` with validated `--top-k`.
- Relevance gate (`strict` mode by default) to reject low-signal OCR output.
- HTTP wrapper with timeout and retry/backoff controls.
- Marker-based embed skip (`.jsonl.embedded`) to avoid re-upserting unchanged chunks.

## Requirements

Runtime dependencies checked by `bin/ingo doctor`:

- `bash`
- `curl`
- `jq`
- `awk`
- `grep`
- `tesseract` (with `INGO_LANG` data installed, default: `spa`)
- `pdftotext`
- `pdftoppm`

Notes:

- Query-only role (`INGO_ROLE=query`) requires only query dependencies (`curl`, `jq`) and Upstash credentials.
- Ingest role (`INGO_ROLE=all`) requires the full OCR + text processing stack above.

## Quick Start (5 Minutes)

1. Copy env template:

```bash
cp .env.example .env
```

2. Set required values in `.env`:

- `UPSTASH_VECTOR_REST_URL`
- `UPSTASH_VECTOR_REST_TOKEN`

3. Verify setup:

```bash
bin/ingo doctor
```

4. Run one ingest pass:

```bash
bin/ingo run --dir data/ingest --strict
```

5. Run one query:

```bash
bin/ingo query "¿Qué exige la licencia ambiental para vertimientos?" --top-k 8
```

## Command Reference

| Command | Purpose | Key Flags | Role Restriction |
| --- | --- | --- | --- |
| `bin/ingo doctor` | Validate dependencies and required env vars | none | Available in all roles (checks OCR stack only when role is not `query`) |
| `bin/ingo fetch` | Discover PDFs in inbox, download one URL, or run document-only seed crawl into corpus artifacts | `--url URL`, `--seeds FILE`, `--crawl-depth N`, `--allow-hosts FILE`, `--manifest FILE`, `--progress-every N`, `--snapshot-pages`, `--verbose`, `--dir DIR` | Blocked when `INGO_ROLE=query` |
| `bin/ingo ocr` | OCR PDFs into `data/raw/*.txt` | `--dir DIR` | Blocked when `INGO_ROLE=query` |
| `bin/ingo chunk` | Convert OCR text to chunk JSONL | `--strict`, `--no-strict` | Blocked when `INGO_ROLE=query` |
| `bin/ingo embed` | Upsert chunks into Upstash Vector | `--force` | Blocked when `INGO_ROLE=query` |
| `bin/ingo cleanup` | Remove local intermediates based on cleanup policy | `--markers` | Blocked when `INGO_ROLE=query` |
| `bin/ingo run` | Run fetch -> ocr -> chunk -> embed -> cleanup pipeline | `--url URL`, `--dir DIR`, `--strict`, `--no-strict`, `--force` | Blocked when `INGO_ROLE=query` |
| `bin/ingo query "<question>"` | Query indexed content in configured namespace | `--top-k N` (positive integer only) | Available in all roles |

Common flows:

Local folder ingest:

```bash
bin/ingo run --dir data/ingest --strict
```

URL one-shot ingest:

```bash
bin/ingo run --url "https://example.com/doc.pdf" --strict
```

Seed-crawl discovery (corpus mode via `fetch`):

```bash
bin/ingo fetch \
  --seeds data/corpus/seeds/seed_url.txt \
  --crawl-depth 2 \
  --allow-hosts data/corpus/config/allowlist.txt \
  --manifest data/corpus/manifests/gdb_documents.ndjson \
  --progress-every 10
```

Optional fallback to export eligible pages as PDF when no document links are found on a page:

```bash
bin/ingo fetch \
  --seeds data/corpus/seeds/seed_url.txt \
  --crawl-depth 2 \
  --allow-hosts data/corpus/config/allowlist.txt \
  --manifest data/corpus/manifests/gdb_documents.ndjson \
  --snapshot-pages
```

Manual curation before indexing:

```bash
# review downloaded corpus files
find data/corpus/downloads -type f | sort
# remove files you do not want indexed
rm -f "data/corpus/downloads/unwanted-file.pdf"
```

Index curated corpus using existing pipeline:

```bash
bin/ingo chunk --no-strict
bin/ingo embed
```

Inspect crawl ledgers:

```bash
jq -r '.status' data/corpus/manifests/gdb_documents.ndjson | sort | uniq -c
jq -r '.reason' data/corpus/manifests/gdb_skipped.ndjson | sort | uniq -c
jq -r '.error' data/corpus/manifests/gdb_errors.ndjson | sort | uniq -c
```

Query-only device:

```bash
INGO_ROLE="query" bin/ingo doctor
INGO_ROLE="query" bin/ingo query "resume obligaciones de vertimientos" --top-k 5
```

## Configuration

Use `.env.example` as a starter, then adjust based on runtime defaults below.

| Variable | Required | Default (`lib/env.sh`) | Description |
| --- | --- | --- | --- |
| `UPSTASH_VECTOR_REST_URL` | Yes | none | Base URL for Upstash Vector REST API. |
| `UPSTASH_VECTOR_REST_TOKEN` | Yes | none | Bearer token for Upstash Vector REST API. |
| `INGO_INBOX` | No | `$HOME/ingest` | Source directory for PDFs. |
| `INGO_RAW_DIR` | No | `data/raw` | OCR output directory (relative to repo root). |
| `INGO_CHUNK_DIR` | No | `data/chunks` | Chunk JSONL output directory (relative to repo root). |
| `INGO_NAMESPACE` | No | `legal-co` | Namespace used for upsert and query. |
| `INGO_LANG` | No | `spa` | OCR language passed to Tesseract; must be installed. |
| `INGO_CHUNK_SIZE` | No | `1400` | Target chunk size (characters). |
| `INGO_CHUNK_OVERLAP` | No | `180` | Character overlap between consecutive chunks. |
| `INGO_CLEANUP_TEXT` | No | `1` | When `1`, cleanup deletes OCR/chunk intermediates. |
| `INGO_ROLE` | No | `all` | `all` enables ingest+query; `query` blocks ingest commands. |
| `INGO_RELEVANCE_MODE` | No | `strict` | Relevance gate mode for chunking (`strict` or effectively off). |
| `INGO_MIN_TERM_MATCHES` | No | `2` | Minimum term matches for strict relevance gate. |
| `INGO_REJECTED_DIR` | No | `data/rejected` | Directory for rejected raw text files. |
| `INGO_RELEVANCE_TERMS` | No | `ambiental,licencia,vertimiento,emision,resolucion,decreto,articulo,autoridad,ministerio,agua,suelo,aire` | Comma-separated relevance terms. |
| `INGO_CORPUS_DIR` | No | `data/corpus` | Base directory for crawl state, downloaded documents, extracted text, and manifests. |
| `INGO_CRAWL_DEPTH` | No | `2` | Maximum crawl depth used by `fetch --seeds`. |
| `INGO_ALLOWED_HOSTS_FILE` | No | `data/corpus/config/allow_hosts.txt` | Host allowlist path used by `fetch --seeds` in addition to `.gov.co` domains. |
| `INGO_INCLUDE_EXTENSIONS` | No | `pdf,docx,xlsx,xlsm` | Comma-separated allowlist for document-only crawl downloads. |
| `INGO_EXCLUDE_EXTENSIONS` | No | `zip,png,jpg,jpeg,gif,webp,svg,ico,js,css,map,woff,woff2,ttf,eot,mp3,mp4,mov,avi` | Comma-separated denylist for crawl filtering. |
| `INGO_PROGRESS_EVERY` | No | `25` | Print crawl progress every N processed URLs. |
| `INGO_SNAPSHOT_PAGES_TO_PDF` | No | `0` | When `1`, attempt `wkhtmltopdf` page snapshots for eligible pages with no discovered document links. |

Spreadsheet handling:

- `.xlsx` and `.xlsm` are downloaded and converted to text for chunking/embedding.
- Extraction priority is `xlsx2csv` -> `in2csv` -> Python `openpyxl` fallback.
- If none are available, spreadsheet extraction is marked `unsupported` and the original files are still preserved.
| `INGO_HTTP_CONNECT_TIMEOUT` | No | `5` | HTTP connect timeout (seconds). |
| `INGO_HTTP_READ_TIMEOUT` | No | `30` | HTTP max request time (seconds). |
| `INGO_HTTP_RETRY_ATTEMPTS` | No | `2` | Number of retry attempts for retriable failures. |
| `INGO_HTTP_RETRY_BACKOFF_MIN` | No | `1` | Initial retry backoff (seconds). |
| `INGO_HTTP_RETRY_BACKOFF_MAX` | No | `8` | Maximum retry backoff (seconds). |
| `INGO_HTTP_RETRY_BACKOFF_FACTOR` | No | `2` | Backoff multiplier between retries. |
| `INGO_HTTP_RETRY_AFTER_MAX` | No | `INGO_HTTP_RETRY_BACKOFF_MAX` | Maximum accepted `Retry-After` sleep (seconds). |

Legacy compatibility:

- `INGO_HTTP_RETRY_MAX` is still accepted and mapped to `INGO_HTTP_RETRY_ATTEMPTS`.
- `INGO_HTTP_RETRY_BACKOFF` is still accepted and mapped to `INGO_HTTP_RETRY_BACKOFF_MIN`.
- Runtime exports both legacy names for compatibility with older scripts/tests.

## Data Layout

```text
data/
  ingest/             # optional local inbox if you set INGO_INBOX=data/ingest
  raw/                # OCR text + source metadata (*.txt, *.meta)
  chunks/             # chunk files (*.jsonl) and embed markers (*.jsonl.embedded)
  rejected/           # OCR text rejected by relevance gate or empty-content check
```

Default inbox is `$HOME/ingest` unless overridden by `INGO_INBOX` or command `--dir`.

## Operational Notes

- Relevance behavior:
  - `chunk --strict` (or default `INGO_RELEVANCE_MODE=strict`) rejects low-signal text into `INGO_REJECTED_DIR`.
  - `chunk --no-strict` disables relevance filtering for that run.
- Marker behavior:
  - `embed` skips files when chunk hash + namespace match existing `.jsonl.embedded` marker.
  - `embed --force` bypasses marker skip and re-upserts.
- Query output shape:
  - JSON object with `match_count` and `matches[]`.
  - Each match includes normalized fields such as `id`, `score`, `text`, `source`, `section`, `article`, `page`, `date_indexed`.

## Testing

Run all test scripts:

```bash
for f in tests/*_test.sh; do bash "$f"; done
```

Key coverage areas:

- `query_top_k_validation_test.sh`: validates `--top-k` acceptance/rejection rules.
- `doctor_lang_check_test.sh`: validates exact OCR language detection behavior.
- `http_wrapper_test.sh`: validates timeout/retry/backoff + wrapper integration in fetch/embed/query.
- `embed_marker_rerun_test.sh`: validates marker skip/re-embed/force behavior.
- `path_key_collision_test.sh`: validates collision-safe artifact keys and meta lookup fidelity.

## Troubleshooting

- `missing env var: UPSTASH_VECTOR_REST_URL` or `UPSTASH_VECTOR_REST_TOKEN`:
  - Define both in `.env` or shell environment.
- `missing OCR language data for INGO_LANG=spa`:
  - Install Tesseract language data for `INGO_LANG` and verify with `tesseract --list-langs`.
- `invalid --top-k: must be a positive integer`:
  - Use an integer greater than zero (for example `--top-k 8`).
- `ingest commands are disabled on this device (INGO_ROLE=query)`:
  - Expected in query-only mode; use `INGO_ROLE=all` for ingest commands.

## Roadmap / Improvements

See [IMPROVEMENTS.md](IMPROVEMENTS.md) for ongoing improvement notes.
See [docs/corpus-fetch-workflow.md](docs/corpus-fetch-workflow.md) for the crawl-enabled fetch workflow.
See [docs/document-only-crawl.md](docs/document-only-crawl.md) for document-only vector-ready crawl behavior.
