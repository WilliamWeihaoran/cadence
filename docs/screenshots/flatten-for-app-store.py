#!/usr/bin/env python3
"""Turn a `screencapture -o -l<windowid>` PNG into an App Store Connect upload.

`screencapture` hands back the window's own shape: the rounded corners are
transparent, and App Store Connect rejects a macOS screenshot with an alpha
channel. This flattens onto an opaque canvas of exactly one of Apple's four
accepted macOS sizes and writes RGB with no alpha.

    python3 docs/screenshots/flatten-for-app-store.py raw.png today.png

By default it keeps the capture's own size when that size is already an
accepted one, and otherwise centres the capture on the smallest accepted
canvas that fits it.
"""

import argparse
import sys

from PIL import Image

# App Store Connect's accepted macOS screenshot sizes, in pixels.
ACCEPTED = [(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)]

# The window background behind the rounded corners. Cadence's chrome is dark, so
# a near-black canvas hides the corner fill instead of ringing it in white.
DEFAULT_BACKGROUND = (28, 28, 30)


def choose_canvas(size: tuple[int, int]) -> tuple[int, int]:
    if size in ACCEPTED:
        return size
    fits = [c for c in ACCEPTED if c[0] >= size[0] and c[1] >= size[1]]
    if not fits:
        raise SystemExit(
            f"capture is {size[0]}x{size[1]}px, larger than every accepted macOS size {ACCEPTED}. "
            "Resize the window before capturing."
        )
    return min(fits, key=lambda c: c[0] * c[1])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source")
    parser.add_argument("destination")
    parser.add_argument("--background", default=",".join(str(v) for v in DEFAULT_BACKGROUND),
                        help="R,G,B canvas colour behind the window's rounded corners.")
    args = parser.parse_args()

    background = tuple(int(part) for part in args.background.split(","))
    if len(background) != 3:
        raise SystemExit("--background wants three comma-separated 0-255 values.")

    image = Image.open(args.source).convert("RGBA")
    canvas_size = choose_canvas(image.size)
    canvas = Image.new("RGB", canvas_size, background)
    offset = ((canvas_size[0] - image.size[0]) // 2, (canvas_size[1] - image.size[1]) // 2)
    canvas.paste(image, offset, image)
    canvas.save(args.destination, format="PNG")
    print(f"{args.source} {image.size[0]}x{image.size[1]} -> {args.destination} {canvas_size[0]}x{canvas_size[1]} RGB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
