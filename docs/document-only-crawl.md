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

## What Gets Downloaded

Allowed extensions:

- `pdf`
- `docx`
- `xlsx`
- `xlsm`

Common exclusions:

- `.zip`
- images/icons (`png`, `jpg`, `svg`, `ico`, ...)
- frontend assets (`js`, `css`, fonts)
- social/login/generic non-document pages

## Output Files

- Accepted docs manifest: `data/corpus/manifests/gdb_documents.ndjson`
- Skipped ledger: `data/corpus/manifests/gdb_skipped.ndjson`
- Error ledger: `data/corpus/manifests/gdb_errors.ndjson`
- Downloaded files: `data/corpus/downloads/`

## Inspect Results

```bash
jq -r '.status' data/corpus/manifests/gdb_documents.ndjson | sort | uniq -c
jq -r '.reason' data/corpus/manifests/gdb_skipped.ndjson | sort | uniq -c
jq -r '.error' data/corpus/manifests/gdb_errors.ndjson | sort | uniq -c
find data/corpus/downloads -type f | sed -n '1,50p'
```

## Notes

- Crawl dedupe is based on content hash.
- Accepted documents are saved with a stable hash suffix in filename to avoid collisions.
- HTML is used as discovery surface only; documents are the index payload.
