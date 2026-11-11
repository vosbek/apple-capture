#!/usr/bin/env python3
"""Transcribe voice reflections locally with faster-whisper (optional step).

Nothing leaves the machine. Reflections are one speaker (Matt), so no diarization and no
Hugging Face token are needed (architecture.md section 5). Permitted session audio under
audio/ is NOT handled here; WhisperX with diarization is the plan for that.

Install (WSL Ubuntu or Windows, Python 3.11+):
    python -m venv .venv && . .venv/bin/activate        # Windows: .venv\\Scripts\\activate
    pip install faster-whisper
CPU works out of the box:          --device cpu --compute-type int8
NVIDIA GPU under WSL2: install only the Windows NVIDIA driver (no Linux driver in WSL), then
    pip install nvidia-cublas-cu12 nvidia-cudnn-cu12==9.*
    export LD_LIBRARY_PATH=$(python -c 'import os, nvidia.cublas.lib, nvidia.cudnn.lib; \
print(os.path.dirname(nvidia.cublas.lib.__file__) + ":" + os.path.dirname(nvidia.cudnn.lib.__file__))')
(See the faster-whisper README if the CUDA libraries change; this is the step most likely to need fixing.)

Usage:
    python tools/transcribe.py                 # every talk with untranscribed reflections
    python tools/transcribe.py harness-new-operating-system --model medium.en
    python tools/ingest.py                     # afterwards: folds transcripts into notes.md

Writes voice/<name>.txt and voice/<name>.segments.json next to each recording.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

AUDIO_EXT = {".m4a", ".mp3", ".wav", ".aac", ".caf"}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("talks", nargs="*", help="talk ids (default: all)")
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    ap.add_argument("--model", default="small.en", help="tiny.en, base.en, small.en, medium.en, large-v3 ...")
    ap.add_argument("--device", default="auto", help="auto, cpu or cuda")
    ap.add_argument("--compute-type", default="default", help="default, int8, float16 ...")
    ap.add_argument("--force", action="store_true", help="re-transcribe even if a .txt exists")
    args = ap.parse_args(argv)

    talks_root = args.root / "vault" / "talks"
    dirs = [talks_root / t for t in args.talks] if args.talks else sorted(p for p in talks_root.iterdir() if p.is_dir())
    todo = []
    for d in dirs:
        for f in sorted((d / "voice").glob("*")) if (d / "voice").exists() else []:
            if f.suffix.lower() in AUDIO_EXT and (args.force or not f.with_suffix(".txt").exists()):
                todo.append(f)
    if not todo:
        print("Nothing to transcribe.")
        return 0
    try:
        from faster_whisper import WhisperModel  # type: ignore
    except ImportError:
        print("faster-whisper is not installed: pip install faster-whisper (see the docstring).", file=sys.stderr)
        return 1

    model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)
    for f in todo:
        segments, info = model.transcribe(str(f), beam_size=5, vad_filter=True, language="en")
        segs = [{"start": round(s.start, 2), "end": round(s.end, 2), "text": s.text.strip()} for s in segments]
        f.with_suffix(".txt").write_text(" ".join(s["text"] for s in segs).strip() + "\n", encoding="utf-8")
        f.with_suffix(".segments.json").write_text(json.dumps(
            {"model": args.model, "duration": round(info.duration, 2), "segments": segs}, indent=1) + "\n",
            encoding="utf-8")
        print(f"transcribed {f.relative_to(args.root)} ({info.duration:.0f} s)")
    print("Now re-run tools/ingest.py so notes.md includes the transcripts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
