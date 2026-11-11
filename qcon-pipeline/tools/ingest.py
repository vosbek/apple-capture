#!/usr/bin/env python3
"""Ingest Collector bundles into the private vault (architecture.md section 5).

Deterministic, no model calls, no network. Python 3.11+, standard library
(Pillow is optional and only used to flag near-duplicate photos).

Normal mode
    python tools/ingest.py                      # every *.zip and folder in inbox/
    python tools/ingest.py inbox/collector_2026-11-16_iphone.zip  path/to/bundle-or-day-folder

    1. Copies each bundle to vault/raw/<date>/<bundle>/. A bundle already there is only
       replaced by a superset (its events.jsonl is a prefix of the new one); anything else
       goes to vault/raw/<date>/_conflicts/ and is reported. Raw bundles are otherwise
       never modified.
    2. Validates every raw bundle: drops a truncated last line, applies tag/edit/delete,
       rebuilds counts, reports clock jumps and skew.
    3. Groups bundles by talk_id (iPhone + iPad), merges by UTC time and writes
       vault/talks/<talk_id>/: timeline.jsonl, talk.json, notes.md, refs.json,
       photos/S01.jpg..., photos/index.json, voice/.

Fallback mode (architecture.md section 13: Camera + Shortcut + Voice Memos)
    python tools/ingest.py --fallback --notes inbox/fallback/notes.txt \
        --photos inbox/fallback/photos --voice inbox/fallback/voice

    Notes file: one line per capture, "<ISO time> | <text>". "TALK <slug or name>" starts
    a talk; empty text (or ".") is a moment; "idea", "for us", "follow up", "question" are tagged
    moments; anything else is a note. Photos are placed by EXIF time; voice memos by the
    talk name in the file name, else by file time. The result is written as synthetic
    bundles (device "fallback") and then merged exactly like app bundles.

Re-running is safe: talk folders are rebuilt from vault/raw each time, and the
S/N/M/V reference numbers already used by a brief are kept (refs.json).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import struct
import sys
import tempfile
import zipfile
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None  # type: ignore

UTC = timezone.utc
CONF_TZ_NAME = "America/Los_Angeles"
KNOWN_TYPES = {
    "session_open", "resume", "speaker_start", "photo", "moment", "note", "voice", "tag",
    "edit", "delete", "audio_permission", "audio_start", "audio_segment", "audio_gap",
    "audio_stop", "visibility", "session_close",
}
CAPTURE_TYPES = {"photo", "moment", "note", "voice", "audio_segment"}
REF_PREFIX = {"photo": "S", "note": "N", "moment": "M", "voice": "V"}
MEDIA_TYPES = {"photo", "voice", "audio_segment"}
TAG_WORDS = {"idea": "idea", "for us": "for_us", "follow up": "follow_up", "follow-up": "follow_up",
             "question": "question"}
PHOTO_EXT = {".jpg", ".jpeg", ".heic", ".png"}
AUDIO_EXT = {".m4a", ".mp3", ".wav", ".aac", ".caf"}


def conf_tz():
    if ZoneInfo is not None:
        try:
            return ZoneInfo(CONF_TZ_NAME)
        except Exception:
            pass
    return timezone(timedelta(hours=-8))  # PST, correct for Nov 16-20 2026


TZ = conf_tz()


# --------------------------------------------------------------------------- time helpers

def parse_ts(s: str | None) -> datetime | None:
    if not s or not isinstance(s, str):
        return None
    try:
        d = datetime.fromisoformat(s.strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=TZ)
    return d


def fmt_utc(d: datetime) -> str:
    d = d.astimezone(UTC)
    return d.strftime("%Y-%m-%dT%H:%M:%S.") + f"{d.microsecond // 1000:03d}Z"


def ms_between(a: datetime, b: datetime) -> int:
    """b - a in milliseconds."""
    return round((b - a).total_seconds() * 1000)


def fmt_offset(ms: int) -> str:
    sign = "-" if ms < 0 else "+"
    s = abs(ms) // 1000
    return f"{sign}{s // 60}:{s % 60:02d}"


def local_hhmm(d: datetime) -> str:
    return d.astimezone(TZ).strftime("%H%M")


def local_day(d: datetime) -> str:
    return d.astimezone(TZ).strftime("%Y-%m-%d")


# --------------------------------------------------------------------------- data classes

@dataclass
class Bundle:
    path: Path
    bundle_id: str
    date: str
    manifest: dict
    events: list[dict]
    problems: list[str] = field(default_factory=list)

    @property
    def device(self) -> str:
        dev = (self.manifest.get("device") or {}).get("label")
        if dev:
            return dev
        m = re.search(r"__([a-z0-9]+)$", self.path.name)
        return m.group(1) if m else "unknown"

    @property
    def talk(self) -> dict:
        return self.manifest.get("talk") or {}

    @property
    def talk_id(self) -> str:
        tid = self.talk.get("talk_id")
        if tid:
            return tid
        m = re.match(r"^\d{4}_(.+)__[a-z0-9]+$", self.path.name)
        return m.group(1) if m else self.path.name

    @property
    def t0(self) -> datetime | None:
        clock = self.manifest.get("clock") or {}
        return parse_ts(clock.get("t0_utc")) or parse_ts(self.talk.get("sched_start_utc"))

    @property
    def visibility(self) -> str:
        vis = self.manifest.get("visibility") or "shareable"
        for e in self.events:  # events.jsonl wins over the manifest
            if e.get("type") == "visibility" and e.get("value") in ("shareable", "private"):
                vis = e["value"]
        if self.talk.get("kind") in ("unconference", "social", "adhoc") and not any(
                e.get("type") == "visibility" for e in self.events):
            vis = "private"
        return vis


@dataclass
class Report:
    imported: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)
    conflicts: list[str] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    talks: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {"imported": self.imported, "skipped": self.skipped, "conflicts": self.conflicts,
                "problems": self.problems, "talks": self.talks}


# --------------------------------------------------------------------------- reading bundles

def read_events(path: Path, problems: list[str]) -> list[dict]:
    """Parse events.jsonl. A truncated last line is dropped; other bad lines are skipped."""
    if not path.exists():
        problems.append("events.jsonl missing")
        return []
    raw = path.read_bytes().decode("utf-8", errors="replace")
    lines = raw.split("\n")
    events: list[dict] = []
    last_index = max((i for i, ln in enumerate(lines) if ln.strip()), default=-1)
    for i, line in enumerate(lines):
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
            if not isinstance(obj, dict):
                raise ValueError("not an object")
        except ValueError:
            if i == last_index:
                problems.append("truncated last line dropped")
            else:
                problems.append(f"line {i + 1} is not valid JSON; skipped")
            continue
        events.append(obj)
    return events


def validate(bundle: Bundle) -> None:
    prev_seq = 0
    prev_mono = None
    dev = bundle.device
    good: list[dict] = []
    for e in bundle.events:
        missing = [k for k in ("seq", "id", "type", "ts_utc", "t_ms", "mono_ms") if k not in e]
        if missing:
            bundle.problems.append(f"event {e.get('id', '?')} missing {', '.join(missing)}; skipped")
            continue
        if parse_ts(e["ts_utc"]) is None:
            bundle.problems.append(f"event {e['id']} has an unreadable ts_utc; skipped")
            continue
        if not isinstance(e["seq"], int) or e["seq"] <= prev_seq:
            bundle.problems.append(f"event {e['id']}: seq {e['seq']} not increasing")
        prev_seq = e["seq"] if isinstance(e["seq"], int) else prev_seq
        if not str(e["id"]).startswith(dev + "-"):
            bundle.problems.append(f"event {e['id']}: id does not start with device label {dev!r}")
        if e["type"] not in KNOWN_TYPES:
            bundle.problems.append(f"event {e['id']}: unknown type {e['type']!r} (kept)")
        if e["type"] in MEDIA_TYPES and e.get("file") and not (bundle.path / e["file"]).exists():
            bundle.problems.append(f"event {e['id']}: file {e['file']} missing")
        if e.get("clock_jump_ms"):
            bundle.problems.append(f"event {e['id']}: wall clock jumped {e['clock_jump_ms']} ms")
        if prev_mono is not None and isinstance(e["mono_ms"], int) and e["mono_ms"] < prev_mono:
            bundle.problems.append(f"event {e['id']}: monotonic clock went backwards (device restart?)")
        prev_mono = e["mono_ms"] if isinstance(e["mono_ms"], int) else prev_mono
        good.append(e)
    bundle.events = good
    if not bundle.manifest:
        bundle.problems.append("manifest.json missing or unreadable; using folder name")


def load_bundle(path: Path, date_hint: str | None = None) -> Bundle:
    problems: list[str] = []
    manifest: dict = {}
    mpath = path / "manifest.json"
    if mpath.exists():
        try:
            manifest = json.loads(mpath.read_text(encoding="utf-8"))
        except ValueError:
            manifest = {}
    events = read_events(path / "events.jsonl", problems)
    bundle_id = manifest.get("bundle_id") or ""
    date = bundle_id[:10] if re.match(r"^\d{4}-\d{2}-\d{2}_", bundle_id) else None
    if not date:
        parent = path.parent.name
        date = parent if re.match(r"^\d{4}-\d{2}-\d{2}$", parent) else (date_hint or "undated")
        bundle_id = f"{date}_{path.name}"
    b = Bundle(path=path, bundle_id=bundle_id, date=date, manifest=manifest, events=events, problems=problems)
    validate(b)
    return b


def find_bundle_dirs(root: Path) -> list[Path]:
    """Any directory holding an events.jsonl is a bundle (zip layouts vary: day/bundle, bundle, sessions/day/bundle)."""
    found = []
    for ev in sorted(root.rglob("events.jsonl")):
        if "__MACOSX" in ev.parts or "_conflicts" in ev.parts:
            continue
        found.append(ev.parent)
    return found


def safe_extract(zf: zipfile.ZipFile, dest: Path) -> None:
    dest = dest.resolve()
    for member in zf.infolist():
        target = (dest / member.filename).resolve()
        if dest != target and dest not in target.parents:
            raise ValueError(f"unsafe path in zip: {member.filename}")
    zf.extractall(dest)


# --------------------------------------------------------------------------- import into raw

def import_bundle(src: Path, raw_root: Path, report: Report) -> None:
    b = load_bundle(src)
    dest = raw_root / b.date / src.name
    new_events = (src / "events.jsonl").read_bytes() if (src / "events.jsonl").exists() else b""
    if dest.exists():
        old_path = dest / "events.jsonl"
        old_events = old_path.read_bytes() if old_path.exists() else b""
        if old_events == new_events:
            _copy_missing(src, dest)  # media that arrived late, nothing else
            report.skipped.append(b.bundle_id)
            return
        if not _is_prefix(old_events, new_events):
            if _is_prefix(new_events, old_events):
                report.skipped.append(f"{b.bundle_id} (older export; kept the newer copy)")
                return
            digest = hashlib.sha1(new_events).hexdigest()[:8]
            cdest = raw_root / b.date / "_conflicts" / f"{src.name}__{digest}"
            if not cdest.exists():
                shutil.copytree(src, cdest)
            report.conflicts.append(f"{b.bundle_id}: differs from the copy in raw/ (not a superset); "
                                    f"saved to {cdest.relative_to(raw_root.parent.parent).as_posix()}")
            return
        _copy_missing(src, dest)
        shutil.copy2(src / "events.jsonl", dest / "events.jsonl")
        if (src / "manifest.json").exists():
            shutil.copy2(src / "manifest.json", dest / "manifest.json")
        report.imported.append(f"{b.bundle_id} (updated)")
        return
    shutil.copytree(src, dest)
    report.imported.append(b.bundle_id)


def _is_prefix(old: bytes, new: bytes) -> bool:
    """True if every complete line of `old` is at the start of `new` (old's truncated tail may differ)."""
    old_lines = old.split(b"\n")
    complete = old_lines[:-1] if not old.endswith(b"\n") else old_lines
    prefix = b"\n".join(complete)
    return new.startswith(prefix)


def _copy_missing(src: Path, dest: Path) -> None:
    for f in src.rglob("*"):
        if f.is_file():
            target = dest / f.relative_to(src)
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(f, target)


def import_inputs(inputs: list[Path], root: Path, report: Report) -> None:
    raw_root = root / "vault" / "raw"
    raw_root.mkdir(parents=True, exist_ok=True)
    for inp in inputs:
        if inp.is_file() and inp.suffix.lower() == ".zip":
            with tempfile.TemporaryDirectory() as tmp:
                with zipfile.ZipFile(inp) as zf:
                    safe_extract(zf, Path(tmp))
                dirs = find_bundle_dirs(Path(tmp))
                if not dirs:
                    report.problems.append(f"{inp.name}: no bundles found")
                for d in dirs:
                    import_bundle(d, raw_root, report)
        elif inp.is_dir():
            dirs = find_bundle_dirs(inp)
            if not dirs:
                report.problems.append(f"{inp}: no bundles found")
            for d in dirs:
                import_bundle(d, raw_root, report)
        else:
            report.problems.append(f"{inp}: not a zip or folder; ignored")


# --------------------------------------------------------------------------- resolve and merge

def resolve(bundle: Bundle) -> tuple[list[dict], dict | None]:
    """Apply tag/edit/delete. Returns (kept events, last speaker_start event)."""
    deleted: set[str] = set()
    tags: dict[str, str | None] = {}
    edits: dict[str, str] = {}
    for e in bundle.events:
        t, target = e.get("type"), e.get("target")
        if not target:
            continue
        if t == "delete":
            deleted.add(target)
        elif t == "tag":
            tags[target] = e.get("tag")  # null clears
        elif t == "edit":
            edits[target] = e.get("text") or ""
    kept = []
    speaker_start = None
    for e in bundle.events:
        t = e.get("type")
        if t in ("tag", "edit", "delete") or e.get("id") in deleted:
            continue
        e = dict(e)
        if e["id"] in tags:
            if tags[e["id"]]:
                e["tag"] = tags[e["id"]]
            else:
                e.pop("tag", None)
        if e["id"] in edits:
            e["text"] = edits[e["id"]]
        if t == "speaker_start":
            speaker_start = e  # last one in the file wins
        e["bundle"] = bundle.bundle_id
        kept.append(e)
    return kept, speaker_start


def counts_of(events: list[dict]) -> dict:
    c = {"photo": 0, "moment": 0, "note": 0, "voice": 0, "audio_segment": 0}
    for e in events:
        if e.get("type") in c:
            c[e["type"]] += 1
    return c


def build_talk(talk_id: str, bundles: list[Bundle], talks_root: Path) -> dict:
    out = talks_root / talk_id
    out.mkdir(parents=True, exist_ok=True)
    problems: list[str] = []
    events: list[dict] = []
    starts: list[tuple[datetime, str]] = []
    for b in bundles:
        kept, ss = resolve(b)
        events.extend(kept)
        if ss:
            starts.append((parse_ts(ss["ts_utc"]), b.device))
        problems.extend(f"{b.bundle_id}: {p}" for p in b.problems)

    # Clock basis: earliest speaker_start across devices; report skew between devices.
    skew_ms = None
    starts.sort()
    if len(starts) >= 2:
        skew_ms = ms_between(starts[0][0], starts[-1][0])
        if skew_ms > 10_000:
            problems.append(f"speaker_start differs by {skew_ms / 1000:.1f} s between devices; using the earliest")
    first = sorted(bundles, key=lambda b: (b.device != "iphone", b.bundle_id))[0]
    t0 = min((b.t0 for b in bundles if b.t0), default=None)
    basis = starts[0][0] if starts else t0
    if basis is None:
        basis = min(parse_ts(e["ts_utc"]) for e in events) if events else datetime.now(UTC)
        problems.append("no scheduled start or speaker_start; offsets count from the first event")

    for e in events:
        e["talk_ms"] = ms_between(basis, parse_ts(e["ts_utc"]))
    events.sort(key=lambda e: (parse_ts(e["ts_utc"]), e.get("bundle", ""), e.get("seq", 0)))

    # Stable reference numbers (S07, N3, M4, V1) so briefs keep pointing at the right capture.
    refs_path = out / "refs.json"
    refs: dict[str, str] = json.loads(refs_path.read_text(encoding="utf-8")) if refs_path.exists() else {}
    next_n = {p: 1 for p in REF_PREFIX.values()}
    for ref in refs.values():
        m = re.match(r"^([SNMV])(\d+)$", ref)
        if m:
            next_n[m.group(1)] = max(next_n[m.group(1)], int(m.group(2)) + 1)
    for e in events:
        prefix = REF_PREFIX.get(e["type"])
        if not prefix:
            continue
        if e["id"] not in refs:
            n = next_n[prefix]
            next_n[prefix] += 1
            refs[e["id"]] = f"{prefix}{n:02d}" if prefix == "S" else f"{prefix}{n}"
        e["ref"] = refs[e["id"]]
    refs_path.write_text(json.dumps(refs, indent=1, sort_keys=True) + "\n", encoding="utf-8")

    # Media: photos/S01.jpg ..., voice/<original name>
    by_bundle = {b.bundle_id: b for b in bundles}
    photos_dir, voice_dir = out / "photos", out / "voice"
    photos_dir.mkdir(exist_ok=True)
    voice_dir.mkdir(exist_ok=True)
    wanted_photos: set[str] = set()
    photo_index = []
    for e in events:
        if e["type"] not in MEDIA_TYPES or not e.get("file"):
            continue
        src = by_bundle[e["bundle"]].path / e["file"]
        if not src.exists():
            continue
        if e["type"] == "photo":
            name = f"{e['ref']}{src.suffix.lower()}"
            wanted_photos.add(name)
            _copy_if_changed(src, photos_dir / name)
            e["vault_file"] = f"photos/{name}"
            photo_index.append({"ref": e["ref"], "file": name, "id": e["id"], "ts_utc": e["ts_utc"],
                                "talk_ms": e["talk_ms"], "offset": fmt_offset(e["talk_ms"]), "zoom": e.get("zoom")})
        elif e["type"] == "voice":
            _copy_if_changed(src, voice_dir / src.name)
            e["vault_file"] = f"voice/{src.name}"
        else:  # permitted session audio: private, never published
            (out / "audio").mkdir(exist_ok=True)
            _copy_if_changed(src, out / "audio" / src.name)
            e["vault_file"] = f"audio/{src.name}"
    for stale in photos_dir.glob("S*"):
        if re.match(r"^S\d+\.(jpg|jpeg|heic|png)$", stale.name) and stale.name not in wanted_photos:
            stale.unlink()  # deleted on the device after an earlier ingest
    mark_near_duplicates(photo_index, photos_dir)
    (photos_dir / "index.json").write_text(json.dumps(photo_index, indent=1) + "\n", encoding="utf-8")

    with (out / "timeline.jsonl").open("w", encoding="utf-8", newline="\n") as f:
        for e in events:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")

    visibility = "private" if any(b.visibility == "private" for b in bundles) else "shareable"
    talk_meta = dict(first.talk)
    talk_meta.setdefault("talk_id", talk_id)
    info = {
        "schema": "qcon.talk/1",
        "talk": talk_meta,
        "visibility": visibility,
        "all_bundles_private": all(b.visibility == "private" for b in bundles),
        "devices": sorted({b.device for b in bundles}),
        "bundles": [{"bundle_id": b.bundle_id, "device": b.device, "visibility": b.visibility,
                     "raw": str(b.path.as_posix())} for b in bundles],
        "t0_utc": fmt_utc(t0) if t0 else None,
        "speaker_start_utc": fmt_utc(starts[0][0]) if starts else None,
        "start_synced": bool(starts),
        "measured_skew_ms": skew_ms,
        "counts": counts_of(events),
        "problems": problems,
    }
    (out / "talk.json").write_text(json.dumps(info, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    write_notes_md(out, info, events)
    return info


def _copy_if_changed(src: Path, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size == src.stat().st_size:
        return
    shutil.copy2(src, dest)


def mark_near_duplicates(index: list[dict], photos_dir: Path) -> None:
    """Flags a photo that looks like the previous kept photo (Pillow dHash). Skipped without Pillow."""
    try:
        from PIL import Image  # type: ignore
    except ImportError:
        return
    prev_hash, prev_ref = None, None
    for item in index:
        try:
            with Image.open(photos_dir / item["file"]) as im:
                g = im.convert("L").resize((9, 8))
                px = g.tobytes()
        except Exception:
            continue
        h = 0
        for row in range(8):
            for col in range(8):
                h = (h << 1) | (px[row * 9 + col] > px[row * 9 + col + 1])
        if prev_hash is not None and bin(h ^ prev_hash).count("1") <= 4:
            item["near_duplicate_of"] = prev_ref
        else:
            prev_hash, prev_ref = h, item["ref"]


def write_notes_md(out: Path, info: dict, events: list[dict]) -> None:
    talk = info["talk"]
    lines = [
        f"# Captures: {talk.get('title', talk.get('talk_id'))}",
        "",
        "Generated by tools/ingest.py. Do not edit; it is rewritten on every ingest.",
        f"Devices: {', '.join(info['devices'])}. Visibility: {info['visibility']}.",
    ]
    if info["start_synced"]:
        lines.append(f"Talk start: speaker_start at {parse_ts(info['speaker_start_utc']).astimezone(TZ):%H:%M:%S} "
                     f"(synced). Offsets below are from that moment.")
    else:
        lines.append("Talk start: not synced; offsets count from the scheduled start.")
    if info.get("measured_skew_ms") is not None:
        lines.append(f"Measured device skew: {info['measured_skew_ms']} ms.")
    lines += ["", "| Ref | Offset | Local time | Device | Kind | Content |", "|---|---|---|---|---|---|"]
    for e in events:
        t = e["type"]
        if t not in REF_PREFIX and t not in ("speaker_start",):
            continue
        local = parse_ts(e["ts_utc"]).astimezone(TZ).strftime("%H:%M:%S")
        dev = e["id"].split("-")[0]
        if t == "photo":
            content = e.get("vault_file", e.get("file", ""))
        elif t == "moment":
            content = e.get("tag", "") or ""
        elif t == "note":
            content = (e.get("text") or "").replace("|", "\\|").replace("\n", " ")
        elif t == "voice":
            content = f"{e.get('phase', 'after')} talk reflection, {(e.get('dur_ms') or 0) // 1000} s, {e.get('vault_file', '')}"
        else:
            content = "speaker started"
        lines.append(f"| {e.get('ref', '')} | {fmt_offset(e['talk_ms'])} | {local} | {dev} | {t} | {content} |")
    voices = [e for e in events if e["type"] == "voice"]
    if voices:
        lines += ["", "## Reflection transcripts", ""]
        for e in voices:
            name = Path(e.get("vault_file", "")).stem
            txt = out / "voice" / f"{name}.txt"
            lines.append(f"### [{e['ref']}] {e.get('vault_file', '')}")
            lines.append(txt.read_text(encoding="utf-8").strip() if txt.exists()
                         else "(not transcribed yet: run tools/transcribe.py, then re-run ingest)")
            lines.append("")
    (out / "notes.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def rebuild_talks(root: Path, report: Report) -> None:
    raw_root = root / "vault" / "raw"
    talks_root = root / "vault" / "talks"
    talks_root.mkdir(parents=True, exist_ok=True)
    groups: dict[str, list[Bundle]] = {}
    if raw_root.exists():
        for day in sorted(p for p in raw_root.iterdir() if p.is_dir()):
            for bdir in sorted(p for p in day.iterdir() if p.is_dir() and not p.name.startswith("_")):
                if not (bdir / "events.jsonl").exists():
                    continue
                b = load_bundle(bdir, date_hint=day.name)
                groups.setdefault(b.talk_id, []).append(b)
    for talk_id, bundles in sorted(groups.items()):
        info = build_talk(talk_id, bundles, talks_root)
        report.talks[talk_id] = {"devices": info["devices"], "counts": info["counts"],
                                 "visibility": info["visibility"], "start_synced": info["start_synced"],
                                 "measured_skew_ms": info["measured_skew_ms"], "problems": info["problems"]}


# --------------------------------------------------------------------------- fallback mode

def load_schedule(path: Path) -> list[dict]:
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    for t in data.get("talks", []):
        t["_start"] = parse_ts(t["start"])
        t["_end"] = parse_ts(t["end"])
    return data.get("talks", [])


def _words(s: str) -> set[str]:
    return {w for w in re.split(r"[^a-z0-9]+", s.lower()) if len(w) >= 4}


def match_talk(name: str, when: datetime | None, talks: list[dict]) -> dict | None:
    """TALK line or file name -> schedule talk: exact slug, slug prefix, then word overlap near the time."""
    key = name.strip().lower()
    for t in talks:
        if t["talk_id"] == key:
            return t
    slugish = re.sub(r"[^a-z0-9]+", "-", key).strip("-")
    prefixed = [t for t in talks if slugish and t["talk_id"].startswith(slugish)]
    if len(prefixed) == 1:
        return prefixed[0]
    qw = _words(name)
    if not qw:
        return None
    scored = []
    for t in talks:
        tw = _words(t["title"] + " " + t["talk_id"] + " " + " ".join(s["name"] for s in t.get("speakers", [])))
        score = len(qw & tw) / len(qw)
        if score >= 0.5:
            near = abs((t["_start"] - when).total_seconds()) if when else 0
            scored.append((-score, near, t["talk_id"], t))
    if not scored:
        return None
    scored.sort(key=lambda x: x[:3])
    return scored[0][3]


def slot_talks(when: datetime, talks: list[dict]) -> list[dict]:
    return [t for t in talks if t["_start"] - timedelta(minutes=20) <= when < t["_end"]]


@dataclass
class FbSession:
    talk: dict
    opened: datetime
    speaker_start: datetime | None
    until: datetime
    items: list[tuple[datetime, str, dict]] = field(default_factory=list)


def exif_datetime(path: Path) -> datetime | None:
    """DateTimeOriginal (+ OffsetTimeOriginal) from a JPEG's EXIF, standard library only."""
    try:
        data = path.read_bytes()[:512 * 1024]
    except OSError:
        return None
    if data[:2] != b"\xff\xd8":
        return None
    i = 2
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            return None
        marker = data[i + 1]
        if marker == 0xD8 or 0xD0 <= marker <= 0xD7 or marker == 0x01:
            i += 2
            continue
        seglen = int.from_bytes(data[i + 2:i + 4], "big")
        if marker == 0xE1 and data[i + 4:i + 10] == b"Exif\x00\x00":
            return _parse_tiff_datetime(data[i + 10:i + 2 + seglen])
        if marker == 0xDA:
            return None
        i += 2 + seglen
    return None


def _parse_tiff_datetime(t: bytes) -> datetime | None:
    try:
        end = "<" if t[:2] == b"II" else ">"
        u16 = lambda o: struct.unpack_from(end + "H", t, o)[0]  # noqa: E731
        u32 = lambda o: struct.unpack_from(end + "I", t, o)[0]  # noqa: E731

        def entries(off):
            for k in range(u16(off)):
                e = off + 2 + 12 * k
                yield u16(e), u16(e + 2), u32(e + 4), e + 8

        def ascii_at(cnt, valoff):
            start = valoff if cnt <= 4 else u32(valoff)
            return t[start:start + cnt].split(b"\x00")[0].decode("ascii", "replace")

        dt_str, dto_str, off_str, exif_ptr = None, None, None, None
        for tag, _typ, cnt, valoff in entries(u32(4)):
            if tag == 0x8769:
                exif_ptr = u32(valoff)
            elif tag == 0x0132:
                dt_str = ascii_at(cnt, valoff)
        if exif_ptr:
            for tag, _typ, cnt, valoff in entries(exif_ptr):
                if tag == 0x9003:
                    dto_str = ascii_at(cnt, valoff)
                elif tag == 0x9011:
                    off_str = ascii_at(cnt, valoff)
        s = dto_str or dt_str
        if not s:
            return None
        d = datetime.strptime(s.strip(), "%Y:%m:%d %H:%M:%S")
        if off_str and re.match(r"^[+-]\d{2}:\d{2}$", off_str):
            sign = 1 if off_str[0] == "+" else -1
            h, m = int(off_str[1:3]), int(off_str[4:6])
            return d.replace(tzinfo=timezone(sign * timedelta(hours=h, minutes=m)))
        return d.replace(tzinfo=TZ)  # no offset: assume the phone was on conference time
    except (struct.error, ValueError, IndexError):
        return None


def fallback(root: Path, notes: list[Path], photos: Path | None, voice: Path | None,
             schedule_path: Path, plan_path: Path, report: Report) -> None:
    talks = load_schedule(schedule_path)
    plan = set()
    if plan_path.exists():
        plan = {ln.strip() for ln in plan_path.read_text(encoding="utf-8").splitlines()
                if ln.strip() and not ln.strip().startswith("#")}
    sessions: list[FbSession] = []
    orphans: list[tuple[datetime, str, dict]] = []

    # 1. Notes file(s): TALK lines open sessions; other lines are captures.
    lines: list[tuple[datetime, str]] = []
    for nf in notes:
        for n, raw in enumerate(nf.read_text(encoding="utf-8-sig").splitlines(), 1):
            if not raw.strip():
                continue
            if "|" not in raw:
                report.problems.append(f"{nf.name}:{n}: no '|' separator; skipped")
                continue
            ts_s, text = raw.split("|", 1)
            ts = parse_ts(ts_s)
            if ts is None:
                report.problems.append(f"{nf.name}:{n}: unreadable time {ts_s.strip()!r}; skipped")
                continue
            lines.append((ts, text.strip()))
    lines.sort(key=lambda x: x[0])
    for ts, text in lines:
        if text.upper().startswith("TALK "):
            name = text[5:].strip()
            t = match_talk(name, ts, talks)
            if t is None:
                t = {"talk_id": f"adhoc-{ts.astimezone(TZ):%Y%m%d-%H%M}", "kind": "adhoc", "title": name,
                     "speakers": [], "track": None, "room": None, "url": None, "no_video": True,
                     "_start": ts, "_end": ts + timedelta(minutes=60)}
                report.problems.append(f"TALK {name!r} matched no scheduled talk; made private ad hoc session")
            if sessions:
                sessions[-1].until = min(sessions[-1].until, ts)
            sessions.append(FbSession(talk=t, opened=ts, speaker_start=ts,
                                      until=max(t["_end"], ts) + timedelta(minutes=15)))
            continue
        low = text.lower().strip(" .!")
        if not text or text in (".", "m", "M"):
            item = ("moment", {})
        elif low in TAG_WORDS:
            item = ("moment", {"tag": TAG_WORDS[low]})
        else:
            item = ("note", {"text": text})
        orphans.append((ts, item[0], item[1]))

    # 2. Photos by EXIF time; 3. voice memos by name, else file time.
    if photos and photos.exists():
        for p in sorted(photos.iterdir()):
            if p.suffix.lower() not in PHOTO_EXT:
                continue
            ts = exif_datetime(p) if p.suffix.lower() in (".jpg", ".jpeg") else None
            if ts is None:
                ts = datetime.fromtimestamp(p.stat().st_mtime, tz=UTC)
                report.problems.append(f"{p.name}: no EXIF time; used the file time (set Camera > Formats > Most Compatible)")
            orphans.append((ts, "photo", {"src": p}))
    voice_by_name: list[tuple[dict, Path]] = []
    if voice and voice.exists():
        for p in sorted(voice.iterdir()):
            if p.suffix.lower() not in AUDIO_EXT:
                continue
            ts = datetime.fromtimestamp(p.stat().st_mtime, tz=UTC)
            t = match_talk(p.stem, None, talks)
            if t is not None:
                voice_by_name.append((t, p))
            else:
                report.problems.append(f"{p.name}: no talk name in the title; placed by file time (check it)")
                orphans.append((ts, "voice", {"src": p}))

    # Place every capture into the TALK session covering its time, else slot + plan, else unassigned.
    unassigned: list[tuple[datetime, str, dict]] = []
    for ts, typ, extra in sorted(orphans, key=lambda x: x[0]):
        home = None
        for s in sessions:
            if s.opened - timedelta(minutes=5) <= ts < s.until:
                home = s
        if home is None:
            cands = slot_talks(ts, talks)
            planned = [t for t in cands if t["talk_id"] in plan]
            pick = planned[0] if len(planned) == 1 else None
            if pick:
                home = next((s for s in sessions if s.talk["talk_id"] == pick["talk_id"]), None)
                if home is None:
                    home = FbSession(talk=pick, opened=ts, speaker_start=None, until=pick["_end"] + timedelta(minutes=15))
                    sessions.append(home)
        if home is None:
            unassigned.append((ts, typ, extra))
        else:
            home.items.append((ts, typ, extra))
    for t, p in voice_by_name:
        home = next((s for s in sessions if s.talk["talk_id"] == t["talk_id"]), None)
        mtime = datetime.fromtimestamp(p.stat().st_mtime, tz=UTC)
        # Voice Memos exports often carry the export time; fall back to the talk's end.
        ts = mtime if t["_start"] <= mtime <= t["_end"] + timedelta(hours=3) else t["_end"]
        if home is None:
            home = FbSession(talk=t, opened=t["_start"], speaker_start=None, until=t["_end"])
            sessions.append(home)
        home.items.append((ts, "voice", {"src": p}))
    if unassigned:
        by_day: dict[str, list] = {}
        for item in unassigned:
            by_day.setdefault(local_day(item[0]), []).append(item)
        for day, items in by_day.items():
            first = min(i[0] for i in items)
            talk = {"talk_id": f"unassigned-{day.replace('-', '')}", "kind": "adhoc",
                    "title": f"Unassigned captures {day}", "speakers": [], "track": None, "room": None,
                    "url": None, "no_video": True, "_start": first, "_end": first + timedelta(minutes=60)}
            s = FbSession(talk=talk, opened=first, speaker_start=None, until=first)
            s.items = items
            sessions.append(s)
            report.problems.append(f"{len(items)} fallback captures on {day} matched no talk; "
                                   f"see talks/{talk['talk_id']}")

    raw_root = root / "vault" / "raw"
    merged: dict[str, FbSession] = {}
    for s in sessions:  # a talk named twice (TALK typed again) becomes one bundle
        key = s.talk["talk_id"]
        if key in merged:
            merged[key].items.extend(s.items)
            merged[key].opened = min(merged[key].opened, s.opened)
            if merged[key].speaker_start is None:
                merged[key].speaker_start = s.speaker_start
        else:
            merged[key] = s
    for s in merged.values():
        if s.items or s.speaker_start:
            write_fallback_bundle(s, raw_root, report)


def write_fallback_bundle(s: FbSession, raw_root: Path, report: Report) -> None:
    talk = s.talk
    adhoc = talk.get("kind") == "adhoc"
    start = s.opened if adhoc else talk["_start"]
    folder = f"{local_hhmm(start)}_{talk['talk_id'][:48]}__fallback"
    day = local_day(start)
    out = raw_root / day / folder
    if out.exists():
        shutil.rmtree(out)  # synthetic: regenerated from the fallback inputs on every run
    (out / "photos").mkdir(parents=True)
    (out / "voice").mkdir()
    t0 = start
    opened = min([s.opened] + [i[0] for i in s.items])
    events: list[dict] = []

    def add(typ: str, ts: datetime, **extra) -> dict:
        seq = len(events) + 1
        e = {"seq": seq, "id": f"fallback-{seq:04d}", "type": typ, "ts_utc": fmt_utc(ts),
             "t_ms": ms_between(t0, ts), "mono_ms": max(0, ms_between(opened, ts))}
        e.update(extra)
        events.append(e)
        return e

    add("session_open", opened, app_version="fallback")
    timeline = sorted(s.items, key=lambda i: i[0])
    if s.speaker_start:
        timeline.append((s.speaker_start, "speaker_start", {}))
        timeline.sort(key=lambda i: i[0])
    for ts, typ, extra in timeline:
        seq = len(events) + 1
        if typ == "photo":
            src: Path = extra["src"]
            rel = f"photos/{seq:04d}_photo_{ts.astimezone(UTC):%H%M%S}Z{src.suffix.lower()}"
            shutil.copy2(src, out / rel)
            add("photo", ts, file=rel, zoom=None)
        elif typ == "voice":
            src = extra["src"]
            rel = f"voice/{seq:04d}_voice_{ts.astimezone(UTC):%H%M%S}Z{src.suffix.lower()}"
            shutil.copy2(src, out / rel)
            add("voice", ts, file=rel, dur_ms=None, phase="after", source_name=src.name)
        elif typ == "speaker_start":
            add("speaker_start", ts)
        elif typ == "moment":
            add("moment", ts, **({"tag": extra["tag"]} if extra.get("tag") else {}))
        elif typ == "note":
            add("note", ts, text=extra["text"], saved_utc=fmt_utc(ts))
    private = talk.get("kind") in ("adhoc", "unconference", "social")
    manifest = {
        "schema": "collector.bundle/1",
        "bundle_id": f"{day}_{folder}",
        "source": "fallback",
        "talk": {
            "talk_id": talk["talk_id"], "kind": talk.get("kind"), "title": talk.get("title"),
            "speakers": talk.get("speakers", []), "track": talk.get("track"), "room": talk.get("room"),
            "url": talk.get("url"), "sched_start_utc": fmt_utc(talk["_start"]),
            "sched_end_utc": fmt_utc(talk["_end"]), "tz": CONF_TZ_NAME, "no_video": talk.get("no_video", False),
        },
        "visibility": "private" if private else "shareable",
        "device": {"label": "fallback", "model": "Camera + Shortcut + Voice Memos", "os": None, "app_version": "fallback"},
        "clock": {"t0_utc": fmt_utc(t0), "t0_basis": "opened" if adhoc else "scheduled_start",
                  "speaker_start_utc": fmt_utc(s.speaker_start) if s.speaker_start else None,
                  "speaker_start_t_ms": ms_between(t0, s.speaker_start) if s.speaker_start else None},
        "session_audio": {"permitted": False, "granted_by": None, "how": None, "note": None, "granted_utc": None},
        "opened_utc": fmt_utc(opened), "closed_utc": None, "close_reason": None,
        "counts": counts_of(events), "last_seq": len(events),
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    with (out / "events.jsonl").open("w", encoding="utf-8", newline="\n") as f:
        for e in events:
            f.write(json.dumps({k: v for k, v in e.items() if v is not None}, ensure_ascii=False) + "\n")
    report.imported.append(f"{day}_{folder} (fallback)")


# --------------------------------------------------------------------------- CLI

def default_inputs(root: Path) -> list[Path]:
    inbox = root / "inbox"
    if not inbox.exists():
        return []
    return sorted(p for p in inbox.iterdir() if (p.suffix.lower() == ".zip") or
                  (p.is_dir() and p.name != "fallback" and not p.name.startswith(".")))


def print_report(report: Report) -> None:
    for title, items in (("Imported", report.imported), ("Unchanged", report.skipped),
                         ("CONFLICTS", report.conflicts), ("Problems", report.problems)):
        if items:
            print(f"{title}:")
            for i in items:
                print(f"  - {i}")
    if report.talks:
        print(f"\n{'talk_id':52} {'dev':14} {'S':>3} {'M':>3} {'N':>3} {'V':>3}  sync  skew   vis")
        for tid, t in report.talks.items():
            c = t["counts"]
            skew = "" if t["measured_skew_ms"] is None else f"{t['measured_skew_ms'] / 1000:.1f}s"
            print(f"{tid[:52]:52} {','.join(t['devices'])[:14]:14} {c['photo']:>3} {c['moment']:>3} "
                  f"{c['note']:>3} {c['voice']:>3}  {'yes' if t['start_synced'] else 'no ':4} {skew:6} {t['visibility']}")
            for p in t["problems"]:
                print(f"      ! {p}")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="*", type=Path, help="zips or folders (default: everything in inbox/)")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                    help="workspace root holding inbox/ and vault/ (default: parent of tools/)")
    ap.add_argument("--fallback", action="store_true", help="ingest Camera/Shortcut/Voice Memos captures")
    ap.add_argument("--notes", type=Path, action="append", help="Shortcut notes file (repeatable)")
    ap.add_argument("--photos", type=Path, help="folder of Camera photos")
    ap.add_argument("--voice", type=Path, help="folder of Voice Memos exports")
    ap.add_argument("--schedule", type=Path, help="collector schedule.json (default vault/schedule/schedule.json)")
    ap.add_argument("--plan", type=Path, help="planned talk ids, one per line (default vault/plan.txt)")
    ap.add_argument("--json", action="store_true", help="print the report as JSON")
    args = ap.parse_args(argv)

    root = args.root.resolve()
    report = Report()
    if args.fallback:
        fb = root / "inbox" / "fallback"
        notes = args.notes or sorted(fb.glob("*.txt"))
        fallback(root, notes, args.photos or fb / "photos", args.voice or fb / "voice",
                 args.schedule or root / "vault" / "schedule" / "schedule.json",
                 args.plan or root / "vault" / "plan.txt", report)
    inputs = args.inputs if args.inputs else ([] if args.fallback else default_inputs(root))
    import_inputs(inputs, root, report)
    rebuild_talks(root, report)
    (root / "vault").mkdir(exist_ok=True)
    (root / "vault" / "ingest-report.json").write_text(json.dumps(report.to_dict(), indent=1) + "\n", encoding="utf-8")
    if args.json:
        print(json.dumps(report.to_dict(), indent=1))
    else:
        print_report(report)
    return 2 if report.conflicts else 0


if __name__ == "__main__":
    sys.exit(main())
