#!/usr/bin/env python3
"""One table: every captured talk and how far it is through the pipeline (for /qcon-status).

    python tools/status.py [--root DIR]

Columns: captures, transcripts, slides.md, research, brief status, check result, published,
official video. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def brief_status(path: Path) -> str:
    if not path.exists():
        return "-"
    m = re.search(r"^status:\s*([a-z]+)", path.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else "?"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = ap.parse_args(argv)
    talks = args.root / "vault" / "talks"
    kb_talks = args.root / "kb" / "talks"
    published = {p.stem for p in kb_talks.rglob("*.md")} if kb_talks.exists() else set()
    rows = []
    for d in sorted(p for p in talks.iterdir() if p.is_dir()) if talks.exists() else []:
        tj = d / "talk.json"
        if not tj.exists():
            continue
        info = json.loads(tj.read_text(encoding="utf-8"))
        c = info["counts"]
        voices = list((d / "voice").glob("*.m4a")) if (d / "voice").exists() else []
        transcribed = sum(1 for v in voices if v.with_suffix(".txt").exists())
        check = d / "check.md"
        check_res = "-"
        if check.exists():
            check_res = "pass" if re.search(r"^Result:\s*PASS", check.read_text(encoding="utf-8"), re.M) else "fail"
        video = "none expected" if info["talk"].get("no_video") else "Dec 21"
        if (d / "reconcile.md").exists():
            video = "reconciled"
        rows.append([d.name[:48], f"{c['photo']}/{c['moment']}/{c['note']}/{c['voice']}",
                     f"{transcribed}/{len(voices)}", "yes" if (d / "slides.md").exists() else "-",
                     "yes" if (d / "research" / "sources.yaml").exists() else "-",
                     brief_status(d / "brief.md"), check_res, "yes" if d.name in published else "-",
                     info["visibility"], video])
    head = ["talk", "S/M/N/V", "transcr", "slides", "research", "brief", "check", "kb", "visibility", "video"]
    print("| " + " | ".join(head) + " |")
    print("|" + "---|" * len(head))
    for r in rows:
        print("| " + " | ".join(r) + " |")
    print(f"\n{len(rows)} talks; {sum(1 for r in rows if r[-1] == 'none expected')} with no official video expected.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
