---
description: Write cross-talk themes, the actions table and the trip summary from reviewed briefs
allowed-tools: Read, Write, Glob, Grep
---

Synthesize across talks (architecture 7.4). Run this once, after Matt has reviewed the briefs.

Inputs: every `vault/talks/*/brief.md` with `status: reviewed` or `published` and
`visibility: shareable`. Ignore drafts and private briefs entirely; list how many were ignored.

1. Themes, `vault/themes/<slug>.md`: an idea that appears in three or more of those briefs. For each:
   front matter (`schema: qcon.theme/1`, `title`, `talks: [talk_ids]`, `lens`, `status: draft`,
   `visibility: shareable`); then where speakers agreed, where they disagreed, and what it means for
   one lens. Every claim cites briefs as `[talk_id]` (and may repeat the brief's own mark, e.g.
   `[harness-new-operating-system S07]`); never cite raw captures directly. Do not create a theme
   from fewer than three talks.
2. Actions, `vault/actions.md`: every "First step" from every included brief, one row each:
   Action | Lens | Source talk | Size | Suggested owner | Status (`proposed`). Keep the brief's wording.
3. Trip summary, `vault/trip-summary.md` (becomes `kb/README.md` on publish): one page with what we
   went to learn, the five things worth acting on (each pointing at a brief or theme), what was
   over-hyped (with the brief that shows why), and where to start reading. Lean prose.
4. Report: themes written (with talk counts), actions count, and briefs that were excluded.

Matt reviews themes and the summary and sets their `status: reviewed` before `/qcon-publish`.
