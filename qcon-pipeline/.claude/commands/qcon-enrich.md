---
description: Research speaker, company, repos and docs for one talk or all talks, with cached sources
argument-hint: "<talk_id | all>"
allowed-tools: Task, Read, Glob, Grep
---

Enrich: $ARGUMENTS

1. Resolve the talk list (`all` = every talk folder with `slides.md`). Skip talks whose
   `talk.json` has `visibility: private` unless Matt names them explicitly; even then, research only
   public facts about named products and repos, never the people in a private conversation.
2. For each talk, in parallel, launch:
   - `speaker-researcher` with the talk folder path. It writes `research/speaker.md`,
     `research/company.md`, and adds records to `research/sources.yaml` with cached text in
     `research/cache/R<n>.md`. It also checks InfoQ for a write-up of this talk.
   - `repo-inspector` with the talk folder path, if `slides.md` or `notes.md` names any repository,
     library, product or tool. It writes `research/repos.md` and adds sources the same way.
   Run the two for the same talk one after the other (speaker-researcher first), because both
   append to `sources.yaml` and must not number two sources the same.
3. Re-runnable: subagents fetch only sources that are missing or whose `fetched_utc` is older than
   14 days. Tell them today's date.
4. Report per talk: sources added (by tier), vendor sources, InfoQ write-up found (yes/no + URL),
   repos inspected, anything that could not be fetched.
