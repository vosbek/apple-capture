---
description: Ingest Collector zips (or fallback captures) from inbox/ into the private vault
argument-hint: "[zip-or-folder ...] | --fallback"
allowed-tools: Bash(python3 tools/ingest.py:*), Bash(python tools/ingest.py:*), Bash(ls:*), Read, Glob
---

Ingest new captures into `vault/`. Arguments: $ARGUMENTS

1. If the arguments are empty, list `inbox/` (zips and folders) and `inbox/fallback/` so the user
   can see what will be read. If `inbox/` is empty and no fallback files exist, say so and stop.
2. Run exactly one of:
   - App bundles: `python3 tools/ingest.py $ARGUMENTS` (no arguments means everything in `inbox/`).
   - Fallback (`--fallback` in the arguments, or only `inbox/fallback/` has files):
     `python3 tools/ingest.py --fallback` (it reads `inbox/fallback/*.txt`, `inbox/fallback/photos/`,
     `inbox/fallback/voice/` and `vault/plan.txt`).
3. Read `vault/ingest-report.json` and report, in this order:
   - Conflicts (exit code 2): a bundle that is not a superset of the copy already in `vault/raw/`.
     Name the `_conflicts/` folder. Do not delete or merge anything; ask Matt which copy is right.
   - A table: talk, devices, slides, moments, notes, reflections, start synced (yes/no), measured skew.
   - Validation problems per talk (truncated last line, missing media, clock jumps, skew over 10 s,
     unassigned fallback captures). One line each; group repeats.
   - Talks with `start_synced: false`: their offsets count from the scheduled start; the brief must say so.
   - Private talks (visibility private), so Matt knows they will never be published.
4. Suggest the next step: `/qcon-read all`.

Never modify anything outside `vault/`. Never edit files in `vault/raw/`.
