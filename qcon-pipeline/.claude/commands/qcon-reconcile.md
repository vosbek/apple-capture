---
description: After Dec 21, convert a talk's moments and notes into official-video timestamps
argument-hint: "<talk_id>"
allowed-tools: Read, Glob, Bash(python3 tools/reconcile.py:*)
---

Reconcile $ARGUMENTS with its official recording (architecture 10). The video player is not
scriptable and the videos may not be downloaded, so this needs one alignment point from Matt.

1. Read `vault/talks/$ARGUMENTS/photos/index.json` and `slides.md`. Suggest three distinctive slides
   (title slide excluded) with their refs and a one-line description each, so Matt can spot one quickly.
2. Ask Matt for: the video URL, which slide he found, and the video time where it appears (mm:ss).
   Do not try to open or play the video yourself.
3. Run `python3 tools/reconcile.py $ARGUMENTS --video-url "<url>" --photo <Sxx> --at <mm:ss>`.
4. Show the Watch list from `reconcile.md`. Ask Matt to check one more moment against the video;
   if it is off by more than 30 s, re-run with a second slide he names and report both offsets.
5. Tell Matt: watch those segments, add notes to `vault/talks/<id>/notes-video.md` (one line per
   point, prefixed with the video time), then re-run `/qcon-brief <id>`; the writer may raise
   confidence only where the new notes support it.
