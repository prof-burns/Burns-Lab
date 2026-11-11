Event photos
============

One folder per event, named after that event's "slug" in data/events.json.

To add photos to an event:
  1. Drop the photos into the matching folder below.
  2. Run  scripts/update-events.sh  from the top of the project.
  3. Commit. The photos appear on the events page in filename order,
     so name them 01.jpg, 02.jpg and so on if the order matters.

To add a new event:
  1. Add an entry to data/events.json, including a "slug".
  2. Run  scripts/update-events.sh  and it creates the folder for you.

Large photos straight off a phone should go through
scripts/optimize-images.sh first.
