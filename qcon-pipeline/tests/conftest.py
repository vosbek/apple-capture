"""Synthetic Collector bundles, written to the format in architecture.md sections 4.4-4.6."""
from __future__ import annotations

import json
import struct
import sys
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parent.parent / "tools"
sys.path.insert(0, str(TOOLS))

UTC = timezone.utc

HARNESS = {
    "talk_id": "harness-new-operating-system",
    "kind": "keynote",
    "title": "The Harness Is the New Operating System",
    "speakers": [{"name": "Manju Rajashekhar", "company": "Mad Labs"}],
    "track": None,
    "room": "Grand Ballroom",
    "url": "https://qconsf.com/keynote/nov2026/harness-new-operating-system",
    "sched_start_utc": "2026-11-16T17:00:00Z",
    "sched_end_utc": "2026-11-16T18:10:00Z",
    "tz": "America/Los_Angeles",
    "no_video": False,
}

UNCONF = {
    "talk_id": "unconference-architectures-youve-always-wondered-about",
    "kind": "unconference",
    "title": "Unconference: Architectures",
    "speakers": [],
    "track": "Architectures You've Always Wondered About",
    "room": "Ballroom BC",
    "url": None,
    "sched_start_utc": "2026-11-16T22:35:00Z",
    "sched_end_utc": "2026-11-16T23:25:00Z",
    "tz": "America/Los_Angeles",
    "no_video": True,
}


def ts(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def iso(d: datetime) -> str:
    d = d.astimezone(UTC)
    return d.strftime("%Y-%m-%dT%H:%M:%S.") + f"{d.microsecond // 1000:03d}Z"


def tiny_jpeg(exif_dt: str | None = None, offset: str | None = None, shade: int = 128) -> bytes:
    """A small JPEG. With Pillow, a real image (shade varies the content); without, SOI+EXIF+EOI."""
    exif = _exif_segment(exif_dt, offset) if exif_dt else b""
    try:
        from PIL import Image
        import io
        im = Image.new("L", (64, 48), shade)
        for x in range(0, 64, 8):  # some structure so dHash differs between shades
            for y in range(48):
                im.putpixel((x, y), (shade * 3 + x * 7) % 256)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=80)
        data = buf.getvalue()
        return data[:2] + exif + data[2:]
    except ImportError:
        return b"\xff\xd8" + exif + b"\xff\xd9"


def _exif_segment(dt: str, offset: str | None) -> bytes:
    """APP1 Exif with IFD0 -> ExifIFD holding DateTimeOriginal (0x9003) and OffsetTimeOriginal (0x9011)."""
    dt_b = dt.encode() + b"\x00"            # 20 bytes
    off_b = (offset.encode() + b"\x00") if offset else b""
    n_exif = 2 if offset else 1
    ifd0_off = 8
    ifd0_size = 2 + 12 * 1 + 4
    exif_ifd_off = ifd0_off + ifd0_size
    exif_ifd_size = 2 + 12 * n_exif + 4
    data_off = exif_ifd_off + exif_ifd_size
    tiff = b"II*\x00" + struct.pack("<I", ifd0_off)
    tiff += struct.pack("<H", 1) + struct.pack("<HHII", 0x8769, 4, 1, exif_ifd_off) + struct.pack("<I", 0)
    entries = struct.pack("<HHII", 0x9003, 2, len(dt_b), data_off)
    if offset:
        entries += struct.pack("<HHII", 0x9011, 2, len(off_b), data_off + len(dt_b))
    tiff += struct.pack("<H", n_exif) + entries + struct.pack("<I", 0)
    tiff += dt_b + off_b
    payload = b"Exif\x00\x00" + tiff
    return b"\xff\xe1" + struct.pack(">H", len(payload) + 2) + payload


class BundleBuilder:
    """Writes one bundle: Documents/sessions/<date>/<HHMM>_<slug48>__<device>/."""

    def __init__(self, sessions: Path, device: str, talk: dict, opened: str, visibility: str | None = None):
        self.device = device
        self.talk = talk
        self.t0 = ts(talk["sched_start_utc"])
        local = self.t0.astimezone(timezone(timedelta(hours=-8)))
        self.date = local.strftime("%Y-%m-%d")
        self.folder = f"{local.strftime('%H%M')}_{talk['talk_id'][:48]}__{device}"
        self.dir = sessions / self.date / self.folder
        (self.dir / "photos").mkdir(parents=True, exist_ok=True)
        (self.dir / "voice").mkdir(parents=True, exist_ok=True)
        self.opened = ts(opened)
        self.events: list[dict] = []
        self.visibility = visibility or ("private" if talk["kind"] in ("unconference", "adhoc", "social") else "shareable")
        self.add("session_open", opened, app_version="1.0 (3)")

    @property
    def bundle_id(self) -> str:
        return f"{self.date}_{self.folder}"

    def add(self, typ: str, when: str, **extra) -> str:
        seq = len(self.events) + 1
        d = ts(when)
        e = {"seq": seq, "id": f"{self.device}-{seq:04d}", "type": typ, "ts_utc": iso(d),
             "t_ms": round((d - self.t0).total_seconds() * 1000),
             "mono_ms": round((d - self.opened).total_seconds() * 1000)}
        e.update(extra)
        self.events.append(e)
        return e["id"]

    def photo(self, when: str, zoom: float = 2.0, shade: int = 128) -> str:
        seq = len(self.events) + 1
        rel = f"photos/{seq:04d}_photo_{ts(when).strftime('%H%M%S')}Z.jpg"
        (self.dir / rel).write_bytes(tiny_jpeg(shade=shade))
        return self.add("photo", when, file=rel, zoom=zoom)

    def voice(self, when: str, dur_ms: int = 84000, phase: str = "after") -> str:
        seq = len(self.events) + 1
        rel = f"voice/{seq:04d}_voice_{ts(when).strftime('%H%M%S')}Z.m4a"
        (self.dir / rel).write_bytes(b"\x00\x00\x00\x18ftypM4A fake audio")
        return self.add("voice", when, file=rel, dur_ms=dur_ms, phase=phase)

    def write(self, truncated_tail: str | None = None, closed: str | None = None) -> "BundleBuilder":
        lines = "".join(json.dumps(e, separators=(",", ":")) + "\n" for e in self.events)
        if truncated_tail:
            lines += truncated_tail
        (self.dir / "events.jsonl").write_text(lines, encoding="utf-8")
        speaker = [e for e in self.events if e["type"] == "speaker_start"]
        manifest = {
            "schema": "collector.bundle/1",
            "bundle_id": self.bundle_id,
            "talk": self.talk,
            "visibility": self.visibility,
            "device": {"label": self.device, "model": "iPhone17,1", "os": "26.1", "app_version": "1.0 (3)"},
            "clock": {"t0_utc": self.talk["sched_start_utc"], "t0_basis": "scheduled_start",
                      "speaker_start_utc": speaker[-1]["ts_utc"] if speaker else None,
                      "speaker_start_t_ms": speaker[-1]["t_ms"] if speaker else None},
            "session_audio": {"permitted": False, "granted_by": None, "how": None, "note": None, "granted_utc": None},
            "opened_utc": iso(self.opened),
            "closed_utc": closed,
            "close_reason": "user" if closed else None,
            "counts": {"photo": 99, "moment": 0, "note": 0, "voice": 0, "audio_segment": 0},  # wrong on purpose
            "last_seq": len(self.events),
        }
        (self.dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return self


def zip_day(sessions: Path, date: str, out: Path) -> Path:
    """Same layout as NSFileCoordinator(.forUploading) on Documents/sessions/<date>: top folder is the date."""
    day = sessions / date
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in sorted(day.rglob("*")):
            zf.write(f, f.relative_to(sessions).as_posix())
    return out


@pytest.fixture
def workspace(tmp_path: Path) -> Path:
    for d in ("inbox", "vault/raw", "vault/talks", "vault/schedule", "kb"):
        (tmp_path / d).mkdir(parents=True)
    return tmp_path


@pytest.fixture
def device_dir(tmp_path: Path) -> Path:
    """Stands in for an iPhone's Documents/sessions folder."""
    p = tmp_path / "device" / "sessions"
    p.mkdir(parents=True)
    return p


def harness_iphone(sessions: Path) -> BundleBuilder:
    """The architecture's worked example: speaker started 09:03:00.120, photo 4 min 12 s into the talk."""
    b = BundleBuilder(sessions, "iphone", HARNESS, "2026-11-16T16:57:41.002Z")
    b.add("speaker_start", "2026-11-16T17:03:00.120Z")
    b.photo("2026-11-16T17:07:12.380Z", shade=40)
    m = b.add("moment", "2026-11-16T17:14:40.010Z")
    b.add("tag", "2026-11-16T17:14:42.700Z", target=m, tag="idea")
    n = b.add("note", "2026-11-16T17:15:05.200Z", text="Check this against our harness doc.",
              saved_utc="2026-11-16T17:15:31.900Z")
    b.add("edit", "2026-11-16T17:20:00.000Z", target=n, text="Check this against our harness architecture doc.")
    p2 = b.photo("2026-11-16T17:21:00.000Z", shade=200)
    b.add("delete", "2026-11-16T17:21:03.000Z", target=p2)
    b.add("session_close", "2026-11-16T18:11:30.550Z", reason="user")
    b.voice("2026-11-16T18:14:12.000Z")
    return b
