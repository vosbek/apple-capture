---
description: Copy reviewed briefs and their cited slides into kb/, run the publish gate, commit (never push)
argument-hint: "<talk_id | all-reviewed>"
allowed-tools: Read, Write, Glob, Grep, Bash(python3 tools/publish_gate.py:*), Bash(python3 tools/downscale.py:*), Bash(git -C kb status:*), Bash(git -C kb add:*), Bash(git -C kb commit:*), Bash(git -C kb init:*), Bash(git -C kb diff:*), Bash(mkdir:*)
---

Publish to the shareable repo: $ARGUMENTS

Preconditions, checked per talk; skip and report a talk that fails any:
- `vault/talks/<id>/brief.md` has `status: reviewed` (or `published`) and `reviewed_by` set.
- `talk.json` has `visibility: shareable` and the brief's front matter says `visibility: shareable`.
- `check.md` exists and says `Result: PASS`.

Steps:
1. If `kb/.git` does not exist: copy `templates/kb/*` into `kb/` (README.md, actions.md, SOURCES.md)
   if they are missing, then run `git -C kb init` once. `kb/` is its own repository; the outer
   project ignores it.
2. For each talk: copy the brief to `kb/talks/<date>/<talk_id>.md` (date from front matter), with
   `status: published` in the copy, and set `status: published` in the vault brief too.
   In the copy, make slide references links to `../../assets/slides/<talk_id>/S07.jpg` the first
   time each is cited, credit the speaker under the first image ("Slide photo: <speaker>, QCon SF 2026"),
   and mark the official video link as needing a QCon login. Remove nothing else.
3. For every `[Sxx]` the brief cites, run
   `python3 tools/downscale.py vault/talks/<id>/photos/Sxx.jpg kb/assets/slides/<id>/Sxx.jpg`.
   Copy no other photo.
4. Speakers: write or update `kb/speakers/<name-slug>.md` from `research/speaker.md`, keeping only
   statements with `[R#]` marks and listing those sources at the bottom with URL and fetch date.
5. Themes, actions, summary: copy `vault/themes/*.md` with `status: reviewed` to `kb/themes/`,
   `vault/actions.md` to `kb/actions.md` (only rows whose source talk is published), and
   `vault/trip-summary.md` (if reviewed) into `kb/README.md` above "How to read this repo".
6. Run `python3 tools/publish_gate.py`. If it fails, fix the cause by removing the offending file or
   passage from `kb/` (never by editing the gate, never by changing a brief's visibility), and run it
   again. Report every failure and what you removed.
7. When the gate passes: `git -C kb add -A` and `git -C kb commit -m "Publish: <talk ids>"`.
   Never `git push`. Show `git -C kb status` and tell Matt the commit is ready for him to push.
