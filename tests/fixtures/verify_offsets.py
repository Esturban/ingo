#!/usr/bin/env python3
# REUSE_CHECKED: none -- no prior offset-verification script existed in this
# repo before DEV-6550; this is the reusable form of the scratch verifier
# used to prove the chunker against 5,966 real chunks from 5 public
# Colombian regulatory PDFs (see docs/offsets.md).
"""Verify every chunk's (page, line_start, line_end) opens to text that
contains the chunk's own verbatim `text`, once whitespace is normalized.
Exit 0 if every chunk verifies, 1 otherwise (with the failing ids printed).

Usage: verify_offsets.py <source.txt> <chunks.jsonl>
"""
import json
import re
import sys


def normalize(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def check_file(txt_path: str, jsonl_path: str):
    raw = open(txt_path, "r", encoding="utf-8", errors="replace").read()
    pages = raw.split("\x0c")  # pages[i] = page i+1's content
    total = 0
    ok = 0
    fails = []
    with open(jsonl_path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            total += 1
            rec = json.loads(line)
            page = rec["page"]
            ls, le = rec["line_start"], rec["line_end"]
            text = rec["text"]
            if page < 1 or page > len(pages):
                fails.append((rec["id"], "page out of range"))
                continue
            page_lines = pages[page - 1].split("\n")
            if ls < 1 or le > len(page_lines) or ls > le:
                fails.append((rec["id"], f"line range invalid ls={ls} le={le} pagelines={len(page_lines)}"))
                continue
            window = "\n".join(page_lines[ls - 1 : le])
            if normalize(text) in normalize(window):
                ok += 1
            else:
                fails.append((rec["id"], "text not found in claimed line range"))
    return total, ok, fails


if __name__ == "__main__":
    txt_path, jsonl_path = sys.argv[1], sys.argv[2]
    total, ok, fails = check_file(txt_path, jsonl_path)
    print(f"{jsonl_path}: {ok}/{total} chunks verified exact")
    for fid, reason in fails[:15]:
        print(f"  FAIL {fid}: {reason}")
    if len(fails) > 15:
        print(f"  ... and {len(fails) - 15} more")
    sys.exit(0 if not fails else 1)
