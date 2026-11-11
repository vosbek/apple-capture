#!/usr/bin/env python3
"""Turn moments and notes into official-video timestamps (architecture.md section 10).

One alignment point is enough: a slide you photographed and the video time it appears at.

    python tools/reconcile.py harness-new-operating-system \
        --video-url "https://qconsf.com/..." --photo S07 --at 12:34

    video_offset_ms = video_time(S07) - talk_ms(S07)
    video_time(x)   = talk_ms(x) + video_offset_ms

Writes vault/talks/<id>/reconcile.md and, if brief.md exists, updates its `official_video`
front matter and the "## Watch list" section. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def parse_clock(s: str) -> int:
    parts = [int(p) for p in s.split(":")]
    secs = 0
    for p in parts:
        secs = secs * 60 + p
    return secs * 1000


def fmt_clock(ms: int) -> str:
    s = max(0, ms) // 1000
    h, rem = divmod(s, 3600)
    return f"{h}:{rem // 60:02d}:{rem % 60:02d}" if h else f"{rem // 60}:{rem % 60:02d}"


TAG_LABEL = {"idea": "Idea", "for_us": "For us", "follow_up": "Follow up", "question": "Question"}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("talk_id")
    ap.add_argument("--video-url", required=True)
    ap.add_argument("--photo", required=True, help="slide ref seen in the video, e.g. S07")
    ap.add_argument("--at", required=True, help="video time where that slide appears, mm:ss or h:mm:ss")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = ap.parse_args(argv)

    d = args.root / "vault" / "talks" / args.talk_id
    events = [json.loads(ln) for ln in (d / "timeline.jsonl").read_text(encoding="utf-8").splitlines() if ln.strip()]
    anchor = next((e for e in events if e.get("ref") == args.photo), None)
    if anchor is None:
        print(f"error: {args.photo} not found in {args.talk_id}", file=sys.stderr)
        return 1
    offset = parse_clock(args.at) - anchor["talk_ms"]
    photos = [e for e in events if e["type"] == "photo"]

    rows = []
    for e in events:
        if e["type"] not in ("moment", "note"):
            continue
        nearest = min(photos, key=lambda p: abs(p["talk_ms"] - e["talk_ms"]), default=None)
        what = "Moment" + (f", {TAG_LABEL.get(e.get('tag'), e.get('tag'))}" if e.get("tag") else "") \
            if e["type"] == "moment" else f"Note: {e.get('text', '')}"
        rows.append(f"- {fmt_clock(e['talk_ms'] + offset)} [{e['ref']}] {what}"
                    + (f" (nearest slide [{nearest['ref']}])" if nearest else ""))
    watch = "\n".join(rows) if rows else "- No moments or notes were captured."
    (d / "reconcile.md").write_text(
        f"# Reconcile: {args.talk_id}\n\nVideo: {args.video_url} (QCon login required)\n"
        f"Alignment: [{args.photo}] at {args.at} in the video; video_offset_ms = {offset}\n\n"
        f"## Watch list\n{watch}\n", encoding="utf-8")

    brief = d / "brief.md"
    if brief.exists():
        text = brief.read_text(encoding="utf-8")
        text = re.sub(r"^official_video:.*$",
                      f"official_video: {{ status: available, url: {args.video_url}, video_offset_ms: {offset} }}",
                      text, count=1, flags=re.M)
        text = re.sub(r"(## Watch list\n)(.*?)(?=\n## |\Z)", lambda m: m.group(1) + watch + "\n",
                      text, count=1, flags=re.S)
        brief.write_text(text, encoding="utf-8")
    print(f"video_offset_ms = {offset}; {len(rows)} entries written to {d.name}/reconcile.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
