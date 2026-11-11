from __future__ import annotations

import json
from pathlib import Path

import pytest

import publish_gate

BRIEF = """---
schema: qcon.brief/1
talk_id: harness-new-operating-system
title: The Harness Is the New Operating System
speakers: [{ name: Manju Rajashekhar, company: Mad Labs, role: Founder & CEO }]
event: QCon San Francisco 2026
date: 2026-11-16
kind: keynote
visibility: shareable
status: {status}            # draft | reviewed | published
reviewed_by: Matt
---

## In one paragraph
The speaker framed the harness as an operating system for agents [S07].

## Evidence
- The project is Apache-2.0 licensed [R2].
{extra}
"""


def make_kb(root: Path, status: str = "reviewed", extra: str = "") -> Path:
    kb = root / "kb"
    (kb / "talks" / "2026-11-16").mkdir(parents=True)
    (kb / "assets" / "slides" / "harness-new-operating-system").mkdir(parents=True)
    (kb / "README.md").write_text("# QCon SF 2026\n\nStart with actions.md.\n")
    (kb / "talks" / "2026-11-16" / "harness-new-operating-system.md").write_text(
        BRIEF.replace("{status}", status).replace("{extra}", extra))
    (kb / "assets" / "slides" / "harness-new-operating-system" / "S07.jpg").write_bytes(b"\xff\xd8 small \xff\xd9")
    (root / "vault" / "talks").mkdir(parents=True, exist_ok=True)
    return kb


def private_talk(root: Path, talk_id: str) -> None:
    d = root / "vault" / "talks" / talk_id
    d.mkdir(parents=True)
    (d / "talk.json").write_text(json.dumps({"talk": {"talk_id": talk_id, "kind": "adhoc"},
                                             "visibility": "private", "all_bundles_private": True}))


def fails(root: Path) -> list[str]:
    return [f"{f.path}: {f.message}" for f in publish_gate.check(root / "kb", root / "vault") if f.level == "FAIL"]


def test_clean_kb_passes(tmp_path):
    make_kb(tmp_path)
    assert fails(tmp_path) == []
    assert publish_gate.main(["--kb", str(tmp_path / "kb"), "--vault", str(tmp_path / "vault")]) == 0


def test_published_status_passes(tmp_path):
    make_kb(tmp_path, status="published")
    assert fails(tmp_path) == []


def test_draft_brief_fails(tmp_path):
    make_kb(tmp_path, status="draft")
    assert any("status is 'draft'" in f for f in fails(tmp_path))
    assert publish_gate.main(["--kb", str(tmp_path / "kb"), "--vault", str(tmp_path / "vault")]) == 1


def test_brief_without_front_matter_fails(tmp_path):
    kb = make_kb(tmp_path)
    (kb / "talks" / "2026-11-16" / "loose.md").write_text("# Notes\nNo header.\n")
    assert any("without front matter" in f for f in fails(tmp_path))


@pytest.mark.parametrize("name", ["reflection.m4a", "session.mp3", "talk.wav", "clip.mov"])
def test_audio_or_video_file_fails(tmp_path, name):
    kb = make_kb(tmp_path)
    (kb / "assets" / name).write_bytes(b"\x00")
    assert any("audio or video" in f for f in fails(tmp_path))


@pytest.mark.parametrize("name", ["timeline.jsonl", "notes.md", "manifest.json", "events.jsonl"])
def test_raw_capture_files_fail(tmp_path, name):
    kb = make_kb(tmp_path)
    (kb / "talks" / name).write_text("{}\n")
    assert any("raw capture data" in f for f in fails(tmp_path))


def test_transcript_fails(tmp_path):
    kb = make_kb(tmp_path)
    (kb / "speakers").mkdir()
    (kb / "speakers" / "reflection-transcript.md").write_text("words\n")
    assert any("transcript" in f for f in fails(tmp_path))


def test_private_visibility_front_matter_fails(tmp_path):
    kb = make_kb(tmp_path)
    (kb / "themes").mkdir()
    (kb / "themes" / "golden-paths.md").write_text("---\nvisibility: private\nstatus: reviewed\n---\n# Theme\n")
    assert any("visibility: private" in f for f in fails(tmp_path))


def test_audio_mark_fails(tmp_path):
    make_kb(tmp_path, extra="- The speaker said it twice [A 23:10].\n")
    assert any("session-audio mark" in f for f in fails(tmp_path))


def test_reference_to_private_talk_fails(tmp_path):
    make_kb(tmp_path, extra="- Compare with what we heard at adhoc-20261116-1230.\n")
    private_talk(tmp_path, "adhoc-20261116-1230")
    assert any("private talk adhoc-20261116-1230" in f for f in fails(tmp_path))


def test_brief_for_private_talk_fails(tmp_path):
    kb = make_kb(tmp_path)
    private_talk(tmp_path, "unconference-modern-api-design")
    (kb / "talks" / "2026-11-16" / "unconference-modern-api-design.md").write_text(
        "---\ntalk_id: unconference-modern-api-design\nstatus: reviewed\n---\n# x\n")
    (kb / "assets" / "slides" / "unconference-modern-api-design").mkdir()
    (kb / "assets" / "slides" / "unconference-modern-api-design" / "S01.jpg").write_bytes(b"x")
    out = fails(tmp_path)
    assert any("is private" in f for f in out)
    assert any("slide from private talk" in f for f in out)


def test_uncited_slide_fails(tmp_path):
    kb = make_kb(tmp_path)
    (kb / "assets" / "slides" / "harness-new-operating-system" / "S08.jpg").write_bytes(b"x")
    out = fails(tmp_path)
    assert any("S08.jpg" in f and "not cited" in f for f in out)
    assert not any("S07.jpg" in f for f in out)


def test_large_slide_only_warns(tmp_path):
    kb = make_kb(tmp_path)
    (kb / "assets" / "slides" / "harness-new-operating-system" / "S07.jpg").write_bytes(b"x" * 1_200_000)
    findings = publish_gate.check(kb, tmp_path / "vault")
    assert [f.level for f in findings] == ["WARN"]


def test_git_directory_is_ignored(tmp_path):
    kb = make_kb(tmp_path)
    (kb / ".git" / "objects").mkdir(parents=True)
    (kb / ".git" / "objects" / "blob.wav").write_bytes(b"x")
    assert fails(tmp_path) == []
