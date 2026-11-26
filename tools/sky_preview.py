"""Preview the game's sky (scenes/world/sky.gdshader) without opening Godot.
Same math as the shader, done with numpy. Writes one image with 4 views:
morning, sunset, night, cloudy day.
    python tools/sky_preview.py out.png
Needs: pip install numpy pillow
"""
import sys
import numpy as np
from PIL import Image

W, H = 640, 260
F = np.float32


def lin(hex_color):
    h = hex_color.lstrip("#")
    c = np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], dtype=F)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4).astype(F)


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def fract(x):
    return x - np.floor(x)


def hash2(px, py):
    px = fract(px * F(123.34))
    py = fract(py * F(456.21))
    d = px * (px + F(45.32)) + py * (py + F(45.32))
    px = px + d
    py = py + d
    return fract(px * py)


def noise(x, y):
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x - ix, y - iy
    ux, uy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = hash2(ix, iy)
    b = hash2(ix + 1, iy)
    c = hash2(ix, iy + 1)
    d = hash2(ix + 1, iy + 1)
    return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy


def fbm(x, y, octaves):
    v = np.zeros_like(x)
    a = F(0.5)
    for _ in range(octaves):
        v += a * noise(x, y)
        x, y = x * F(2.03) + F(17.1), y * F(2.03) + F(9.2)
        a *= F(0.5)
    return v


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def view(sky_top, horizon, ground, sun_tint, night, cover, sun_elev, sun_az, pitch=14.0, fov=80.0, t=0.0):
    sky_top, horizon, ground, sun_tint = lin(sky_top), lin(horizon), lin(ground), lin(sun_tint)
    xs = np.linspace(-1, 1, W, dtype=F) * np.tan(np.radians(fov / 2))
    ys = np.linspace(1, -1, H, dtype=F) * np.tan(np.radians(fov / 2)) * H / W
    X, Y = np.meshgrid(xs, ys)
    Z = -np.ones_like(X)
    p = np.radians(pitch)
    Y2 = Y * np.cos(p) - Z * np.sin(p)
    Z2 = Y * np.sin(p) + Z * np.cos(p)
    n = np.sqrt(X * X + Y2 * Y2 + Z2 * Z2)
    dx, dy, dz = X / n, Y2 / n, Z2 / n
    h = dy
    day = 1 - night
    g = np.clip(h, 0, 1) ** 0.55
    col = horizon + (sky_top - horizon) * g[..., None]
    below = h < 0
    gb = np.clip(-h * 4, 0, 1)[..., None]
    col = np.where(below[..., None], horizon + (ground - horizon) * gb, col)
    el, az = np.radians(sun_elev), np.radians(sun_az)
    sdir = np.array([np.sin(az) * np.cos(el), np.sin(el), -np.cos(az) * np.cos(el)], dtype=F)
    sd = dx * sdir[0] + dy * sdir[1] + dz * sdir[2]
    toward = np.maximum(sd, 0)
    col = col + sun_tint * ((toward ** 8) * 0.3 + (toward ** 90) * 0.6)[..., None] * day
    sun_disc = smoothstep(0.99945, 0.9997, sd) * day
    moon_disc = smoothstep(0.9988, 0.99905, sd) * night
    col = col + np.array([0.55, 0.65, 0.9], dtype=F) * ((toward ** 300) * 0.25 * night)[..., None]
    hp = np.maximum(h, 1e-4)
    ux = dx / (hp + F(0.12)) * F(1.4) + F(t * 0.004)
    uy = dz / (hp + F(0.12)) * F(1.4) + F(t * 0.004 * 0.35)
    nz = fbm(ux, uy, 4)
    thr = 0.68 + (0.32 - 0.68) * cover
    clouds = smoothstep(thr, thr + 0.2, nz)
    clouds = np.floor(clouds * 7 + 0.5) / 7
    clouds = clouds * smoothstep(0.0, 0.2, h) * (h > 0)
    thick = smoothstep(thr, thr + 0.45, nz)
    lit = np.ones(3, dtype=F) * (1 - 0.45) + sun_tint * 0.45
    shadow = (horizon + (sky_top - horizon) * 0.35) * 0.72
    ccol = lit + (shadow - lit) * (thick * 0.65)[..., None]
    ccol = ccol + sun_tint * ((toward ** 5) * 0.35 * day)[..., None]
    ccol = ccol + (np.array([0.12, 0.14, 0.2], dtype=F) - ccol) * night * 0.85
    col = col + (ccol - col) * (clouds * 0.95)[..., None]
    if night > 0.01:
        cx, cy, cz = np.floor(dx * 260), np.floor(dy * 260), np.floor(dz * 260)
        r = hash2(cx, cy + cz * F(7.13))
        star = (r > 0.9968) * 0.9
        col = col + (star * night * smoothstep(0.02, 0.25, h) * (1 - clouds))[..., None]
    col = col + ((sun_tint * 1.6 + 0.25) - col) * (sun_disc * (1 - clouds * 0.85))[..., None]
    col = col + (np.array([0.92, 0.94, 1.0], dtype=F) - col) * (moon_disc * (1 - clouds * 0.9))[..., None]
    # simple stand-in for Godot's filmic tonemap: soft shoulder
    col = col / (1 + col * 0.35) * 1.2
    return (to_srgb(col) * 255).astype(np.uint8)


views = [
    ("morning", view("#4f9fe0", "#cfe8f5", "#6b8f71", "#fff0d8", 0.0, 0.4, 22, 25)),
    ("sunset", view("#3d5a99", "#f08a5d", "#6b8f71", "#ff9050", 0.5, 0.5, 3, -10)),
    ("night", view("#0b1026", "#1b2440", "#1b2440", "#9fb4ff", 1.0, 0.35, 30, 20)),
    ("cloudy", view("#4f9fe0", "#cfe8f5", "#6b8f71", "#fff4e0", 0.0, 0.75, 50, 160)),
]
out = Image.new("RGB", (W * 2, H * 2))
for i, (name, img) in enumerate(views):
    out.paste(Image.fromarray(img), ((i % 2) * W, (i // 2) * H))
path = sys.argv[1] if len(sys.argv) > 1 else "sky_preview.png"
out.save(path)
print("saved", path)
