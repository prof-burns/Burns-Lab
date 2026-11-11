#!/bin/bash
# Rebuild data/abstracts.json: conference abstracts published as journal supplements.
#
# PubMed does not index meeting abstracts, but the supplements they appear in
# (SID in JID, AAD in JAAD, and so on) register DOIs with Crossref, so that is
# where we look. An abstract is recognised by a supplement page number (S..,
# AB..) or by the abstract number that starts its title.
#
# Anything Crossref does not carry, such as GLBIO or a symposium poster, goes in
# data/abstracts-manual.json by hand. This script never touches that file.
#
# Scope rule, and it differs by who presented:
#   Dr. Burns' own talks  - everything, internal Loyola events included.
#   Students and mentees  - external venues only. Internal events (Carbon Luncheon,
#                           USRE, the Undergraduate Research Symposium) stay off.
#
# Usage: scripts/update-abstracts.sh

LAST="Burns"          # author surname to match
INITIAL="M"           # first initial
FROM="2018-01-01"     # earliest publication date to consider
OUT="data/abstracts.json"
DOIS="data/abstracts-dois.txt"      # extra abstracts to fetch by DOI
SKIP="data/abstracts-exclude.txt"   # DOIs that are a different M Burns

# Journals that publish the meeting abstracts we care about. Keep this to venues
# where "M Burns" is unambiguous; anywhere else, list the DOI in $DOIS instead.
JOURNALS=(
  "Journal of Investigative Dermatology"
  "Journal of the American Academy of Dermatology"
  "British Journal of Dermatology"
  "Journal of the European Academy of Dermatology and Venereology"
  "Experimental Dermatology"
  "Archives of Dermatological Research"
  "JID Innovations"
)

mkdir -p data
tmp=$(mktemp -d)

for j in "${JOURNALS[@]}"; do
  enc=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$j")
  curl -s "https://api.crossref.org/works?query.author=$LAST&filter=container-title:$enc,from-pub-date:$FROM&rows=300&select=title,author,container-title,published,DOI,page" \
    -o "$tmp/$(echo "$j" | tr ' /' '__').json"
done

# Fetch each DOI listed in $DOIS on its own. The journal sweep ranks by
# relevance, so in a large journal it never reaches these.
n=0
while read -r line; do
  doi=$(echo "$line" | sed 's/#.*//' | tr -d '[:space:]')
  [ -z "$doi" ] && continue
  n=$((n+1))
  curl -s "https://api.crossref.org/works/$doi" \
    | python3 -c "import json,sys; print(json.dumps({'message': {'items': [json.load(sys.stdin)['message']]}}))" \
    > "$tmp/doi_$n.json" 2>/dev/null
done < "$DOIS"

python3 - "$tmp" "$OUT" "$LAST" "$INITIAL" <<'PY'
import glob, json, os, re, sys
tmp, out, last, initial = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

skip = set()
if os.path.exists("data/abstracts-exclude.txt"):
    for line in open("data/abstracts-exclude.txt"):
        line = line.split("#")[0].strip()
        if line: skip.add(line.lower())

# Crossref knows the author list but not who stood up and gave the talk, nor
# whether it was a talk or a poster. Convention is that the first author presents,
# so that is the starting guess; anything you correct by hand is carried over
# instead of being overwritten on the next run.
HAND_SET = ("type", "presenter", "presented_by", "note")
kept = {}
if os.path.exists(out):
    for r in json.load(open(out)):
        link = r.get("link", "")
        if link and not r.get("inferred", True):
            kept[link] = {k: r[k] for k in HAND_SET if k in r}

# lab members, so we can tell a trainee presenting from a collaborator presenting
lab = []
try:
    lab = json.load(open("data/lab-authors.json"))
except Exception:
    pass

def as_initials(given):
    """'Michael B.' and 'M. B.' both become 'MB'."""
    return "".join(t[0] for t in re.split(r"[\s.]+", given) if t).upper()

def name_of(a):
    return f"{a.get('family','')} {as_initials(a.get('given',''))}".strip()

def is_lab(name):
    parts = name.split()
    if len(parts) < 2:
        return False
    surname, initials = " ".join(parts[:-1]), parts[-1]
    return any(p["last"].lower() == surname.lower() and initials.startswith(p["initial"])
               for p in lab)

records = {}
for f in glob.glob(os.path.join(tmp, "*.json")):
    try:
        items = json.load(open(f))["message"]["items"]
    except Exception:
        continue
    for it in items:
        authors = it.get("author", [])
        if not any(a.get("family", "").lower() == last.lower()
                   and a.get("given", "").upper().startswith(initial) for a in authors):
            continue
        if it["DOI"].lower() in skip:
            continue
        title = (it.get("title") or [""])[0]
        page = it.get("page", "")
        aacr = re.match(r"^Abstract\s+([A-Z0-9][\w.-]*):\s*(.+)$", title, re.S)
        if not (page.startswith(("S", "AB")) or re.match(r"^\d{3,5}\s", title) or aacr):
            continue                      # a regular paper, not a meeting abstract
        # strip the abstract number off the front of the title, whichever style it is
        if aacr:
            number, title = aacr.group(1), aacr.group(2).strip()
        elif re.match(r"^\d{3,5}\s", title):
            parts = title.split()
            number, title = parts[0], " ".join(parts[1:])
        else:
            number = ""

        # first author is the presenter by convention
        presenter = name_of(authors[0]) if authors else ""
        journal = it.get("container-title", [""])[0]
        # The website uses "date" to decide what counts as a recent talk. Crossref only
        # knows when the supplement came out, which trails the meeting by a month or two.
        parts = it.get("published", {}).get("date-parts", [[""]])[0]
        records[it["DOI"]] = {
            "year": str(parts[0]),
            "date": "-".join(str(p).zfill(2) for p in parts),
            "meeting": "SID Annual Meeting" if "Investigative Derm" in journal
                       else "AAD Annual Meeting" if "American Academy" in journal
                       else "AACR meeting" if journal in ("Cancer Research", "Molecular Cancer Research",
                                                          "Molecular Cancer Therapeutics", "Clinical Cancer Research")
                       else journal,
            "title": title,
            "number": number,
            "authors": ", ".join(name_of(a) for a in authors),
            "link": "https://doi.org/" + it["DOI"],
            "type": "abstract",
            "presenter": presenter,
            "presented_by": ("burns" if presenter.lower().startswith(last.lower() + " " + initial.lower())
                             else "lab" if is_lab(presenter) else "collaborator"),
            "inferred": True,     # set false once you have checked who presented
        }
        hand = kept.get("https://doi.org/" + it["DOI"], {})
        if hand:
            records[it["DOI"]].update(hand)
            records[it["DOI"]]["inferred"] = False

rows = sorted(records.values(), key=lambda r: (r["year"], r["number"]), reverse=True)
json.dump(rows, open(out, "w"), indent=1)
print(f"wrote {len(rows)} conference abstracts to {out}")
PY

rm -rf "$tmp"
