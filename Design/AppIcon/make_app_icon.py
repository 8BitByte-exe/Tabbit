#!/usr/bin/env python3
"""Turns the app icon artwork into the 1024x1024 PNG used by the asset catalog.

The source artwork (app-icon-source.png) is already a full-bleed square tile
with a light background and room around the bunny and its hole, so iOS's
rounded mask doesn't clip anything. This script only:
  1. flattens any transparency onto the artwork's background color,
  2. center-crops to a square if the source isn't one,
  3. scales to 1024x1024 and saves an opaque RGB PNG.

Usage: python3 make_app_icon.py <source image> <output png>
Needs Pillow (pip install pillow). Not part of the CI build.
"""
import sys

from PIL import Image

SIZE = 1024


def main(source_path, output_path):
    image = Image.open(source_path).convert("RGBA")
    background = Image.new("RGBA", image.size, image.getpixel((0, 0))[:3] + (255,))
    image = Image.alpha_composite(background, image).convert("RGB")

    width, height = image.size
    side = min(width, height)
    left = (width - side) // 2
    top = (height - side) // 2
    image = image.crop((left, top, left + side, top + side))

    image = image.resize((SIZE, SIZE), Image.LANCZOS)
    image.save(output_path, "PNG", optimize=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
