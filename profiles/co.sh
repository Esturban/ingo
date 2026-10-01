#!/usr/bin/env bash
# REUSE_CHECKED: /Users/EVA/Desktop/eva/03_development/_dev/repos/3_utilities/go/bfr/.venv-docs/lib/python3.14/site-packages/babel/locale-data/co.dat
# that hit is Babel's Corsican ("co") locale data, vendored inside an
# unrelated tool's venv -- a coincidental filename match, not jurisdiction
# config. Also searched for '*jurisdiction*'/'*profile*' under this repo
# (DEV-6550): no prior per-jurisdiction config existed before
# lib/jurisdiction.sh (this same ticket) introduced the profiles/ contract.

set -euo pipefail

# DEV-6550: Colombia jurisdiction profile -- ANLA (licenciamiento ambiental),
# IGAC (catastro/cartografia), MADS (decretos/resoluciones marco), CAR
# (corporaciones autonomas regionales). Loaded when INGO_JURISDICTION=co.
#
# Every assignment below uses ":=" so a value already set by the caller's
# environment or .env (higher precedence) is never overwritten -- this file
# only fills in what is still unset when it runs, per lib/jurisdiction.sh.

# Article/paragrafo/numeral/section patterns matched against a lowercase,
# accent-folded copy of each line (see lc_es() in lib/chunk.sh). Both the
# accented and unaccented spelling are listed because OCR and some official
# PDFs drop tildes. Also matches the abbreviated drafting style some
# issuers use (confirmed on a real IGAC resolution: "ART. 1o-Objeto." /
# "PAR.-..." instead of the spelled-out "Articulo"/"Paragrafo") -- without
# "art\."/"par\." those documents' articles never get detected at all.
#
# ANLA resolutions' own dispositive section ("RESUELVE:") numbers its
# articles with ordinal WORDS, not digits -- confirmed on a real ANLA
# resolution: "ARTICULO PRIMERO.", "ARTICULO SEGUNDO.", never "ARTICULO 1.".
# A digit-only pattern misses every one of those articles.
: "${INGO_SECTION_PATTERN:=^[[:space:]]*(seccion|sección|capitulo|capítulo|titulo|título)[[:space:]]+}"
: "${INGO_ARTICLE_PATTERN:=^[[:space:]]*(articulo|artículo|art\.)[[:space:]]+([0-9]|primero|segundo|tercero|cuarto|quinto|sexto|septimo|séptimo|octavo|noveno|decimo|décimo)}"
: "${INGO_PARAGRAPH_PATTERN:=^[[:space:]]*(paragrafo|parágrafo|par\.)}"
# A literal {n,m} interval inside a "${VAR:=word}" default silently
# truncates in bash (confirmed on 5.3.15: the word is cut right after the
# nested "}", losing everything past it) -- go through a plain variable
# first so the brace only ever appears in an ordinary assignment, never
# nested inside another parameter expansion.
_ingo_co_default_numeral_pattern='^[[:space:]]*([0-9]{1,3}|[a-z])[.)][[:space:]]+'
: "${INGO_NUMERAL_PATTERN:=$_ingo_co_default_numeral_pattern}"
unset _ingo_co_default_numeral_pattern

# Relevance-gate vocabulary (see lib/relevance.sh / INGO_MIN_TERM_MATCHES):
# rejects OCR noise that never mentions any Colombian environmental/
# cadastral term, on top of the generic defaults in lib/env.sh.
: "${INGO_RELEVANCE_TERMS:=ambiental,licencia,licenciamiento,vertimiento,emision,resolucion,decreto,articulo,paragrafo,numeral,autoridad,ministerio,anla,igac,mads,car,corporacion autonoma regional,catastro,pma,agua,suelo,aire,fauna,flora,biodiversidad,recurso hidrico,plan de manejo ambiental}"

# Best-effort issuer detection: comma-separated ISSUER:PHRASE pairs. sig's
# `norma` command (and any future consumer) scans the first lines of a
# document's own text for one of these phrases to label the source without
# needing per-file manifest metadata. First match wins; order matters.
: "${INGO_ISSUER_HINTS:=ANLA:AUTORIDAD NACIONAL DE LICENCIAS AMBIENTALES,IGAC:INSTITUTO GEOGRAFICO AGUSTIN CODAZZI,MADS:MINISTERIO DE AMBIENTE Y DESARROLLO SOSTENIBLE,PRESIDENCIA:PRESIDENCIA DE LA REPUBLICA,CONGRESO:CONGRESO DE LA REPUBLICA,CAR:CORPORACION AUTONOMA REGIONAL}"
