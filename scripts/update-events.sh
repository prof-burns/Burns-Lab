#!/bin/bash
# Point each event at the photos sitting in its own folder.
#
# Every event in data/events.json has a "slug". Its photos live in
#   images/events/<slug>/
# Drop photos in that folder, run this script, and they appear on the events page
# in filename order. The script also creates a folder for any event missing one,
# so adding an event to the JSON and running this gives you the drop spot.
#
# Usage: scripts/update-events.sh

EVENTS="data/events.json"
PHOTO_ROOT="images/events"

python3 - "$EVENTS" "$PHOTO_ROOT" <<'PY'
import json, os, sys
events_file, root = sys.argv[1], sys.argv[2]
events = json.load(open(events_file))
exts = (".jpg", ".jpeg", ".png", ".webp")

for e in events:
    folder = os.path.join(root, e["slug"])
    os.makedirs(folder, exist_ok=True)
    # keep empty folders in git so the drop spot exists after a clone
    keep = os.path.join(folder, ".gitkeep")
    if not os.path.exists(keep):
        open(keep, "w").close()
    photos = sorted(f for f in os.listdir(folder) if f.lower().endswith(exts))
    e["photos"] = [f"{folder}/{f}" for f in photos]
    print(f"{e['slug']}: {len(photos)} photo(s)")

json.dump(events, open(events_file, "w"), indent=1)
PY

echo
echo "Reminder: run scripts/optimize-images.sh on big photos before committing them."
