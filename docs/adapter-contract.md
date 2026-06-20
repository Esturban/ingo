# ingo Adapter Contract

Any vector backend can plug into ingo by implementing three shell functions and either:

- **dropping a file** into `lib/vector/<name>.sh` (built-in), or
- **pointing an env var** at it: `INGO_VECTOR_ADAPTER=/path/to/my-adapter.sh`

---

## Selecting a backend

```sh
# Built-in
INGO_VECTOR_BACKEND=qdrant ingo query "my question"

# External adapter — no changes to ingo required
INGO_VECTOR_BACKEND=chroma \
INGO_VECTOR_ADAPTER=/opt/adapters/chroma.sh \
ingo query "my question"
```

Backend names may contain `a-z`, `0-9`, hyphens, and underscores.
Hyphens are converted to underscores when forming function names.

---

## Three functions to implement

Replace `<name>` with your backend name slug (hyphens → underscores).

### 1. `ingo_vector_<name>_doctor`

Print a one-line status string and exit 0, or print an error and exit non-zero
if required env vars are missing.

```sh
ingo_vector_chroma_doctor() {
  [ -n "${CHROMA_URL:-}" ] || { echo "missing: CHROMA_URL" >&2; return 4; }
  printf "vector: backend=chroma url=%s\n" "$CHROMA_URL"
}
```

### 2. `ingo_vector_<name>_embed_jsonl <jsonl> <namespace> [raw_dir]`

Read a JSONL file (one JSON object per line), upsert every chunk into the
backend, and print the count of vectors written to stdout.

Each line has at minimum: `id`, `text`, `source`, `section`, `article`.
`raw_dir` is optional — if set, a `.meta` file lives at `$raw_dir/<basename>.meta`
with extra fields (`doc_id`, `norm_type`, `issuer`, etc.).

```sh
ingo_vector_chroma_embed_jsonl() {
  local jsonl="$1" namespace="$2" count=0 line
  # shellcheck disable=SC2094
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    _chroma_upsert "$line" "$namespace"
    count=$((count + 1))
  done < "$jsonl"
  printf "%s\n" "$count"
}
```

### 3. `ingo_vector_<name>_query_text <question> <top_k> <namespace>`

Query the backend and print a normalized JSON object to stdout.

**Required output shape** — ingo validates this before returning to the caller:

```json
{
  "match_count": 3,
  "matches": [
    {
      "id":      "chunk-abc-001",
      "score":   0.92,
      "text":    "El artículo 5 establece que ...",
      "source":  "decreto-1076-2015.pdf",
      "section": "Capítulo II",
      "article": "Artículo 5"
    }
  ]
}
```

Fields `id`, `score`, `text`, `source`, `section`, and `article` are required;
`score` must be a number; all others must be strings. Your adapter is responsible
for normalizing whatever your backend returns into this shape.

---

## HTTP helper

Your adapter can use ingo's built-in retry/backoff-aware curl wrapper:

```sh
response="$(ingo_http_curl -sS -w "\n%{http_code}" \
  -X POST "${MY_URL}/upsert" \
  -H "Authorization: Bearer ${MY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$payload")"

status="$(printf "%s" "$response" | tail -n 1)"
body="$(printf "%s" "$response" | sed '$d')"
```

`ingo_http_curl` honours `INGO_HTTP_RETRY_ATTEMPTS`, `INGO_HTTP_RETRY_BACKOFF_*`,
and `INGO_HTTP_RETRY_AFTER_MAX`. It is available because ingo sources `lib/http.sh`
before loading any adapter.

---

## Reference implementations

| File | Backend | Notes |
|------|---------|-------|
| `lib/vector/upstash.sh` | Upstash Vector | Default; server-side text embedding |
| `lib/vector/pinecone.sh` | Pinecone | Integrated-embedding indexes |
| `lib/vector/qdrant.sh` | Qdrant | Inference-backed or BYO vectors |
| `lib/vector/generic.sh` | Any REST API | Configure via env vars, no code needed |

---

## Minimal starter template

```sh
#!/usr/bin/env bash
# Replace MY and my_backend with your backend name throughout.
set -euo pipefail

ingo_vector_my_backend_doctor() {
  [ -n "${MY_URL:-}" ] || { echo "missing: MY_URL" >&2; return 4; }
  printf "vector: backend=my-backend url=%s\n" "$MY_URL"
}

ingo_vector_my_backend_embed_jsonl() {
  local jsonl="$1" namespace="$2" count=0 line
  # shellcheck disable=SC2094
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    line="$(printf "%s" "$line" | LC_ALL=C tr -d '\000-\011\013\014\016-\037\177')"
    # TODO: POST $line to your upsert endpoint
    count=$((count + 1))
  done < "$jsonl"
  printf "%s\n" "$count"
}

ingo_vector_my_backend_query_text() {
  local question="$1" top_k="$2" namespace="$3"
  # TODO: POST to your query endpoint, normalize to:
  # { "match_count": N, "matches": [ { "id","score","text","source","section","article" } ] }
  printf '{"match_count":0,"matches":[]}\n'
}
```
