# Crawl-Enabled Fetch Workflow

This workflow extends `bin/ingo fetch` to discover and download corpus documents from seed pages while keeping the existing CLI shape.

## 1. Prepare seed and host files

Create a seed file:

```txt
https://www.anla.gov.co/01_anla/normatividad/documentos-estrategicos/terminos-de-referencia
https://www.minambiente.gov.co/asuntos-ambientales-sectorial-y-urbana/metodologia-general-para-la-elaboracion-y-presentacion-de-estudios-ambientales-mgepea/
```

Create an allow-host list (in addition to `.gov.co`):

```txt
vital-publico.minambiente.gov.co
```

## 2. Run fetch in crawl mode

```bash
bin/ingo fetch \
  --seeds data/corpus/seeds/seed_urls.txt \
  --crawl-depth 2 \
  --allow-hosts data/corpus/config/allow_hosts.txt \
  --manifest data/corpus/manifests/documents.ndjson
```

Outputs:

- `data/corpus/crawl/discovered-*.txt`: normalized discovered URLs.
- `data/corpus/downloads/`: downloaded candidate documents.
- `data/corpus/extracted/`: extracted text for supported formats.
- `data/corpus/manifests/documents.ndjson`: corpus records (`downloaded`, `duplicate`, `failed`, `extracted`, `unsupported`).

## 3. Curate documents manually

Review and delete anything you do not want indexed:

```bash
find data/corpus/downloads -type f | sort
rm -f "data/corpus/downloads/document-you-dont-want.pdf"
```

## 4. Publish to Upstash with existing pipeline

Continue with existing commands:

```bash
bin/ingo chunk --no-strict
bin/ingo embed
```

`embed` includes corpus metadata fields when present in sidecar metadata.

## 5. Troubleshooting

- If crawl returns very few links, verify seed URLs and `--crawl-depth`.
- If non-`.gov.co` sources are needed, add exact hosts to `allow_hosts.txt`.
- If extraction fails for `docx`/`html`, install `pandoc` (or `docx2txt` for `docx` fallback).
