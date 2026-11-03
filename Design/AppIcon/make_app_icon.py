#!/usr/bin/env python3
"""Turns the app icon artwork into the 1024x1024 PNG used by the asset catalog.

The source artwork (app-icon-source.jpg) shows the icon as a rounded tile on a
black background. iOS wants a full-bleed square and applies its own rounded
mask, so this script:
  1. crops to the tile, just inside its shaded edge (bevel),
  2. repaints the rounded corners of the old tile (black background and the
     shaded edge) with the tile's own color; only the corner areas outside the
     tile's curve are touched, never the artwork,
  3. adds a 6% margin by extending the tile's background outward, so iOS's
     rounded mask doesn't cut off the artwork (the hole nearly touches the edges),
  4. scales to 1024x1024 and saves an opaque RGB PNG.

Usage: python3 make_app_icon.py <source image> <output png>
Needs Pillow (pip install pillow). Not part of the CI build.
"""
import sys

from PIL import Image, ImageFilter, ImageStat

DARK = 60      # pixels darker than this (0-255) count as background
BEVEL = 14     # pixels to trim inside the tile edge
PAD = 0.06     # extra background on each side, as a fraction of the tile, so iOS's
               # rounded mask doesn't clip the artwork (the hole reaches the edges)
SIZE = 1024


def main(source_path, output_path):
    image = Image.open(source_path).convert("RGB")
    grey = image.convert("L")
    box = grey.point(lambda v: 255 if v > DARK else 0).getbbox()
    if box is None:
        sys.exit("No artwork found (image is all dark).")
    x0, y0, x1, y1 = box
    x0, y0, x1, y1 = x0 + BEVEL, y0 + BEVEL, x1 - BEVEL, y1 - BEVEL
    side = min(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    tile = image.crop((cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side))

    # Repaint each rounded corner of the old tile with the tile's own color, so no
    # black (or the old tile's shaded edge) is left in the corners.
    # The corner curve is estimated from the source: along the diagonal, how far the
    # artwork starts from the tile's bounding-box corner gives the corner radius
    # (circle model: inset = r * (1 - 1/sqrt 2)).
    w, h = tile.size
    left, top = cx - side // 2, cy - side // 2
    along = int(side * 0.25)
    edge = 6
    corners = [
        # (bbox corner in source, diagonal step, crop corner, fill samples along the two edges)
        ((box[0], box[1]), (1, 1), (0, 0), [(along, edge), (edge, along)]),
        ((box[2] - 1, box[1]), (-1, 1), (w - 1, 0), [(w - 1 - along, edge), (w - 1 - edge, along)]),
        ((box[0], box[3] - 1), (1, -1), (0, h - 1), [(along, h - 1 - edge), (edge, h - 1 - along)]),
        ((box[2] - 1, box[3] - 1), (-1, -1), (w - 1, h - 1), [(w - 1 - along, h - 1 - edge), (w - 1 - edge, h - 1 - along)]),
    ]
    pixels = tile.load()
    for (bx, by), (dx, dy), (kx, ky), samples in corners:
        inset = 0
        while inset < side // 2 and grey.getpixel((bx + dx * inset, by + dy * inset)) < 200:
            inset += 1
        radius = inset / (1 - 2 ** -0.5)
        # Circle center in crop coordinates (the crop starts BEVEL px inside the bbox).
        center_x = kx + dx * (radius - BEVEL)
        center_y = ky + dy * (radius - BEVEL)
        samples_rgb = []
        for sx, sy in samples:
            patch = tile.crop((sx - 4, sy - 4, sx + 4, sy + 4))
            samples_rgb.append(ImageStat.Stat(patch).median)
        color = tuple(int(round(sum(c[i] for c in samples_rgb) / len(samples_rgb))) for i in range(3))
        reach = int(radius) + 2
        for oy in range(reach):
            for ox in range(reach):
                x, y = kx + dx * ox, ky + dy * oy
                if not (0 <= x < w and 0 <= y < h):
                    continue
                # Only the corner quadrant beyond the circle center, outside the curve
                # (minus a few pixels to remove the anti-aliased shaded edge).
                if (x - center_x) * dx > 0 or (y - center_y) * dy > 0:
                    continue
                if ((x - center_x) ** 2 + (y - center_y) ** 2) ** 0.5 > radius - 5:
                    pixels[x, y] = color

    tile = pad_with_background(tile, int(round(side * PAD)))
    tile = tile.resize((SIZE, SIZE), Image.LANCZOS)
    tile.save(output_path, "PNG", optimize=True)
    print(f"Wrote {output_path}: {tile.size[0]}x{tile.size[1]} from crop {side}px at {box}")


def pad_with_background(tile, pad):
    """Grows the image by `pad` px on each side, continuing the background at each
    edge: the outermost few rows/columns are averaged and softened, then stretched
    outward (no streaks from single noisy pixels)."""
    if pad <= 0:
        return tile
    w, h = tile.size
    strip = 8
    out = Image.new("RGB", (w + 2 * pad, h + 2 * pad))
    out.paste(tile, (pad, pad))

    def edge_band(box, size, horizontal):
        band = tile.crop(box)
        band = band.resize((band.width, 1) if horizontal else (1, band.height), Image.BOX)
        band = band.resize((band.width, 9) if horizontal else (9, band.height), Image.NEAREST)
        band = band.filter(ImageFilter.GaussianBlur(3))
        mid = band.crop((0, 4, band.width, 5)) if horizontal else band.crop((4, 0, 5, band.height))
        return mid.resize(size, Image.NEAREST)

    out.paste(edge_band((0, 0, w, strip), (w, pad), True), (pad, 0))
    out.paste(edge_band((0, h - strip, w, h), (w, pad), True), (pad, h + pad))
    out.paste(edge_band((0, 0, strip, h), (pad, h), False), (0, pad))
    out.paste(edge_band((w - strip, 0, w, h), (pad, h), False), (w + pad, pad))
    for (cx, cy), (ox, oy) in [((0, 0), (0, 0)), ((w - 1, 0), (w + pad, 0)),
                               ((0, h - 1), (0, h + pad)), ((w - 1, h - 1), (w + pad, h + pad))]:
        patch = tile.crop((max(cx - 8, 0), max(cy - 8, 0), min(cx + 8, w), min(cy + 8, h)))
        color = tuple(int(round(c)) for c in ImageStat.Stat(patch).median)
        out.paste(Image.new("RGB", (pad, pad), color), (ox, oy))
    return out


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
