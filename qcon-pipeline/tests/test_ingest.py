from __future__ import annotations

import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

import pytest

import build_schedule
import ingest
from conftest import HARNESS, UNCONF, BundleBuilder, harness_iphone, tiny_jpeg, zip_day

TALK = "harness-new-operating-system"


def run(workspace: Path, *args: str) -> int:
    return ingest.main([*args, "--root", str(workspace)])


def timeline(workspace: Path, talk_id: str = TALK) -> list[dict]:
    path = workspace / "vault" / "talks" / talk_id / "timeline.jsonl"
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def talk_json(workspace: Path, talk_id: str = TALK) -> dict:
    return json.loads((workspace / "vault" / "talks" / talk_id / "talk.json").read_text(encoding="utf-8"))


def test_single_bundle_from_zip(workspace, device_dir):
    b = harness_iphone(device_dir).write(closed="2026-11-16T18:11:30.550Z")
    z = zip_day(device_dir, "2026-11-16", workspace / "inbox" / "collector_2026-11-16_iphone.zip")

    assert run(workspace) == 0  # default input: everything in inbox/
    assert (workspace / "vault" / "raw" / "2026-11-16" / b.folder / "events.jsonl").exists()

    tl = timeline(workspace)
    by_type = {}
    for e in tl:
        by_type.setdefault(e["type"], []).append(e)
    # tag/edit/delete are applied, not carried
    assert not {"tag", "edit", "delete"} & set(by_type)
    photo = by_type["photo"]
    assert len(photo) == 1, "deleted photo must be dropped"
    # architecture example: photo at t_ms 432380, speaker started at 180120 -> 4:12.260 into the talk
    assert photo[0]["talk_ms"] == 432380 - 180120
    assert photo[0]["ref"] == "S01"
    assert by_type["moment"][0]["tag"] == "idea" and by_type["moment"][0]["ref"] == "M1"
    assert by_type["note"][0]["text"] == "Check this against our harness architecture doc."
    assert by_type["voice"][0]["ref"] == "V1"
    assert all("talk_ms" in e and e["bundle"] == b.bundle_id for e in tl)

    info = talk_json(workspace)
    assert info["counts"] == {"photo": 1, "moment": 1, "note": 1, "voice": 1, "audio_segment": 0}  # rebuilt, not 99
    assert info["start_synced"] is True and info["visibility"] == "shareable"
    talk_dir = workspace / "vault" / "talks" / TALK
    assert (talk_dir / "photos" / "S01.jpg").exists()
    assert not (talk_dir / "photos" / "S02.jpg").exists()
    assert (talk_dir / "voice" / Path(by_type["voice"][0]["file"]).name).exists()
    notes = (talk_dir / "notes.md").read_text(encoding="utf-8")
    assert "| S01 | +4:12 |" in notes and "| M1 |" in notes and "not transcribed yet" in notes
    assert z.exists()


def test_truncated_last_line_is_dropped(workspace, device_dir):
    b = harness_iphone(device_dir)
    b.write(truncated_tail='{"seq":99,"id":"iphone-0099","type":"mom')
    assert run(workspace, str(device_dir / "2026-11-16")) == 0
    info = talk_json(workspace)
    assert any("truncated last line dropped" in p for p in info["problems"])
    assert info["counts"]["moment"] == 1


def test_iphone_and_ipad_merge_by_talk_and_time(workspace, device_dir):
    harness_iphone(device_dir).write()
    ipad = BundleBuilder(device_dir, "ipad", HARNESS, "2026-11-16T16:58:00.000Z")
    ipad.add("speaker_start", "2026-11-16T17:03:02.000Z")
    ipad.add("note", "2026-11-16T17:10:00.000Z", text="Five planes, evidence is the hard one.",
             saved_utc="2026-11-16T17:10:20.000Z")
    ipad.add("moment", "2026-11-16T17:14:41.000Z")
    ipad.write()
    zip_day(device_dir, "2026-11-16", workspace / "inbox" / "day1.zip")

    assert run(workspace) == 0
    info = talk_json(workspace)
    assert info["devices"] == ["ipad", "iphone"]
    assert info["measured_skew_ms"] == 1880
    assert info["speaker_start_utc"] == "2026-11-16T17:03:00.120Z"  # the earlier one
    tl = timeline(workspace)
    stamps = [e["ts_utc"] for e in tl]
    assert stamps == sorted(stamps)
    ids = [e["id"] for e in tl]
    assert len(ids) == len(set(ids)), "ids stay unique across devices"
    notes = [e for e in tl if e["type"] == "note"]
    assert [n["id"].split("-")[0] for n in notes] == ["ipad", "iphone"]
    assert [n["ref"] for n in notes] == ["N1", "N2"]
    assert info["counts"]["moment"] == 2


def test_rerun_is_idempotent_and_superset_updates(workspace, device_dir):
    b = BundleBuilder(device_dir, "iphone", HARNESS, "2026-11-16T16:57:41.002Z")
    b.add("speaker_start", "2026-11-16T17:03:00.120Z")
    b.photo("2026-11-16T17:07:12.380Z", shade=40)
    b.write()
    first = zip_day(device_dir, "2026-11-16", workspace / "first.zip")
    assert run(workspace, str(first)) == 0
    tl1 = timeline(workspace)
    assert run(workspace, str(first)) == 0
    assert timeline(workspace) == tl1, "re-running on the same export changes nothing"

    # Later in the evening: more captures, exported again (a superset).
    b.photo("2026-11-16T17:30:00.000Z", shade=220)
    b.add("moment", "2026-11-16T17:31:00.000Z")
    b.write()
    second = zip_day(device_dir, "2026-11-16", workspace / "second.zip")
    report = ingest.Report()
    ingest.import_inputs([second], workspace, report)
    assert report.imported == [f"{b.bundle_id} (updated)"]
    ingest.rebuild_talks(workspace, report)
    tl2 = timeline(workspace)
    assert [e["ref"] for e in tl2 if e["type"] == "photo"] == ["S01", "S02"]
    assert tl2[0]["ts_utc"] == tl1[0]["ts_utc"]

    # The older export arriving late does not overwrite the newer copy.
    report = ingest.Report()
    ingest.import_inputs([first], workspace, report)
    assert report.skipped and "older export" in report.skipped[0]
    assert not report.conflicts


def test_refs_stay_stable_when_an_earlier_photo_appears(workspace, device_dir):
    ipad = BundleBuilder(device_dir, "ipad", HARNESS, "2026-11-16T16:58:00.000Z")
    ipad.write()
    iphone = BundleBuilder(device_dir, "iphone", HARNESS, "2026-11-16T16:57:41.002Z")
    iphone.photo("2026-11-16T17:20:00.000Z", shade=90)
    iphone.write()
    assert run(workspace, str(device_dir / "2026-11-16" / iphone.folder)) == 0
    assert [e["ref"] for e in timeline(workspace) if e["type"] == "photo"] == ["S01"]
    ipad.photo("2026-11-16T17:05:00.000Z", shade=10)  # earlier in time, ingested later
    ipad.write()
    assert run(workspace, str(device_dir / "2026-11-16" / ipad.folder)) == 0
    photos = {e["id"]: e["ref"] for e in timeline(workspace) if e["type"] == "photo"}
    assert photos["iphone-0002"] == "S01" and photos["ipad-0002"] == "S02"


def test_conflicting_export_is_kept_aside(workspace, device_dir):
    b = harness_iphone(device_dir).write()
    assert run(workspace, str(device_dir / "2026-11-16")) == 0
    lines = (b.dir / "events.jsonl").read_text().splitlines()
    lines[2] = lines[2].replace("17:07:12.380Z", "17:07:13.000Z")  # history rewritten: not a superset
    (b.dir / "events.jsonl").write_text("\n".join(lines) + "\n")
    assert run(workspace, str(device_dir / "2026-11-16")) == 2
    conflicts = list((workspace / "vault" / "raw" / "2026-11-16" / "_conflicts").iterdir())
    assert len(conflicts) == 1


def test_unconference_is_private(workspace, device_dir):
    u = BundleBuilder(device_dir, "iphone", UNCONF, "2026-11-16T22:36:00.000Z")
    u.add("note", "2026-11-16T22:40:00.000Z", text="Peer story, keep private.", saved_utc="2026-11-16T22:40:09.000Z")
    u.write()
    assert run(workspace, str(device_dir)) == 0
    info = talk_json(workspace, UNCONF["talk_id"])
    assert info["visibility"] == "private" and info["all_bundles_private"] is True


def test_media_missing_and_bad_seq_are_reported(workspace, device_dir):
    b = harness_iphone(device_dir)
    b.events[2]["file"] = "photos/9999_photo_000000Z.jpg"
    b.events[4]["seq"] = 2
    b.write()
    assert run(workspace, str(device_dir)) == 0
    problems = " ".join(talk_json(workspace)["problems"])
    assert "missing" in problems and "not increasing" in problems


def test_exif_parser_reads_original_time_and_offset(tmp_path):
    p = tmp_path / "a.jpg"
    p.write_bytes(tiny_jpeg("2026:11:16 09:10:00", "-08:00"))
    assert ingest.exif_datetime(p) == datetime(2026, 11, 16, 17, 10, tzinfo=timezone.utc)
    q = tmp_path / "b.jpg"
    q.write_bytes(tiny_jpeg("2026:11:16 09:10:00"))  # no offset: conference time assumed
    assert ingest.exif_datetime(q).astimezone(timezone.utc).hour == 17
    r = tmp_path / "c.jpg"
    r.write_bytes(b"not a jpeg")
    assert ingest.exif_datetime(r) is None


def _schedule(workspace: Path) -> None:
    dataset = Path(__file__).resolve().parent.parent / "vault" / "schedule" / "qconsf-2026-schedule.json"
    sched = build_schedule.build(json.loads(dataset.read_text(encoding="utf-8")), "2026-11-13T00:00:00Z")
    (workspace / "vault" / "schedule" / "schedule.json").write_text(json.dumps(sched), encoding="utf-8")


def test_fallback_notes_photos_and_voice(workspace):
    _schedule(workspace)
    fb = workspace / "inbox" / "fallback"
    (fb / "photos").mkdir(parents=True)
    (fb / "voice").mkdir()
    (fb / "notes.txt").write_text("\n".join([
        "2026-11-16T09:03:00-08:00 | TALK harness",
        "2026-11-16T09:14:40-08:00 | ",
        "2026-11-16T09:15:00-08:00 | idea",
        "2026-11-16T09:15:30-08:00 | .",
        "2026-11-16T09:16:00-08:00 | Evidence plane is the hard part.",
        "2026-11-16T12:30:00-08:00 | TALK Lunch table platform folks",
        "2026-11-16T12:31:00-08:00 | Someone runs 40 golden paths.",
        "not a line",
    ]) + "\n", encoding="utf-8")
    (fb / "photos" / "IMG_0001.JPG").write_bytes(tiny_jpeg("2026:11:16 09:10:00", "-08:00"))
    (fb / "photos" / "IMG_0002.JPG").write_bytes(tiny_jpeg("2026:11:16 08:00:00", "-08:00"))  # before any talk
    voice = fb / "voice" / "Harness new operating system reflection.m4a"
    voice.write_bytes(b"fake")
    t = datetime(2026, 11, 16, 18, 15, tzinfo=timezone.utc).timestamp()
    os.utime(voice, (t, t))

    assert run(workspace, "--fallback") == 0
    info = talk_json(workspace)
    assert info["devices"] == ["fallback"]
    assert info["counts"] == {"photo": 1, "moment": 3, "note": 1, "voice": 1, "audio_segment": 0}
    assert info["start_synced"] is True
    tl = timeline(workspace)
    photo = next(e for e in tl if e["type"] == "photo")
    assert photo["talk_ms"] == 7 * 60 * 1000  # 09:10 photo, TALK typed at 09:03
    assert next(e for e in tl if e["type"] == "moment" and e.get("tag")).get("tag") == "idea"

    adhoc = talk_json(workspace, "adhoc-20261116-1230")
    assert adhoc["visibility"] == "private" and adhoc["counts"]["note"] == 1
    unassigned = talk_json(workspace, "unassigned-20261116")
    assert unassigned["counts"]["photo"] == 1
    report = json.loads((workspace / "vault" / "ingest-report.json").read_text())
    assert any("no '|' separator" in p for p in report["problems"])

    # Re-running regenerates the synthetic bundles without duplicating captures.
    assert run(workspace, "--fallback") == 0
    assert talk_json(workspace)["counts"]["moment"] == 3


def test_fallback_and_app_bundles_merge(workspace, device_dir):
    _schedule(workspace)
    harness_iphone(device_dir).write()
    fb = workspace / "inbox" / "fallback"
    fb.mkdir(parents=True)
    (fb / "notes.txt").write_text("2026-11-16T09:03:01-08:00 | TALK harness-new-operating-system\n"
                                  "2026-11-16T09:20:00-08:00 | From the Shortcut\n", encoding="utf-8")
    assert run(workspace, "--fallback") == 0
    assert run(workspace, str(device_dir)) == 0
    info = talk_json(workspace)
    assert info["devices"] == ["fallback", "iphone"]
    assert info["measured_skew_ms"] == 880


def test_build_schedule_contract():
    dataset = Path(__file__).resolve().parent.parent / "vault" / "schedule" / "qconsf-2026-schedule.json"
    data = json.loads(dataset.read_text(encoding="utf-8"))
    sched = build_schedule.build(data, "2026-11-13T00:00:00Z")
    talks = {t["talk_id"]: t for t in sched["talks"]}
    assert sched["schema"] == "collector.schedule/1" and len(talks) == 119
    k = talks["harness-new-operating-system"]
    assert k["kind"] == "keynote" and k["start"] == "2026-11-16T09:00:00-08:00" and k["end"] == "2026-11-16T10:10:00-08:00"
    assert k["speakers"][0] == {"name": "Manju Rajashekhar", "company": "Mad Labs", "role": "Founder & CEO",
                                "speaker_url": "https://qconsf.com/speakers/manjurajashekhar"}
    assert talks["unconference-architectures-youve-always-wondered-about"]["kind"] == "unconference"
    assert talks["unconference-architectures-youve-always-wondered-about"]["private_by_default"] is True
    assert talks["sponsored-session-4"]["kind"] == "sponsored"
    assert sum(t["no_video"] for t in talks.values()) == 33
    assert {t["kind"] for t in talks.values()} == {"keynote", "presentation", "sponsored", "unconference", "training"}
    bad = json.loads(json.dumps(data))
    bad["sessions"][0]["start"] = None
    with pytest.raises(build_schedule.ScheduleError):
        build_schedule.build(bad)


def test_near_duplicate_photos_are_flagged(workspace, device_dir):
    pytest.importorskip("PIL")
    b = BundleBuilder(device_dir, "iphone", HARNESS, "2026-11-16T16:57:41.002Z")
    b.photo("2026-11-16T17:05:00.000Z", shade=40)
    b.photo("2026-11-16T17:05:02.000Z", shade=40)   # same slide twice
    b.photo("2026-11-16T17:09:00.000Z", shade=210)
    b.write()
    assert run(workspace, str(device_dir)) == 0
    index = json.loads((workspace / "vault" / "talks" / TALK / "photos" / "index.json").read_text())
    assert [i.get("near_duplicate_of") for i in index] == [None, "S01", None]
