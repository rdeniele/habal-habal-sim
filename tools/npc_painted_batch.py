"""All 20 sheet NPCs in one batch, the "painted" way: TripoSR makes the shape from the drawing,
then the same drawing is painted back onto it (tools/blender/make_painted.py).

    tools/triposr_tmp/venv/Scripts/python.exe tools/npc_painted_batch.py prepare
    tools/triposr_tmp/venv/Scripts/python.exe tools/npc_painted_batch.py generate
    tools/triposr_tmp/venv/Scripts/python.exe tools/npc_painted_batch.py build

Work files go to tools/triposr_tmp/painted/<name>/ (source.png, atlas.png, mesh.obj).
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
TMP = ROOT / "tools/triposr_tmp"
OUT = TMP / "painted"
BLENDER = r"D:\Tools\Blender\blender-5.3.0-windows-x64\blender.exe"
sys.path.insert(0, str(ROOT / "tools"))
from npc_batch import BOUNDS   # noqa: E402  (masks that cut away the neighboring figure)

TYPES = ["vendor", "enforcer", "customer", "pedestrian", "fellow_rider",
         "office_worker", "student", "technician", "delivery", "misc"]
NAMES = [t + "_" + g for t in TYPES for g in "mf"]
SHEET = Path.home() / "AppData/Local/Temp/claude/05fbbc76bd988a23/8165caba-ac4b-4f23-b33a-8ea598b4d4c2/images/2.webp"
SHEET_COPY = ROOT / "reference/npc_sheet.webp"
# the small back views (male left, female right) of each type, on the sheet
BACKS = {"vendor": (228, 325, 312, 440), "enforcer": (530, 325, 612, 440), "customer": (824, 325, 906, 440),
         "pedestrian": (1122, 325, 1204, 440), "fellow_rider": (1438, 325, 1522, 440),
         "office_worker": (236, 783, 316, 898), "student": (540, 783, 620, 898), "technician": (838, 783, 920, 898),
         "delivery": (1146, 783, 1228, 898), "misc": (1448, 783, 1530, 898)}
TILE = (512, 1024)


def figure_mask(rgb, min_hole):
    """The figure on a plain cream background (flood fill; the dark outlines stop it)."""
    im = rgb.astype(int)
    cream = (im.min(axis=2) > 188) & (im[:, :, 0] - im[:, :, 2] > 5) & (im[:, :, 0] - im[:, :, 2] < 50)
    regions, _ = ndimage.label(cream)
    border = np.unique(np.concatenate([regions[0], regions[-1], regions[:, 0], regions[:, -1]]))
    sizes = np.bincount(regions.ravel())
    background = np.isin(regions, np.union1d(border, np.nonzero(sizes > min_hole)[0])) & cream
    return ndimage.binary_opening(~background, iterations=2)


def largest(mask, rank=0):
    lab, n = ndimage.label(mask)
    sizes = np.bincount(lab.ravel())
    sizes[0] = 0
    order = np.argsort(sizes)[::-1]
    return lab == order[rank]


def tile(rgb, mask, erode):
    """The figure cut to its box, colors spread outward, stretched to one atlas tile."""
    ys, xs = np.nonzero(mask)
    rgb = rgb[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    mask = mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    solid = ndimage.binary_erosion(mask, iterations=erode)
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    return Image.fromarray(rgb[iy, ix]).resize(TILE, Image.LANCZOS), rgb, mask


def prepare():
    if not SHEET_COPY.exists():
        shutil.copy(SHEET, SHEET_COPY)
    sheet = Image.open(SHEET_COPY).convert("RGB")
    for name in NAMES:
        kind, gender = name.rsplit("_", 1)
        out = OUT / name
        (out / "0").mkdir(parents=True, exist_ok=True)
        im = Image.open(ROOT / "reference/npc_crops" / (name + ".png")).convert("RGB")
        w, h = im.size
        bg = im.getpixel((w // 2, 5))
        if name in BOUNDS:
            left, right = BOUNDS[name]
        else:   # vendors
            left, right = ([(0.05, 0), (0.05, 1)], [(0.91, 0), (0.91, 1)]) if gender == "m" else ([(0.09, 0), (0.09, 1)], [(0.9, 0), (0.9, 1)])
        keep = Image.new("L", im.size)
        ImageDraw.Draw(keep).polygon([(round(x * w), round(y * h)) for x, y in left + list(reversed(right))], fill=255)
        clean = Image.new("RGB", im.size, bg)
        clean.paste(im, mask=keep)
        rgb = np.array(clean)
        mask = largest(figure_mask(rgb, 1500))
        front, fig, fig_mask = tile(rgb, mask, 5)
        # TripoSR input: the figure filling 85% of a grey square
        grey = np.full_like(fig, 128)
        grey[fig_mask] = fig[fig_mask]
        g = Image.fromarray(grey)
        side = int(max(g.size) / 0.85)
        square = Image.new("RGB", (side, side), (128, 128, 128))
        square.paste(g, ((side - g.width) // 2, (side - g.height) // 2))
        square.resize((768, 768), Image.LANCZOS).save(out / "source.png")
        # back view: split the little pair
        pair = sheet.crop(BACKS[kind])
        pair = np.array(pair.resize((pair.width * 6, pair.height * 6), Image.LANCZOS))
        pm = figure_mask(pair, 600)
        parts = [largest(pm, 0), largest(pm, 1)]
        parts.sort(key=lambda m: np.nonzero(m)[1].mean())
        back, _, _ = tile(pair, parts[0 if gender == "m" else 1], 3)
        atlas = Image.new("RGB", (TILE[0] * 2, TILE[1]))
        atlas.paste(front, (0, 0))
        atlas.paste(back, (TILE[0], 0))
        atlas.save(out / "atlas.png")
        print("prepared", name, flush=True)


def generate():
    """One TripoSR run for all pictures (the model loads once)."""
    env = dict(os.environ, HF_HOME=str(TMP / "hf_cache"), U2NET_HOME=str(TMP / "u2net"),
               HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", PYTHONUNBUFFERED="1")
    batch = OUT / "_run"
    sources = []
    for i, name in enumerate(NAMES):
        (batch / str(i)).mkdir(parents=True, exist_ok=True)
        sources.append(str(OUT / name / "source.png"))
    with open(OUT / "generate.log", "w", encoding="utf-8") as log:
        code = subprocess.run([str(TMP / "venv/Scripts/python.exe"), "run.py", *sources, "--no-remove-bg",
                               "--output-dir", str(batch), "--chunk-size", "2048", "--mc-resolution", "192",
                               "--model-save-format", "obj"], cwd=TMP / "TripoSR", env=env,
                              stdout=log, stderr=subprocess.STDOUT).returncode
    if code:
        raise SystemExit((OUT / "generate.log").read_text(encoding="utf-8")[-3000:])
    for i, name in enumerate(NAMES):
        shutil.copy(batch / str(i) / "mesh.obj", OUT / name / "0/mesh.obj")
    print("generated", len(NAMES))


def build():
    result = subprocess.run([BLENDER, "-b", "--python-exit-code", "1", "-P",
                             str(ROOT / "tools/blender/make_painted.py"), "--", *NAMES],
                            cwd=ROOT, capture_output=True, text=True)
    for line in result.stdout.splitlines():
        if line.startswith("  ") or "Error" in line:
            print(line)
    if result.returncode:
        raise SystemExit(result.stderr[-3000:])


if __name__ == "__main__":
    {"prepare": prepare, "generate": generate, "build": build}[sys.argv[1]]()
