"""Prepare a character from an A-pose turnaround sheet (front, side facing right, back).

    tools/triposr_tmp/venv/Scripts/python.exe tools/apose_prep.py nanay

Writes into tools/triposr_tmp/apose/<name>/:
    source.png  the front view on grey, for TripoSR (run it with --no-remove-bg)
    atlas.png   front | back | side, each cut to the figure and stretched to its tile, used by
                tools/blender/make_apose.py to paint the sheet art onto the 3D shape
    info.json   the front figure's box on the sheet (to turn landmark pixels into meters)
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
SHEETS = {"nanay": {"file": "reference/nanay_sheet.webp",
                    "front": (5, 112, 385, 940), "side": (625, 112, 805, 940), "back": (825, 112, 1100, 940)}}
TILE = (512, 1024)


def cut_out(sheet, box):
    """(rgb array, figure mask) with the plain cream background removed by flood fill."""
    im = np.array(sheet.crop(box)).astype(int)
    cream = (im.min(axis=2) > 188) & (im[:, :, 0] - im[:, :, 2] > 6) & (im[:, :, 0] - im[:, :, 2] < 50)
    regions, _ = ndimage.label(cream)
    border = np.unique(np.concatenate([regions[0], regions[-1], regions[:, 0], regions[:, -1]]))
    sizes = np.bincount(regions.ravel())
    background = np.isin(regions, np.union1d(border, np.nonzero(sizes > 400)[0])) & cream
    figure, _ = ndimage.label(ndimage.binary_opening(~background, iterations=1))
    sizes = np.bincount(figure.ravel())
    sizes[0] = 0
    return im.astype(np.uint8), figure == sizes.argmax()


def main():
    name = sys.argv[1]
    spec = SHEETS[name]
    out = ROOT / "tools/triposr_tmp/apose" / name
    out.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(ROOT / spec["file"]).convert("RGB")
    atlas = Image.new("RGB", (TILE[0] * 3, TILE[1]))
    for i, view in enumerate(("front", "back", "side")):
        rgb, mask = cut_out(sheet, spec[view])
        ys, xs = np.nonzero(mask)
        x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
        rgb, mask = rgb[y0:y1, x0:x1], mask[y0:y1, x0:x1]
        # spread the figure's colors outward, so edges never pick up the background
        solid = ndimage.binary_erosion(mask, iterations=7)   # drop the drawing's dark outline
        _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
        atlas.paste(Image.fromarray(rgb[iy, ix]).resize(TILE, Image.LANCZOS), (i * TILE[0], 0))
        if view == "front":
            grey = np.full_like(rgb, 128)
            grey[mask] = rgb[mask]
            fig = Image.fromarray(grey)
            side = int(max(fig.size) / 0.85)
            square = Image.new("RGB", (side, side), (128, 128, 128))
            square.paste(fig, ((side - fig.width) // 2, (side - fig.height) // 2))
            square.resize((768, 768), Image.LANCZOS).save(out / "source.png")
            bx, by = spec[view][0], spec[view][1]
            json.dump({"box": [int(bx + x0), int(by + y0), int(bx + x1), int(by + y1)]}, open(out / "info.json", "w"))
    atlas.save(out / "atlas.png")
    print("prepared", out)


main()
