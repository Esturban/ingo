# Document-Only Crawl for Vector Index Readiness

This workflow keeps `fetch --seeds` focused on hard documents for indexing and suppresses generic pages/assets.

## Command

```bash
bin/ingo fetch \
  --seeds data/corpus/seeds/seed_url.txt \
  --crawl-depth 2 \
  --allow-hosts data/corpus/config/allowlist.txt \
  --manifest data/corpus/manifests/gdb_documents.ndjson
```

Optional:

```bash
bin/ingo fetch ... --progress-every 25 --verbose
```

Reset run ledgers only when needed:

```bash
bin/ingo fetch ... --reset-manifests
```

Optional page snapshot fallback (requires `wkhtmltopdf`):

```bash
bin/ingo fetch ... --snapshot-pages
```

## What Gets Downloaded

Allowed extensions:

- `pdf`
- `docx`
- `xlsx`
- `xlsm`

Spreadsheet extraction:

- `xlsx/xlsm` are converted into plain text table rows using `xlsx2csv` or `in2csv` when available.
- Fallback is `python3` + `openpyxl`.
- Converted text is written into the extraction/chunk pipeline, so spreadsheet content can enter the vector index.

Common exclusions:

- `.zip`
- images/icons (`png`, `jpg`, `svg`, `ico`, ...)
- frontend assets (`js`, `css`, fonts)
- social/login/generic non-document pages
- malformed URLs (spaces, bad schemes, invalid host section)

## Output Files

- Accepted docs manifest: `data/corpus/manifests/gdb_documents.ndjson`
- Skipped ledger: `data/corpus/manifests/gdb_skipped.ndjson`
- Error ledger: `data/corpus/manifests/gdb_errors.ndjson`
- Downloaded files: `data/corpus/downloads/`

By default manifests are append-only, and URLs already present in the accepted manifest are skipped with reason `already_seen_url`.
Host policy for discovery is derived from seed hosts plus `--allow-hosts`.

Progress phases during run:
- `crawl-progress`: discover + queue
- `collect-progress`: probe + download
- `extract-progress`: extraction

## Inspect Results

```bash
jq -r '.status' data/corpus/manifests/gdb_documents.ndjson | sort | uniq -c
jq -r '.reason' data/corpus/manifests/gdb_skipped.ndjson | sort | uniq -c
jq -r '.error' data/corpus/manifests/gdb_errors.ndjson | sort | uniq -c
jq -c 'select(.reason=="malformed_url")' data/corpus/manifests/gdb_skipped.ndjson | sed -n '1,20p'
find data/corpus/downloads -type f | sed -n '1,50p'
```

## Notes

- Crawl dedupe is based on content hash.
- Accepted documents are saved with a stable hash suffix in filename to avoid collisions.
- HTML is used as discovery surface only; documents are the index payload.
