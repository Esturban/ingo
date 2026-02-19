#!/usr/bin/env bash

set -euo pipefail

ingo_chunk_txt() {
  local txt="$1"
  local out_jsonl="$2"
  local chunk_size="$3"
  local overlap="$4"

  LC_ALL=C awk \
    -v chunk_size="$chunk_size" \
    -v overlap="$overlap" \
    -v source="$(basename "$txt")" \
    '
    function esc(s,    t) {
      t = s
      gsub(/\\/,"\\\\",t)
      gsub(/"/,"\\\"",t)
      gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "", t)
      gsub(/\r/,"",t)
      gsub(/\t/," ",t)
      gsub(/\302\240/," ",t)
      gsub(/[ ]+/," ",t)
      gsub(/\n/,"\\n",t)
      return t
    }

    function emit_chunk(text, section, article, start_pos, end_pos, id, clean) {
      clean = text
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", clean)
      if (length(clean) == 0) return
      id = source "-" NR "-" start_pos "-" end_pos
      printf("{\"id\":\"%s\",\"source\":\"%s\",\"section\":\"%s\",\"article\":\"%s\",\"start\":%d,\"end\":%d,\"text\":\"%s\"}\n",
        esc(id), esc(source), esc(section), esc(article), start_pos, end_pos, esc(clean))
    }

    BEGIN {
      section = ""
      article = ""
      buf = ""
      start_pos = 1
      pos = 1
    }

    {
      line = $0
      line_lc = tolower(line)

      if (line_lc ~ /^[[:space:]]*(seccion|capitulo)[[:space:]]+/) {
        section = line
      }
      if (line_lc ~ /^[[:space:]]*(articulo)[[:space:]]+[0-9A-Za-z.-]+/) {
        article = line
      }

      if (length(buf) == 0) {
        start_pos = pos
      }

      if (length(line) == 0 && length(buf) > 0) {
        emit_chunk(buf, section, article, start_pos, pos)
        if (overlap > 0 && length(buf) > overlap) {
          buf = substr(buf, length(buf) - overlap + 1)
          start_pos = pos - length(buf)
        } else {
          buf = ""
        }
      } else {
        if (length(buf) > 0) {
          buf = buf "\n" line
        } else {
          buf = line
        }
      }

      if (length(buf) >= chunk_size) {
        emit_chunk(buf, section, article, start_pos, pos + length(line))
        if (overlap > 0 && length(buf) > overlap) {
          buf = substr(buf, length(buf) - overlap + 1)
          start_pos = pos + length(line) - length(buf)
        } else {
          buf = ""
        }
      }

      pos += length(line) + 1
    }

    END {
      if (length(buf) > 0) {
        emit_chunk(buf, section, article, start_pos, pos)
      }
    }
    ' "$txt" > "$out_jsonl"
}
