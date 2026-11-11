#!/usr/bin/env python3
"""Copy a slide photo into kb/ downscaled (long edge 1600 px, JPEG quality 80). Needs Pillow.

    python tools/downscale.py vault/talks/<id>/photos/S07.jpg kb/assets/slides/<id>/S07.jpg
"""
from __future__ import annotations

import sys
from pathlib import Path


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        from PIL import Image, ImageOps
    except ImportError:
        print("Pillow is required: pip install pillow", file=sys.stderr)
        return 1
    src, dest = Path(argv[0]), Path(argv[1])
    dest.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as im:
        im = ImageOps.exif_transpose(im).convert("RGB")  # upright, and drops EXIF (location, device)
        im.thumbnail((1600, 1600))
        im.save(dest.with_suffix(".jpg"), "JPEG", quality=80)
    print(f"{src} -> {dest.with_suffix('.jpg')}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
