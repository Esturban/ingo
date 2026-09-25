#!/usr/bin/env bash

set -euo pipefail

# DEV-6550: chunk.sh now keeps page, paragraph and line offsets per chunk
# (not just the old flat character start/end), so every hit returned by
# `ingo query` can cite documento + pagina + parrafo/articulo/numeral +
# lineas + cita textual verbatim. See docs/offsets.md for the exact
# definitions (what "page" and "line" mean here) and docs/jurisdiction-profiles.md
# for how INGO_SECTION_PATTERN/INGO_ARTICLE_PATTERN/INGO_PARAGRAPH_PATTERN/
# INGO_NUMERAL_PATTERN are set per jurisdiction (see profiles/co.sh).

ingo_chunk_txt() {
  local txt="$1"
  local out_jsonl="$2"
  local chunk_size="$3"
  local overlap="$4"

  LC_ALL=C awk \
    -v chunk_size="$chunk_size" \
    -v overlap="$overlap" \
    -v source="$(basename "$txt")" \
    -v section_pattern="${INGO_SECTION_PATTERN:-}" \
    -v article_pattern="${INGO_ARTICLE_PATTERN:-}" \
    -v paragraph_pattern="${INGO_PARAGRAPH_PATTERN:-}" \
    -v numeral_pattern="${INGO_NUMERAL_PATTERN:-}" \
    '
    # LC_ALL=C tolower() only touches ASCII a-z/A-Z; it leaves UTF-8
    # accented capitals (multi-byte sequences) untouched, so "CAPITULO"
    # with an accented I would lowercase to a mixed-case string and never
    # match a plain-lowercase pattern. Fold the Spanish accented capitals
    # byte-for-byte first (octal escapes = exact UTF-8 byte pairs).
    function lc_es(s,    t) {
      t = s
      gsub(/\303\201/, "\303\241", t)  # Á -> á
      gsub(/\303\211/, "\303\251", t)  # É -> é
      gsub(/\303\215/, "\303\255", t)  # Í -> í
      gsub(/\303\223/, "\303\263", t)  # Ó -> ó
      gsub(/\303\232/, "\303\272", t)  # Ú -> ú
      gsub(/\303\221/, "\303\261", t)  # Ñ -> ñ
      gsub(/\303\234/, "\303\274", t)  # Ü -> ü
      return tolower(t)
    }

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

    function start_new_buf(first_line) {
      buf_start_page = page
      buf_start_article = article
      para_in_page += 1
      buf_para = para_in_page
      buf_line_start = page_line
      last_content_line = page_line
      buf = first_line
      buf_linenos = page_line
    }

    # Retain trailing whole lines of the just-flushed buffer as the seed of
    # the next chunk, so the reported line_start of the retained tail is
    # always a real physical line -- never a character-count guess that can
    # land mid-line or point at the wrong paragraph. Retains lines from the
    # end of `buf` until >= `overlap` characters are captured; if that would
    # be the entire buffer (paragraph shorter than the overlap budget), or
    # the buffer changed article since it started, nothing is retained.
    #
    # `buf` can already span an earlier retained (non-contiguous) tail --
    # e.g. it skipped a blank separator line -- so the tail line start is
    # looked up from the parallel `prev_linenos` list, never computed by
    # subtracting a line count from `last_content_line` (that arithmetic
    # silently assumes no gaps, which is false once a chunk has already
    # crossed one blank line).
    function retain_overlap_tail(flush_end_pos,    n, arr, lns, i, acc, k, tail) {
      buf = ""
      if (overlap <= 0 || article != buf_start_article) {
        return
      }
      n = split(prev_buf, arr, "\n")
      split(prev_linenos, lns, " ")
      acc = 0
      k = 0
      for (i = n; i >= 1; i--) {
        acc += length(arr[i]) + 1
        k += 1
        if (acc >= overlap) break
      }
      if (k >= n) {
        return
      }
      tail = arr[n - k + 1]
      buf_linenos = lns[n - k + 1]
      for (i = n - k + 2; i <= n; i++) {
        tail = tail "\n" arr[i]
        buf_linenos = buf_linenos " " lns[i]
      }
      buf_start_page = page
      buf_start_article = article
      para_in_page += 1
      buf_para = para_in_page
      buf_line_start = lns[n - k + 1] + 0
      start_pos = flush_end_pos - length(tail)
      buf = tail
    }

    function emit_chunk(text, sect, art, par_mark, num_mark, start_p, end_p, pg, para_no, line_s, line_e,    clean, id) {
      clean = text
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", clean)
      if (length(clean) == 0) return
      id = source "-" NR "-" start_p "-" end_p
      printf("{\"id\":\"%s\",\"source\":\"%s\",\"page\":%d,\"paragraph\":%d,\"line_start\":%d,\"line_end\":%d,\"section\":\"%s\",\"article\":\"%s\",\"paragraph_marker\":\"%s\",\"numeral_marker\":\"%s\",\"start\":%d,\"end\":%d,\"text\":\"%s\"}\n",
        esc(id), esc(source), pg, para_no, line_s, line_e, esc(sect), esc(art), esc(par_mark), esc(num_mark), start_p, end_p, esc(clean))
    }

    BEGIN {
      FF = sprintf("%c", 12)
      page = 1
      page_line = 0
      last_content_line = 0
      para_in_page = 0
      section = ""
      article = ""
      paragraph_marker = ""
      numeral_marker = ""
      buf = ""
      buf_start_page = 1
      buf_start_article = ""
      buf_para = 0
      buf_line_start = 0
      buf_linenos = ""
      start_pos = 1
      pos = 1
    }

    {
      raw = $0
      # A page with zero extractable text (a scanned figure, a blank page)
      # still gets its own form feed, so two or more FF bytes can land at
      # the front of the same record back-to-back. Consume every one of
      # them and advance `page` for each -- stopping after only the first
      # would silently merge an empty page into the next one and leave
      # every later page number off by one for the rest of the document.
      while (index(raw, FF) == 1) {
        if (length(buf) > 0) {
          emit_chunk(buf, section, article, paragraph_marker, numeral_marker, start_pos, pos, buf_start_page, buf_para, buf_line_start, last_content_line)
          buf = ""
        }
        page += 1
        page_line = 0
        para_in_page = 0
        raw = substr(raw, 2)
      }
      line = raw

      page_line += 1
      line_lc = lc_es(line)

      is_new_section = (section_pattern != "" && line_lc ~ section_pattern)
      is_new_article = (article_pattern != "" && line_lc ~ article_pattern)
      is_new_paragraph_marker = (paragraph_pattern != "" && line_lc ~ paragraph_pattern)
      is_new_numeral = (numeral_pattern != "" && line_lc ~ numeral_pattern)

      if ((is_new_section || is_new_article || is_new_paragraph_marker || is_new_numeral) && length(buf) > 0) {
        # Any structural heading (titulo/capitulo/seccion/articulo/paragrafo/
        # numeral) always starts a fresh chunk: never let one chunk of text
        # straddle two different legal citation units.
        emit_chunk(buf, section, article, paragraph_marker, numeral_marker, start_pos, pos, buf_start_page, buf_para, buf_line_start, last_content_line)
        buf = ""
      }
      if (is_new_section) {
        section = line
      }
      if (is_new_article) {
        article = line
        paragraph_marker = ""
        numeral_marker = ""
      }
      if (is_new_paragraph_marker) {
        paragraph_marker = line
        numeral_marker = ""
      }
      if (is_new_numeral) {
        numeral_marker = line
      }

      if (length(line) == 0) {
        if (length(buf) > 0) {
          emit_chunk(buf, section, article, paragraph_marker, numeral_marker, start_pos, pos, buf_start_page, buf_para, buf_line_start, last_content_line)
          prev_buf = buf
          prev_linenos = buf_linenos
          retain_overlap_tail(pos)
        }
      } else {
        last_content_line = page_line
        if (length(buf) == 0) {
          start_pos = pos
          start_new_buf(line)
        } else {
          buf = buf "\n" line
          buf_linenos = buf_linenos " " page_line
        }
      }

      if (length(buf) >= chunk_size) {
        emit_chunk(buf, section, article, paragraph_marker, numeral_marker, start_pos, pos + length(line), buf_start_page, buf_para, buf_line_start, last_content_line)
        prev_buf = buf
        prev_linenos = buf_linenos
        retain_overlap_tail(pos + length(line))
      }

      pos += length(line) + 1
    }

    END {
      if (length(buf) > 0) {
        emit_chunk(buf, section, article, paragraph_marker, numeral_marker, start_pos, pos, buf_start_page, buf_para, buf_line_start, last_content_line)
      }
    }
    ' "$txt" > "$out_jsonl"
}
