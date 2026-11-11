---
description: One table showing every talk's progress through the pipeline and which talks have no official video
allowed-tools: Bash(python3 tools/status.py:*), Read
---

1. Run `python3 tools/status.py` and show its table as is.
2. Below it, list in this order, one line each:
   - Talks with no official video expected (their captures and reflections are the only record).
   - Briefs in `draft` that have a passing `check.md` (ready for Matt's review).
   - Briefs whose check failed.
   - Reviewed briefs not yet in `kb/` (ready for `/qcon-publish`).
   - From Dec 21: published talks with a video expected but no `reconcile.md`.
3. End with the single most useful next command.
