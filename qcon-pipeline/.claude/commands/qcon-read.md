---
description: Read slide photos into slides.md and refresh notes.md for one talk or all talks
argument-hint: "<talk_id | all> [--force]"
allowed-tools: Task, Read, Glob, Bash(python3 tools/transcribe.py:*), Bash(python3 tools/ingest.py:*), Bash(ls:*)
---

Turn captures into text for: $ARGUMENTS

1. Resolve the talk list. `all` means every folder in `vault/talks/` that has `photos/index.json`.
   Skip a talk whose `slides.md` is newer than its `photos/index.json`, unless `--force` is given.
2. Fan out: launch one `slide-reader` subagent per talk, in parallel (several Task calls in one
   message). Give each one the absolute path of its talk folder and nothing else. Each writes
   `vault/talks/<talk_id>/slides.md`.
3. Reflections: if any `voice/*.m4a` lacks a `.txt`, run `python3 tools/transcribe.py <talk ids>`.
   If faster-whisper is not installed, say so once (install notes are in the script's docstring)
   and continue without transcripts.
4. Run `python3 tools/ingest.py` (no arguments) so `notes.md` picks up new transcripts. It only
   rebuilds talk folders; it does not touch `slides.md`, `research/` or `brief.md`.
5. Report per talk: photos read, photos flagged unreadable, near-duplicates skipped, URLs/repos/names
   found on slides (count), reflections transcribed. List unreadable photos by ref so Matt can look.

Do not open the web in this step.
