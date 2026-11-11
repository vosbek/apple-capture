# QCon Collector

An offline iPhone and iPad app for capturing conference talks (slide photos, moment markers, notes and your own voice reflections), plus a Claude Code pipeline that turns the captures into cited briefs a team can read.

Built for QCon San Francisco 2026 (Nov 16–20). Overview and onboarding: **https://vosbek.github.io/apple-capture/**

## How it works

1. **Capture** on the phone or iPad: one bundle per talk per device, saved as you go, with no network calls.
2. **Export** each day as a zip from the share sheet.
3. **Ingest** on the PC: `qcon-pipeline/tools/ingest.py` merges devices into one timeline per talk.
4. **Enrich and brief** in Claude Code: speaker, company and repo research, then one cited brief per talk.
5. **Publish** reviewed briefs only, into a separate `kb/` repo, behind a gate that blocks private material.

The app does **not** record sessions, because QCon's [terms](https://qconsf.com/terms-conditions) forbid it. Moments carry their offset from the talk's start, so after the official recordings arrive (Dec 21 for ticket holders) `/qcon-reconcile` turns them into video timestamps.

## Quick start (Windows PC, no Mac)

```powershell
# admin PowerShell, in the repo folder
powershell -ExecutionPolicy Bypass -File .\setup\windows\1-windows-setup.ps1
```
```bash
# Ubuntu (WSL), in the repo folder
bash setup/windows/2-wsl-setup.sh
xtool setup                      # free Apple ID + the Xcode 27.1 .xip
mkdir -p ~/ios && rsync -a --exclude .build --exclude xtool QConCollector/ ~/ios/QConCollector/
cd ~/ios/QConCollector && xtool dev build && xtool dev
```

See [BUILD.md](BUILD.md) for the full evening-by-evening plan, device setup, likely compile errors and the no-app fallback.

## Layout

| Path | What it is |
|---|---|
| `QConCollector/` | The app: xtool SwiftPM project, SwiftUI, iOS 17+. Not yet compiled; see BUILD.md. |
| `qcon-pipeline/` | Ingest, publish gate, schedule builder, Claude Code commands and agents. `python3 -m pytest -q` runs the tests. |
| `qcon-pipeline/docs/` | Architecture, UI spec and the research behind them. |
| `setup/windows/` | WSL, Swift, xtool and USB passthrough scripts. |
| `docs/` | The GitHub Pages site: overview, onboarding and all screen designs. |

## Privacy

Your captures never belong in this repo. `qcon-pipeline/.gitignore` ignores everything under `inbox/`, `vault/` and `kb/` except the empty skeleton and the public schedule dataset. Your lenses (the initiatives briefs are read against) go in `vault/lenses.yaml`, copied from `templates/lenses.example.yaml`, and stay private. `kb/` is its own repository; push it wherever your team reads.

Schedule data is paraphrased from [qconsf.com](https://qconsf.com/schedule/nov2026). This is a personal tool, not affiliated with QCon or InfoQ.
