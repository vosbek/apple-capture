# QCon SF 2026 schedule dataset: notes

Retrieved 2026-11-10 with WebFetch from qconsf.com: the schedule, speakers index, training index, all 18 track pages, about 120 speaker and track-host pages, and the keynote pages plus a few presentation pages. Nothing was blocked except `/users/abhinavsinha` (robots.txt disallows it; `/speakers/abhinavsinha` worked) and `/speakers/catswetel` (client error). The site says the schedule is subject to change.

## Coverage

| | Captured | Listed on site |
|---|---|---|
| Sessions (keynote/talk/unconference/sponsored/training) | 119 | 119 on /schedule/nov2026 (excluding meals, breaks, socials) |
| - keynotes | 4 | 4 |
| - talks (12 curated tracks) | 61 (+1 "Speaker TBA": testing-verification-code-generating-agents) | 62 |
| - sponsored talks with content | 24 | 24 |
| - sponsored placeholders ("details coming soon") | 9 (type `other`) | 9 |
| - unconferences | 6 (type `other`) | 6 |
| - training/certification | 14 | 14 |
| Speakers | 127 | 124 unique on /speakers/nov2026 |
| Tracks | 18 (12 curated + 6 sponsored) | 18 |

Speaker count, reconciled: the 124 on the index include 3 program-committee-only people (Erin Doyle, Haley Tucker, Thomas Betts). They give no sessions, so I left them out. I added 6 people who appear on session pages but not on the index: Cat Swetel (Nubank), RJ Atwal (Confluent), Meghana Madhyastha (Parasail), Vimal Kumar (Juspay), Christian Weber (Harness) and Alex Berkoff (Azul). The 11 track hosts with no talk are included with `session_ids: []` and `roles: ["track_host"]`. Vanessa Huerta Granda is both a host and a speaker.

Social links come only from QCon pages. The schema has only github, linkedin, x and website, so Bluesky, Mastodon and YouTube links were dropped. A Medium or newsletter link was used as `website` when no personal site was listed.

## Gaps and caveats

- **Not yet published:** 9 sponsored sessions (sponsored-session-3/4/5/7/8/9/10/11/12) and the Mon 17:05 "Testing & Verification for Code-Generating Agents" talk have no speaker. They have no abstract either, except a placeholder note on the 9 sponsored sessions.
- **No bio on QCon:** Cat Swetel, Alex Berkoff, Andrew Finch, Rachael Wonnacott, Baruch Sadogursky.
- **Rooms:** the Tue and Wed morning keynotes and the Wed evening keynote list no room, so `room` is null. It is probably Grand Ballroom, like Monday's, but that is not confirmed.
- **End times** are worked out from published durations: talks 50 min, morning keynotes 1h10, evening keynote 45 min, half-day trainings 3h, full-day trainings 09:00–16:00.
- **`video_expected`** (an added field): `false` means the schedule says "No Video Available" (33 sessions: most sponsored talks, all unconferences, and the Roblox and Airbnb talks). `true` means a keynote or talk with no such label, which is inferred, not confirmed. `null` means a training or an unlabeled placeholder. The labels came from a model reading the schedule page. The sponsored track pages show no labels, so treat this field as indicative only.
- **Unconference slugs** come from the track pages (`unconference-<track>`). The schedule links all of them to /unconference.
- **Conflicts resolved** (schedule and speaker page disagree):
  - Abhinav Sinha: his speaker page says 13:35, but the schedule and the track page say 10:35. I used 10:35.
  - Ammar Khaku: one page says 13:35. I used 15:55, which the schedule, the track page and his co-speaker's page all give.
  - Em Ruppe: the speaker page header says Chime, the schedule says Twilio. I used Chime.
  - Ryan Brown: the schedule says Crunchyroll, the speaker page says Render. I used Render.
  - Kent Beck: I used "Programmer, Studio Beck" from his speaker page.
  - Sepehr Khosravi: his speaker page says Coinbase, the index says OneKit. I used Coinbase.
  - Courtney Nash: the index says Forrester, the bio says The VOID. I used Forrester.
  - Grey Newell: his current employer is unnamed, so `company` is null.
  - These companies appear only on the schedule page: Rachael Wonnacott (Capital Group), Jyothi Nookula (DataRobot), Christian Weber (Harness), Baruch Sadogursky (Port.io).
- **Stale sponsored track pages:** the sponsored track pages are older than /schedule/nov2026 (for example, they list Heather Downing for the Yugabyte talk, while the schedule and speaker page say Hari Sunder). The schedule and speaker pages were used.
- `https://qconsf.com/llms/nov2026.md` was checked. It gives only an overview of tracks and trainings, with no per-session data. It also gives a different slug for the AI-Assisted Coding class (`sold-out-...`); I used the slug on the live training index.
- Meals, breaks, the socials and the Women & Allies lunch (qconsf.com/events/WIT2026) are not included as sessions.

## Tracks

**Mon Nov 16**
- `architectures-youve-always-wondered-about` (host Daniela Miao, Momento): real architectures and the trade-offs behind them (Valkey, Nubank, Cerebras, Roblox, voice agents). Ballroom BC.
- `guardrails-safety-nets-evals-new-landscape` (host Tanya Reilly, Datadog): evals, feedback loops and guardrails for AI systems (Uber, Airbnb, Datadog, Google). Ballroom A.
- `modern-api-design-humans-and-agents` (host Krys Flores, Crunchyroll): APIs that both humans and agents can use safely (Imprint, Duolingo, Netflix). Pacific DEKJ.
- `resilience-engineering-everything-fails-all-time` (host Vanessa Huerta Granda, Enova): designing for failure, incidents and severity, saturation. Seacliff ABC.
- `sponsored-solution-track-i` (Pacific LM) and `sponsored-solution-track-ii` (Marina): vendor talks.

**Tue Nov 17**
- `distributed-systems-production` (host Vidhya Arvind, Netflix): KV compression, object storage, Valkey autoscaling, Postgres for agents. Ballroom BC.
- `engineering-ai-systems` (host Melanie Zhao, BlackRock): production agents, evals, OpenAI, LinkedIn ranking, Netflix ML serving. Ballroom A.
- `staff-engineering-skills` (host Javier Fernandez-Ivern, Netflix): alignment, AI leverage and onboarding for Staff+ engineers. Pacific DEKJ.
- `data-platforms-reimagined` (host Adi Polak, Confluent): PySpark, Iceberg V4, streaming query layers, data products. Seacliff ABC.
- `sponsored-solution-track-iii` (Pacific LM / L-O) and `sponsored-solution-track-v` (Marina): vendor talks.

**Wed Nov 18**
- `architecting-agents-beneath-loop` (host Julie Amundson): the agent SDLC, observability MCP, GPU agents, agent memory, prompt debt. Ballroom BC.
- `engineering-developer-experience` (host Ankit Jain, Aviator): Kent Beck, Google, Netflix, Margaret-Anne Storey, MongoDB on DevEx in the AI era. Ballroom A.
- `real-world-platform-engineering` (host Daniel Bryant, Syntasso): platform pillars, LinkedIn compute, adoption, the Netflix Aurora migration. Pacific DEKJ.
- `code-beyond-engineers-engineering-teams` (host Suhail Patel, OpenAI): builders beyond engineering, verification, ownership of production. Seacliff ABC.
- `sponsored-solution-track-iv` (Pacific LM) and `sponsored-solution-track-vi` (Marina): vendor talks.

**Thu Nov 19 – Fri Nov 20:** training, with no track (`track_id: null`). There are 9 half-day sessions on Thursday plus the 3-hour InfoQ Certified Architect workshop (Garden A), and 4 full-day sessions on Friday.
