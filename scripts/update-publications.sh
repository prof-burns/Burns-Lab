#!/bin/bash
# Rebuild data/publications.json from PubMed.
#
# Input:  a PubMed author query (below) and data/publications-exclude.txt
# Output: data/publications.json, which the website reads directly
#
# Run it whenever a new paper comes out:  scripts/update-publications.sh
# Nothing to install: curl and python3 both ship with macOS.

# ---- settings ----------------------------------------------------------
QUERY="Burns MB[Author]"                      # PubMed search, same syntax as the website
MAX=200                                       # most records to pull
OUT="data/publications.json"
EXCLUDE="data/publications-exclude.txt"       # one PMID per line, # for comments
TOOL="burns-lab-site"                         # NCBI asks callers to identify themselves
EMAIL="michael@burns-lab.org"
# ------------------------------------------------------------------------

EUTILS="https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
mkdir -p data
tmp=$(mktemp -d)

# 1. Find the PMIDs matching the query, newest first.
curl -s "$EUTILS/esearch.fcgi" \
  --get --data-urlencode "term=$QUERY" \
  -d db=pubmed -d retmode=json -d sort=pub_date -d "retmax=$MAX" \
  -d "tool=$TOOL" -d "email=$EMAIL" -o "$tmp/search.json"

ids=$(python3 -c "
import json
ids = json.load(open('$tmp/search.json'))['esearchresult']['idlist']
skip = set()
try:
    for line in open('$EXCLUDE'):
        line = line.split('#')[0].strip()
        if line: skip.add(line)
except FileNotFoundError:
    pass
print(','.join(i for i in ids if i not in skip))
")

if [ -z "$ids" ]; then echo "No records found for: $QUERY"; exit 1; fi

# 2. Pull the summary record for each one.
curl -s "$EUTILS/esummary.fcgi" -d db=pubmed -d retmode=json -d "id=$ids" \
  -d "tool=$TOOL" -d "email=$EMAIL" -o "$tmp/summary.json"

# 3. Keep just the fields the website shows.
python3 - "$tmp/summary.json" "$OUT" <<'PY'
import json, sys
src, out = sys.argv[1], sys.argv[2]
result = json.load(open(src))["result"]
papers = []
for uid in result["uids"]:
    r = result[uid]
    doi = next((a["value"] for a in r.get("articleids", []) if a["idtype"] == "doi"), "")
    papers.append({
        "pmid":    uid,
        "year":    r.get("pubdate", "")[:4],
        # sortpubdate reads "2025/08/21 00:00"; the website uses the date for its rolling window
        "date":    r.get("sortpubdate", "")[:10].replace("/", "-"),
        "title":   r.get("title", "").rstrip("."),
        "authors": ", ".join(a["name"] for a in r.get("authors", []) if a.get("authtype") == "Author"),
        "journal": r.get("source", ""),
        "doi":     doi,
    })
json.dump(papers, open(out, "w"), indent=1)
print(f"wrote {len(papers)} publications to {out}")
PY

rm -rf "$tmp"
