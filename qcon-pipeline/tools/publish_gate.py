#!/usr/bin/env python3
"""Publish gate for the shareable kb/ repo (architecture.md section 8).

    python tools/publish_gate.py            # checks kb/ against vault/; exit 0 = pass, 1 = fail

Fails the publish when any file under kb/:
  - has an audio or video extension (session audio, reflections: never shared);
  - is raw capture data (timeline.jsonl, events.jsonl, manifest.json, notes.md, refs.json,
    talk.json, any .jsonl) or a transcript;
  - has front matter with `visibility: private`, or a `status` other than reviewed/published
    (talk briefs under kb/talks/ must have front matter with one of those);
  - cites a permitted-audio mark such as [A 23:10];
  - names or belongs to a private talk (all its bundles private: unconference, social,
    ad hoc, hallway), including slide assets under kb/assets/slides/<talk_id>/;
  - ships a slide photo that no brief cites.
Warns (does not fail) on slide photos over 1 MB and on paths that point into the vault.

Standard library; uses PyYAML for front matter when installed.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:  # pragma: no cover
    yaml = None

AUDIO_VIDEO_EXT = {".m4a", ".mp3", ".wav", ".aac", ".caf", ".flac", ".ogg", ".opus", ".aiff", ".aif",
                   ".wma", ".mp4", ".mov", ".m4v", ".webm", ".mkv", ".avi"}
RAW_NAMES = {"timeline.jsonl", "events.jsonl", "manifest.json", "notes.md", "refs.json", "talk.json",
             "collector.json", "ingest-report.json"}
OK_STATUS = {"reviewed", "published"}
AUDIO_MARK = re.compile(r"\[A\s*\d{1,3}:\d{2}(?::\d{2})?\s*\]")
SLIDE_MARK = re.compile(r"\[(S\d{2,3})\]")
PRIVATE_PREFIXES = ("adhoc-", "unassigned-", "unconference-")
TEXT_EXT = {".md", ".markdown", ".txt", ".yaml", ".yml", ".json", ".html", ".csv"}


@dataclass
class Finding:
    level: str  # FAIL or WARN
    path: str
    message: str


def front_matter(text: str) -> dict | None:
    if not text.startswith("---"):
        return None
    m = re.match(r"^---\s*\n(.*?)\n---\s*(\n|$)", text, re.S)
    if not m:
        return None
    body = m.group(1)
    if yaml is not None:
        try:
            data = yaml.safe_load(body)
            return data if isinstance(data, dict) else {}
        except yaml.YAMLError:
            pass
    data = {}
    for line in body.splitlines():
        mm = re.match(r"^([A-Za-z_][\w-]*):\s*(.*?)\s*(#.*)?$", line)
        if mm:
            data[mm.group(1)] = mm.group(2).strip().strip("'\"") or None
    return data


def private_talks(vault: Path) -> set[str]:
    """Talk ids whose captures are private (talk.json from ingest)."""
    out: set[str] = set()
    talks = vault / "talks"
    if talks.exists():
        for tj in talks.glob("*/talk.json"):
            try:
                info = json.loads(tj.read_text(encoding="utf-8"))
            except ValueError:
                continue
            if info.get("all_bundles_private") or info.get("visibility") == "private":
                out.add(tj.parent.name)
            elif (info.get("talk") or {}).get("kind") in ("unconference", "social", "adhoc"):
                out.add(tj.parent.name)
    return out


def check(kb: Path, vault: Path) -> list[Finding]:
    findings: list[Finding] = []
    private = private_talks(vault)
    cited: dict[str, set[str]] = {}  # talk_id -> slide refs cited by its brief

    files = [p for p in kb.rglob("*") if p.is_file() and ".git" not in p.relative_to(kb).parts
             and p.name not in (".gitkeep", ".gitignore", ".gitattributes")]
    texts: dict[Path, str] = {}
    for p in files:
        rel = p.relative_to(kb).as_posix()
        name = p.name.lower()
        if p.suffix.lower() in AUDIO_VIDEO_EXT:
            findings.append(Finding("FAIL", rel, "audio or video file; raw audio is never shared"))
            continue
        if name in RAW_NAMES or p.suffix.lower() == ".jsonl":
            findings.append(Finding("FAIL", rel, "raw capture data; only reviewed briefs are shared"))
            continue
        if "transcript" in name or ({"voice", "audio"} & set(p.relative_to(kb).parts)):
            findings.append(Finding("FAIL", rel, "transcript or voice/audio folder; never shared"))
            continue
        if p.suffix.lower() in TEXT_EXT:
            try:
                texts[p] = p.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                findings.append(Finding("WARN", rel, "not UTF-8 text; not checked"))

    for p, text in texts.items():
        rel = p.relative_to(kb).as_posix()
        fm = front_matter(text)
        under_talks = p.relative_to(kb).parts[0] == "talks" and p.suffix.lower() == ".md"
        if under_talks:
            if fm is None:
                findings.append(Finding("FAIL", rel, "talk brief without front matter"))
            elif fm.get("status") not in OK_STATUS:
                findings.append(Finding("FAIL", rel, f"status is {fm.get('status')!r}; must be reviewed or published"))
        if fm is not None:
            if str(fm.get("visibility", "")).lower() == "private":
                findings.append(Finding("FAIL", rel, "front matter says visibility: private"))
            if "status" in fm and fm.get("status") not in OK_STATUS and not under_talks:
                findings.append(Finding("FAIL", rel, f"status is {fm.get('status')!r}; must be reviewed or published"))
            tid = fm.get("talk_id")
            if tid:
                cited.setdefault(str(tid), set()).update(SLIDE_MARK.findall(text))
                if tid in private or str(tid).startswith(PRIVATE_PREFIXES):
                    findings.append(Finding("FAIL", rel, f"talk {tid} is private (Code of Conduct)"))
        if AUDIO_MARK.search(text):
            findings.append(Finding("FAIL", rel, "cites a session-audio mark [A mm:ss]; audio is never a public source"))
        for tid in private:
            if re.search(rf"(?<![\w-]){re.escape(tid)}(?![\w-])", text):
                if not (fm and fm.get("talk_id") == tid):  # already reported above
                    findings.append(Finding("FAIL", rel, f"references private talk {tid}"))
        if re.search(r"vault/(raw|talks)/", text):
            findings.append(Finding("WARN", rel, "mentions a vault path; links will not resolve in kb"))

    slides = kb / "assets" / "slides"
    if slides.exists():
        for img in slides.rglob("*"):
            if not img.is_file() or img.name.startswith("."):
                continue
            rel = img.relative_to(kb).as_posix()
            tid = img.parent.name
            if tid in private or tid.startswith(PRIVATE_PREFIXES):
                findings.append(Finding("FAIL", rel, f"slide from private talk {tid}"))
                continue
            if img.stem not in cited.get(tid, set()):
                findings.append(Finding("FAIL", rel, f"not cited as [{img.stem}] by the brief for {tid}"))
            if img.stat().st_size > 1_000_000:
                findings.append(Finding("WARN", rel, "over 1 MB; downscale before publishing"))
    return findings


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    root_default = Path(__file__).resolve().parent.parent
    ap.add_argument("--kb", type=Path, default=root_default / "kb")
    ap.add_argument("--vault", type=Path, default=root_default / "vault")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    if not args.kb.exists():
        print(f"error: {args.kb} does not exist", file=sys.stderr)
        return 1
    findings = check(args.kb, args.vault)
    fails = [f for f in findings if f.level == "FAIL"]
    if args.json:
        print(json.dumps([f.__dict__ for f in findings], indent=1))
    else:
        for f in findings:
            print(f"{f.level}  {f.path}: {f.message}")
        print(f"\npublish gate: {'FAIL' if fails else 'PASS'} "
              f"({len(fails)} failures, {len(findings) - len(fails)} warnings)")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
