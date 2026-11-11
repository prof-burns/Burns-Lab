#!/bin/bash
# Rebuild data/lab-authors.json, the list of lab members whose names get bolded
# in the publication list.
#
# Input:  people.html (every name on it except the collaborating research groups)
# Output: data/lab-authors.json, as {name, last, initial} per person
#
# Run it after you add or remove someone on the people page:
#   scripts/update-lab-authors.sh

PEOPLE="people.html"
OUT="data/lab-authors.json"
SKIP_SECTION="Collaborating Research Groups"   # other labs' PIs, not ours

mkdir -p data

python3 - "$PEOPLE" "$OUT" "$SKIP_SECTION" <<'PY'
import json, re, sys
people_file, out, skip = sys.argv[1], sys.argv[2], sys.argv[3]
html = open(people_file).read()

names = []
for section in html.split("<section"):
    if skip in section:
        continue
    # person cards: <div class="name">Jane Doe</div>
    names += re.findall(r'<div class="name">([^<]+)</div>', section)
    # alumni lists: <li>Jane Doe, Bioinformatics MS</li>
    for li in re.findall(r"<li>([^<]+)</li>", section):
        names.append(li)

people = {}
for raw in names:
    # drop anything after a comma or dash: degrees, fellowships, programs
    name = re.split(r"[,\-]", raw)[0].strip()
    parts = name.split()
    if len(parts) < 2:
        continue
    last, initial = parts[-1], parts[0][0]
    people[(last, initial)] = {"name": name, "last": last, "initial": initial}

records = sorted(people.values(), key=lambda p: (p["last"], p["initial"]))
json.dump(records, open(out, "w"), indent=1)
print(f"wrote {len(records)} lab members to {out}")
PY
