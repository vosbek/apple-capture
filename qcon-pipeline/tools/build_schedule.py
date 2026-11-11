#!/usr/bin/env python3
"""Build the Collector schedule (collector.schedule/1) from the QCon SF dataset.

architecture.md section 4.8. Standard library only.

    python tools/build_schedule.py vault/schedule/qconsf-2026-schedule.json \
        -o vault/schedule/schedule.json --app ../QConCollector/Resources/schedule.json

Fails loudly (exit 1) on a session with no id or no start time.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None  # type: ignore

SCHEMA = "collector.schedule/1"
EVENT_ID = "qconsf-nov2026"
SOURCE = "https://qconsf.com/schedule/nov2026"


class ScheduleError(Exception):
    pass


def conference_tz(name: str):
    """IANA zone; falls back to PST (UTC-8), which is correct for Nov 16-20 2026.
    On Windows Python, `pip install tzdata` gives the real zone."""
    if ZoneInfo is not None:
        try:
            return ZoneInfo(name)
        except Exception:
            pass
    print(f"warning: time zone {name} not found; using UTC-08:00 (pip install tzdata)", file=sys.stderr)
    return timezone(timedelta(hours=-8))


def kind_for(session: dict) -> str:
    t = session.get("type")
    sid = session.get("id") or ""
    track = session.get("track_id") or ""
    if t == "keynote":
        return "keynote"
    if t == "training":
        return "training"
    if t == "talk":
        return "sponsored" if track.startswith("sponsored-solution-track") else "presentation"
    if t == "other":
        return "unconference" if sid.startswith("unconference-") else "sponsored"
    raise ScheduleError(f"session {sid!r}: unknown type {t!r}")


def local_iso(day: str, hhmm: str, tz) -> str:
    d = date.fromisoformat(day)
    h, m = (int(x) for x in hhmm.split(":"))
    return datetime.combine(d, time(h, m), tzinfo=tz).isoformat()


def build(dataset: dict, generated_utc: str | None = None) -> dict:
    event = dataset.get("event") or {}
    tz_name = event.get("timezone") or "America/Los_Angeles"
    tz = conference_tz(tz_name)
    speakers = {s["id"]: s for s in dataset.get("speakers", [])}
    tracks = {t["id"]: t for t in dataset.get("tracks", [])}

    talks = []
    problems = []
    for s in dataset.get("sessions", []):
        sid = s.get("id")
        if not sid:
            problems.append(f"session with title {s.get('title')!r} has no id")
            continue
        if not s.get("start") or not s.get("day"):
            problems.append(f"session {sid!r} has no start time")
            continue
        start = local_iso(s["day"], s["start"], tz)
        end_hhmm = s.get("end")
        if end_hhmm:
            end = local_iso(s["day"], end_hhmm, tz)
        else:  # not expected in the dataset; 50 minutes is the talk default
            end = (datetime.fromisoformat(start) + timedelta(minutes=50)).isoformat()
        kind = kind_for(s)
        sp = []
        for spk_id in s.get("speaker_ids") or []:
            p = speakers.get(spk_id)
            if not p:
                problems.append(f"session {sid!r}: unknown speaker id {spk_id!r}")
                continue
            sp.append({
                "name": p.get("name"),
                "company": p.get("company"),
                "role": p.get("title"),
                "speaker_url": p.get("profile_url"),
            })
        track_id = s.get("track_id")
        track_name = tracks.get(track_id, {}).get("name") if track_id else None
        talks.append({
            "talk_id": sid,
            "kind": kind,
            "title": s.get("title") or sid,
            "speakers": sp,
            "track": track_name,
            "room": s.get("room"),
            "start": start,
            "end": end,
            "url": s.get("url"),
            "no_video": s.get("video_expected") is False,
            "private_by_default": kind == "unconference",
        })
    if problems:
        raise ScheduleError("; ".join(problems))
    talks.sort(key=lambda t: (t["start"], t["track"] or "~", t["talk_id"]))
    return {
        "schema": SCHEMA,
        "event": EVENT_ID,
        "tz": tz_name,
        "generated_utc": generated_utc or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": SOURCE,
        "talks": talks,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dataset", type=Path, help="qconsf-2026-schedule.json")
    ap.add_argument("-o", "--out", type=Path, required=True, help="where to write schedule.json")
    ap.add_argument("--app", type=Path, help="also copy to the app's Resources/schedule.json")
    args = ap.parse_args(argv)
    try:
        result = build(json.loads(args.dataset.read_text(encoding="utf-8")))
    except ScheduleError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    text = json.dumps(result, indent=1, ensure_ascii=False) + "\n"
    for target in [args.out] + ([args.app] if args.app else []):
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        print(f"wrote {target} ({len(result['talks'])} talks)")
    no_speaker = [t["talk_id"] for t in result["talks"] if not t["speakers"]]
    print(f"{sum(t['no_video'] for t in result['talks'])} marked no_video; "
          f"{len(no_speaker)} without a speaker yet (shown as 'Speaker to be announced')")
    return 0


if __name__ == "__main__":
    sys.exit(main())
