"""Reproduce the local TripoSR NPC batch without downloading models or replacing vendors.

    python tools/npc_batch.py prepare
    python tools/npc_batch.py generate
    python tools/npc_batch.py build

Use --types enforcer customer to limit any step. Intermediates stay in triposr_tmp.
"""
import argparse
import os
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
TMP = ROOT / "tools/triposr_tmp"
BATCH = TMP / "npc_batch"
TYPES = ("enforcer", "customer", "pedestrian", "fellow_rider", "office_worker",
         "student", "technician", "delivery", "misc")

# Retain only the large figure, excluding the adjacent portraits/back views. Coordinates
# are fractions of the original crop. rembg subsequently removes the remaining backdrop.
# Each boundary is a polyline from the top to the bottom of the crop.
BOUNDS = {
    "enforcer_m": ([(0, 0), (0, 1)], [(0.82, 0), (0.82, 1)]),
    "enforcer_f": ([(0, 0), (0, 1)], [(0.78, 0), (0.78, 1)]),
    "customer_m": ([(0.04, 0), (0.04, 1)], [(0.85, 0), (0.85, 1)]),
    "customer_f": ([(0, 0), (0, 1)], [(0.76, 0), (0.76, 1)]),
    "pedestrian_m": ([(0, 0), (0, 1)], [(0.86, 0), (0.86, 0.24), (0.82, 0.34), (0.86, 0.58), (0.91, 1)]),
    "pedestrian_f": ([(0, 0), (0, 0.96), (0.09, 0.96), (0.09, 1)], [(0.76, 0), (0.76, 1)]),
    "fellow_rider_m": ([(0, 0), (0, 1)], [(0.93, 0), (0.93, 1)]),
    "fellow_rider_f": ([(0.04, 0), (0.04, 0.27), (0.16, 0.34), (0.18, 0.57), (0.05, 0.73), (0.05, 1)], [(0.94, 0), (0.94, 1)]),
    "office_worker_m": ([(0.04, 0), (0.04, 1)], [(0.93, 0), (0.93, 1)]),
    "office_worker_f": ([(0.04, 0), (0.04, 0.87), (0.15, 1)], [(0.89, 0), (0.89, 1)]),
    "student_m": ([(0, 0), (0, 1)], [(0.84, 0), (0.84, 1)]),
    "student_f": ([(0, 0), (0, 1)], [(0.78, 0), (0.78, 1)]),
    "technician_m": ([(0.02, 0), (0.02, 1)], [(0.87, 0), (0.87, 1)]),
    "technician_f": ([(0.04, 0), (0.04, 1)], [(0.83, 0), (0.83, 1)]),
    "delivery_m": ([(0, 0), (0, 1)], [(0.85, 0), (0.85, 0.49), (0.90, 0.62), (0.94, 1)]),
    "delivery_f": ([(0, 0), (0, 0.93), (0.10, 0.93), (0.10, 1)], [(0.83, 0), (0.83, 1)]),
    "misc_m": ([(0, 0), (0, 1)], [(0.88, 0), (0.79, 0.22), (0.79, 0.88), (0.87, 0.94), (0.87, 1)]),
    "misc_f": ([(0, 0), (0, 1)], [(0.86, 0), (0.86, 1)]),
}


def prepare(names):
    for name in names:
        out = BATCH / name
        out.mkdir(parents=True, exist_ok=True)
        im = Image.open(ROOT / "reference/npc_crops" / (name + ".png")).convert("RGB")
        w, h = im.size
        left, right = BOUNDS[name]
        mask = Image.new("L", im.size)
        polygon = [(round(x*w), round(y*h)) for x,y in left + list(reversed(right))]
        ImageDraw.Draw(mask).polygon(polygon, fill=255)
        bg = im.getpixel((w//2, 5))
        clean = Image.new("RGB", im.size, bg)
        clean.paste(im, mask=mask)
        pad = Image.new("RGB", (h, h), bg)
        pad.paste(clean, ((h-w)//2, 0))
        pad.resize((768, 768), Image.Resampling.LANCZOS).save(out / "source.png")
        print("Prepared", name, flush=True)


def generate(names, force=False):
    # All weights are already installed. Offline flags prevent accidental network fetches.
    env = dict(os.environ, HF_HOME=str(TMP / "hf_cache"), U2NET_HOME=str(TMP / "u2net"),
               HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", PYTHONUNBUFFERED="1")
    python = TMP / "venv/Scripts/python.exe"
    # One process at a time keeps the RTX 3050 inside its VRAM budget; each completed
    # character is reusable when resuming an interrupted run.
    for name in names:
        dest = BATCH / name
        if not force and (dest / "0/mesh.obj").exists() and (dest / "0/texture.png").exists():
            print("Already generated", name, flush=True)
            continue
        if not (dest / "source.png").exists():
            raise FileNotFoundError("Run prepare first: " + name)
        print("Generating", name, flush=True)
        with (dest / "generate.log").open("w", encoding="utf-8") as log:
            result = subprocess.run([str(python), "run.py", str(dest / "source.png"),
                "--output-dir", str(dest), "--chunk-size", "2048", "--mc-resolution", "128",
                "--bake-texture", "--texture-resolution", "1024", "--model-save-format", "obj"],
                cwd=TMP / "TripoSR", env=env, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError((dest / "generate.log").read_text(encoding="utf-8")[-5000:])
        print("Generated", name, flush=True)


def build(names, blender):
    for name in names:
        dest = BATCH / name
        kind = name.rsplit("_", 1)[0]
        with (dest / "build.log").open("w", encoding="utf-8") as log:
            result = subprocess.run([str(blender), "-b", "--python-exit-code", "1", "-P",
                str(ROOT / "tools/blender/triposr_to_npc.py"), "--", str(dest / "0/mesh.obj"),
                str(dest / "0/texture.png"), name, kind, "-90"], cwd=ROOT,
                stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError("Blender exit code %s\n%s" % (result.returncode,
                (dest / "build.log").read_text(encoding="utf-8")[-5000:]))
        print("Built", name, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("step", choices=("prepare", "generate", "build"))
    parser.add_argument("--types", nargs="+", choices=TYPES, default=list(TYPES))
    parser.add_argument("--genders", nargs="+", choices=("m", "f"), default=["m", "f"])
    parser.add_argument("--force", action="store_true", help="Regenerate existing intermediate meshes")
    parser.add_argument("--blender", type=Path,
                        default=Path(r"D:\Tools\Blender\blender-5.3.0-windows-x64\blender.exe"))
    args = parser.parse_args()
    names = [kind + "_" + gender for kind in args.types for gender in args.genders]
    if args.step == "prepare": prepare(names)
    elif args.step == "generate": generate(names, args.force)
    else: build(names, args.blender)


if __name__ == "__main__":
    main()
