# QCon SF 2026 workspace

This folder turns QCon Collector bundles into sourced briefs and a shareable knowledge repo.
Contract: `docs/architecture.md` sections 4-10 (UI: `docs/design-spec.md`). Commands are in
`.claude/commands/`, subagents in `.claude/agents/`, deterministic work in `tools/`.

## Two zones, one gate

- `vault/` is PRIVATE: raw bundles, photos, notes, reflections, audio, research cache, draft briefs.
  It never gets a git remote and nothing in it is pasted into web searches.
- `kb/` is SHAREABLE and is its own git repository. Only `/qcon-publish` writes to it, and only
  after `tools/publish_gate.py` passes. Never `git push`; Matt pushes.
- `inbox/` holds zips as downloaded. `vault/raw/` is read-only: never edit a raw bundle.

## Rules for every command and subagent

1. Scripts first. Ingest, status, reconcile, downscale and the gate are scripts; run them, do not
   reimplement them. If a script is wrong, say so and stop rather than working around it.
2. Citation discipline (architecture 7.1). A sentence about what the speaker said carries a capture
   mark (`[S07]` slide, `[N3]` note, `[M4]` moment, `[V1]` reflection). A fact about a speaker, company
   or repo carries a source mark (`[R2]`). Inference starts with "Our read:". Refs come from
   `timeline.jsonl` / `notes.md` / `photos/index.json`; never invent or renumber them.
3. The dataset's abstracts and bios (`vault/schedule/qconsf-2026-schedule.json`) are paraphrases. Never
   quote them and never present them as what the speaker said; fetch the talk page instead.
4. Vendor numbers are "the vendor's claim", never a finding.
5. Privacy. Talks whose `talk.json` says `visibility: private` (unconference, social, ad hoc, hallway)
   stay private: their briefs get `visibility: private` and are never published. Session audio,
   reflection audio and any transcript are never published. Do not put note or reflection text into
   web search queries; search with names of products, repos, people and companies only.
6. Where captures are thin, write less. Do not fill gaps from the abstract.
7. Talks are independent: fan out one subagent per talk (in parallel) for read, enrich and brief.

## Layout

```
inbox/                     zips as downloaded; inbox/fallback/ for Camera/Shortcut/Voice Memos files
vault/raw/<date>/<bundle>/ bundles as exported (read-only)
vault/schedule/            dataset + built schedule.json
vault/lenses.yaml          initiatives to read talks against (copy templates/lenses.example.yaml; private)
vault/talks/<talk_id>/     timeline.jsonl talk.json notes.md refs.json photos/ voice/ audio/
                           slides.md research/{sources.yaml,cache/,speaker.md,company.md,repos.md}
                           brief.md check.md reconcile.md
vault/themes/ vault/actions.md vault/trip-summary.md
kb/                        README.md actions.md SOURCES.md talks/<date>/<talk_id>.md themes/ speakers/
                           assets/slides/<talk_id>/S07.jpg
templates/brief.md         the brief template (architecture 7.2)
templates/kb/              starting README, actions and SOURCES for kb/
templates/lenses.example.yaml  example lenses; copy to vault/lenses.yaml and make it yours
tools/                     ingest.py build_schedule.py transcribe.py publish_gate.py status.py
                           reconcile.py downscale.py
```

Python: `python3` in WSL (or `python` on Windows), 3.11+. Tests: `python3 -m pytest -q`.
