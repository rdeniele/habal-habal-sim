"""Cut a figure out of the sheet by flood-filling the plain cream background (for pictures
where rembg leaves cream slabs beside the legs). The drawing's dark outlines stop the fill.
Writes <batch>/<name>/clean.png on grey, ready for TripoSR with --no-remove-bg.
    tools/triposr_tmp/venv/Scripts/python.exe tools/npc_clean.py customer_f ..."""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from skimage.measure import label
from skimage.morphology import binary_opening, disk

BATCH = Path(__file__).resolve().parent / "triposr_tmp/npc_batch"

for name in sys.argv[1:]:
    im = np.array(Image.open(BATCH / name / "source.png").convert("RGB")).astype(int)
    h, w = im.shape[:2]
    # every light, slightly warm pixel could be background (cream, and its soft shading)
    cream = (im.min(axis=2) > 188) & (im[:, :, 0] - im[:, :, 2] > 6) & (im[:, :, 0] - im[:, :, 2] < 45)
    regions = label(cream, connectivity=1)
    sizes = np.bincount(regions.ravel())
    border = np.unique(np.concatenate([regions[0], regions[-1], regions[:, 0], regions[:, -1]]))
    big = np.nonzero(sizes > 1500)[0]          # large flat areas are background even if enclosed
    background = np.isin(regions, np.union1d(border, big)) & cream
    solid = binary_opening(~background, disk(2))   # drop hair-thin leftover lines
    figure = label(solid, connectivity=1)
    sizes = np.bincount(figure.ravel())
    sizes[0] = 0
    keep = figure == sizes.argmax()
    # same framing as TripoSR expects: figure fills 85% of a square, on grey
    ys, xs = np.nonzero(keep)
    out = np.full((h, w, 3), 128, dtype=np.uint8)
    out[keep] = im[keep]
    crop = Image.fromarray(out[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    side = int(max(crop.size) / 0.85)
    square = Image.new("RGB", (side, side), (128, 128, 128))
    square.paste(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
    square.resize((768, 768), Image.Resampling.LANCZOS).save(BATCH / name / "clean.png")
    print(name, "kept", int(keep.sum()), "pixels")
