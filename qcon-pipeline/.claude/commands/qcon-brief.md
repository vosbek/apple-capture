---
description: Write brief.md for one talk or all talks, then check every citation in a fresh context
argument-hint: "<talk_id | all>"
allowed-tools: Task, Read, Write, Glob, Grep
---

Write and check briefs for: $ARGUMENTS

1. Resolve the talk list (`all` = every talk folder with `slides.md`). Never overwrite a brief whose
   front matter says `status: reviewed` or `published`; list those as skipped. To redo one, Matt sets
   it back to `draft`.
2. For each talk, in parallel: launch `brief-writer` with the talk folder path, the path of
   `vault/lenses.yaml` and the path of `templates/brief.md`. It writes `brief.md` with `status: draft`.
3. When a brief is written, launch `claim-checker` for that talk folder as a separate Task (fresh
   context; do not pass it the writer's output or reasoning, only the folder path). It returns a
   report and has no write access. Save its report verbatim to `vault/talks/<talk_id>/check.md`.
4. If the check says `Result: FAIL`, launch `brief-writer` once more with the folder path and the
   instruction "Fix only the problems listed in check.md; remove a claim rather than weaken a
   citation." Then run `claim-checker` again and overwrite `check.md`. Do not loop further; a brief
   that still fails stays a draft and is reported.
5. Report per talk: confidence, lenses chosen (or "no clear fit"), check result, number of problems.
   Remind Matt that he reviews each brief and sets `status: reviewed` and `reviewed_by` himself.
