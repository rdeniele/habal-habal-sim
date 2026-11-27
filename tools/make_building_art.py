"""Paint the building facade images (original art, no photos): one 3.2 m x 3.2 m "bay" each.

    python tools/make_building_art.py      -> assets/buildings/<name>.png  (+ <name>_lit.png)

Alpha is a paint mask the game reads: 128 = wall paint (takes the building's color),
255 = keep the drawn color (glass, signs, metal). (Never 0: Godot would rewrite those pixels.)
The _lit image is what glows at night.
Layer order used by the game (scenes/world/bacolod_city.gd): UPPER then GROUND, see NAMES.
"""
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parents[1] / "assets/buildings"
S = 512            # drawn at 512, saved at 256 (smooth edges)
PAINT, KEEP = 128, 255
WARM = (255, 206, 120)


def font(size):
    for f in ("C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/arial.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


class Bay:
    def __init__(self, seed, base=(226, 222, 214)):
        self.rng = random.Random(seed)
        self.img = Image.new("RGB", (S, S), base)
        self.mask = Image.new("L", (S, S), PAINT)
        self.lit = Image.new("RGB", (S, S), (0, 0, 0))
        self.d = ImageDraw.Draw(self.img)
        self.m = ImageDraw.Draw(self.mask)
        self.l = ImageDraw.Draw(self.lit)

    def rect(self, box, color, keep=True):
        self.d.rectangle(box, fill=color)
        self.m.rectangle(box, fill=KEEP if keep else PAINT)

    def shadow(self, box, strength=0.35, blur=6):
        """Soft darkening (under ledges, awnings, sills)."""
        layer = Image.new("L", (S, S), 0)
        ImageDraw.Draw(layer).rectangle(box, fill=int(255 * strength))
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
        self.img.paste(Image.new("RGB", (S, S), (40, 34, 30)), (0, 0), layer)

    def streaks(self, x0, x1, y0, count, length=(30, 110), strength=40):
        """Rain stains running down from a ledge."""
        layer = Image.new("L", (S, S), 0)
        d = ImageDraw.Draw(layer)
        for _ in range(count):
            x = self.rng.randint(x0, x1)
            d.line([(x, y0), (x + self.rng.randint(-3, 3), y0 + self.rng.randint(*length))],
                   fill=self.rng.randint(strength // 2, strength), width=self.rng.randint(2, 7))
        layer = layer.filter(ImageFilter.GaussianBlur(2.5))
        self.img.paste(Image.new("RGB", (S, S), (92, 84, 70)), (0, 0), layer)

    def grime(self, base_dirt=0.0):
        """Plaster grain, blotches, and splash dirt at the bottom."""
        a = np.array(self.img).astype(np.float32)
        gen = np.random.default_rng(self.rng.randint(0, 1 << 30))
        fine = gen.normal(0, 5.0, (S, S))
        blot = np.array(Image.fromarray((gen.random((16, 16)) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC),
                        dtype=np.float32) / 255.0 - 0.5
        a += (fine + blot * 18.0)[..., None]
        if base_dirt > 0:
            ramp = np.clip((np.arange(S) - S * 0.82) / (S * 0.18), 0, 1)[:, None]
            a *= (1.0 - base_dirt * ramp)[..., None]
        self.img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
        self.d = ImageDraw.Draw(self.img)

    def ledge(self, y, h=18):
        self.rect((0, y, S, y + h), (206, 201, 192), keep=False)
        self.d.line([(0, y), (S, y)], fill=(245, 242, 235), width=3)
        self.shadow((0, y + h, S, y + h + 10), 0.4, 5)

    def glass(self, box, lit=True):
        x0, y0, x1, y1 = box
        h = y1 - y0
        for y in range(y0, y1):
            t = (y - y0) / max(h, 1)
            self.d.line([(x0, y), (x1, y)], fill=(int(96 - 52 * t), int(128 - 62 * t), int(156 - 66 * t)))
        self.m.rectangle(box, fill=KEEP)
        self.d.polygon([(x0 + (x1 - x0) * 0.12, y1), (x0 + (x1 - x0) * 0.45, y0), (x0 + (x1 - x0) * 0.62, y0),
                        (x0 + (x1 - x0) * 0.29, y1)], fill=(132, 160, 180))
        if self.rng.random() < 0.6:   # curtain
            c = self.rng.choice([(186, 92, 80), (214, 190, 140), (110, 140, 120), (208, 208, 200)])
            w = (x1 - x0) // 3
            self.d.rectangle((x0, y0, x0 + w, y1), fill=c)
            for x in range(x0 + 8, x0 + w, 16):
                self.d.line([(x, y0), (x, y1)], fill=tuple(int(v * 0.75) for v in c), width=4)
        if lit and self.rng.random() < 0.7:
            self.l.rectangle(box, fill=WARM)

    def frame(self, box, color=(188, 192, 196), width=8):
        x0, y0, x1, y1 = box
        for b in ((x0 - width, y0 - width, x1 + width, y0), (x0 - width, y1, x1 + width, y1 + width),
                  (x0 - width, y0, x0, y1), (x1, y0, x1 + width, y1)):
            self.rect(b, color)

    def grill(self, box, color=(58, 58, 62), step=34):
        """Iron window grills, the Filipino way."""
        x0, y0, x1, y1 = box
        for x in range(x0 + step // 2, x1, step):
            self.d.line([(x, y0), (x, y1)], fill=color, width=5)
        for y in (y0 + 6, (y0 + y1) // 2, y1 - 6):
            self.d.line([(x0, y), (x1, y)], fill=color, width=5)
        for x in range(x0 + step // 2, x1 - step, step * 2):
            cy = (y0 + y1) // 2
            self.d.ellipse((x + 4, cy - 15, x + step - 4, cy + 15), outline=color, width=4)

    def window(self, box, grill=True, sill=True):
        x0, y0, x1, y1 = box
        self.shadow((x0 - 14, y0 - 14, x1 + 14, y0), 0.35)
        self.glass(box)
        self.frame(box)
        self.rect(((x0 + x1) // 2 - 4, y0, (x0 + x1) // 2 + 4, y1), (188, 192, 196))
        if grill:
            self.grill((x0 - 4, y0 - 4, x1 + 4, y1 + 4))
        if sill:
            self.rect((x0 - 24, y1 + 10, x1 + 24, y1 + 28), (212, 206, 196), keep=False)
            self.shadow((x0 - 20, y1 + 28, x1 + 20, y1 + 40), 0.4)
            self.streaks(x0 - 20, x1 + 20, y1 + 30, 9)

    def aircon(self, x, y):
        self.shadow((x, y + 74, x + 130, y + 92), 0.5)
        self.rect((x, y, x + 130, y + 78), (222, 220, 212))
        for yy in range(y + 12, y + 70, 10):
            self.d.line([(x + 10, yy), (x + 92, yy)], fill=(130, 130, 128), width=4)
        self.d.ellipse((x + 98, y + 14, x + 122, y + 38), fill=(150, 150, 148))
        self.streaks(x + 10, x + 120, y + 80, 5, (30, 90), 55)

    def sign(self, y0, y1, text, bg, fg=(255, 255, 255)):
        self.rect((14, y0, S - 14, y1), bg)
        self.d.rectangle((22, y0 + 8, S - 22, y1 - 8), outline=fg, width=3)
        f = font(int((y1 - y0) * 0.52))
        while self.d.textlength(text, font=f) > S - 70:
            f = font(f.size - 4)
        self.d.text((S / 2, (y0 + y1) / 2), text, font=f, fill=fg, anchor="mm")
        self.l.rectangle((14, y0, S - 14, y1), fill=tuple(v // 3 for v in bg))
        self.shadow((14, y1, S - 14, y1 + 12), 0.4)

    def awning(self, y, colors, drop=62):
        w = (S - 12) / 10
        for i in range(10):
            c = colors[i % len(colors)]
            x = 6 + i * w
            self.d.polygon([(x + 6, y), (x + w + 6, y), (x + w, y + drop), (x, y + drop)], fill=c)
            self.d.pieslice((x, y + drop - 14, x + w, y + drop + 14), 0, 180, fill=c)
            self.m.rectangle((x, y, x + w, y + drop + 14), fill=KEEP)
        self.shadow((6, y + drop + 12, S - 6, y + drop + 44), 0.45, 9)

    def goods(self, box, rows=3):
        """Shelves full of colorful goods."""
        x0, y0, x1, y1 = box
        self.rect(box, (52, 40, 32))
        h = (y1 - y0) // rows
        for r in range(rows):
            base = y0 + (r + 1) * h - 8
            x = x0 + 8
            while x < x1 - 20:
                w, hh = self.rng.randint(14, 30), self.rng.randint(h // 3, h - 14)
                c = self.rng.choice([(214, 60, 52), (240, 190, 50), (60, 140, 200), (80, 170, 90), (235, 235, 225), (230, 120, 40)])
                self.d.rectangle((x, base - hh, x + w, base), fill=c)
                self.d.rectangle((x + 3, base - hh // 2 - 6, x + w - 3, base - hh // 2 + 4), fill=(250, 246, 235))
                x += w + self.rng.randint(3, 8)
            self.d.rectangle((x0, base, x1, base + 8), fill=(120, 90, 62))
        self.l.rectangle(box, fill=(150, 118, 72))

    def save(self, name):
        rgba = self.img.convert("RGBA")
        rgba.putalpha(self.mask)
        rgb = rgba.convert("RGB").resize((256, 256), Image.LANCZOS)
        alpha = self.mask.resize((256, 256), Image.NEAREST)
        rgb.putalpha(alpha)
        rgb.save(OUT / (name + ".png"))
        self.lit.resize((256, 256), Image.LANCZOS).save(OUT / (name + "_lit.png"))


# --- upper floors -------------------------------------------------------------------------

def upper_home(b):
    b.grime()
    b.ledge(0)
    b.window((104, 130, 360, 330))
    b.aircon(366, 396)


def upper_jalousie(b):
    b.grime()
    b.ledge(0)
    for x0 in (60, 292):
        box = (x0, 118, x0 + 160, 338)
        b.shadow((x0 - 12, 104, x0 + 172, 118), 0.4)
        b.glass(box)
        for y in range(122, 336, 24):
            b.d.polygon([(x0, y), (x0 + 160, y), (x0 + 160, y + 13), (x0, y + 13)], fill=(168, 200, 208))
            b.d.line([(x0, y + 15), (x0 + 160, y + 15)], fill=(40, 62, 74), width=4)
        b.frame(box, (150, 112, 82), 9)
        b.rect((x0 - 16, 348, x0 + 176, 364), (212, 206, 196), keep=False)
        b.streaks(x0, x0 + 160, 366, 8)


def upper_office(b):
    b.grime()
    b.ledge(0, 26)
    box = (18, 112, 494, 352)
    b.shadow((10, 96, 502, 112), 0.45)
    b.glass(box)
    b.frame(box, (120, 126, 134), 10)
    for x in range(18, 495, 119):
        b.rect((x - 5, 112, x + 5, 352), (120, 126, 134))
    b.rect((18, 188, 494, 196), (120, 126, 134))
    b.rect((0, 404, S, 440), (178, 172, 164), keep=False)
    b.streaks(20, 490, 442, 20, (20, 60))


def upper_balcony(b):
    b.grime()
    b.ledge(0)
    b.window((52, 128, 218, 322), sill=False)
    door = (290, 108, 452, 450)
    b.shadow((278, 92, 464, 108), 0.45)
    b.rect(door, (122, 84, 58))
    for box in ((308, 130, 434, 270), (308, 296, 434, 428)):
        b.d.rectangle(box, outline=(84, 56, 40), width=7)
    b.d.ellipse((424, 282, 440, 298), fill=(222, 190, 100))
    # laundry on a line
    b.d.line([(30, 340), (270, 356)], fill=(70, 70, 70), width=3)
    x = 42
    while x < 240:
        c = b.rng.choice([(214, 80, 70), (70, 120, 190), (238, 236, 228), (90, 160, 100), (230, 180, 60)])
        w = b.rng.randint(36, 60)
        top = 342 + (x - 30) // 15
        b.rect((x, top, x + w, top + b.rng.randint(48, 76)), c)
        x += w + 12
    # slab and railing
    b.rect((0, 448, S, 486), (196, 190, 180), keep=False)
    b.shadow((0, 486, S, 510), 0.55)
    b.rect((0, 372, S, 386), (62, 62, 68))
    for x in range(14, S, 34):
        b.rect((x, 386, x + 9, 448), (62, 62, 68))


# --- ground floors ------------------------------------------------------------------------

def base_floor(b):
    b.grime(0.35)
    b.rect((0, 482, S, S), (132, 126, 118))   # concrete step
    b.d.line([(0, 482), (S, 482)], fill=(190, 184, 174), width=4)


def ground_sarisari(b):
    base_floor(b)
    b.goods((52, 178, 460, 360))
    # strings of sachets
    for x in range(70, 450, 44):
        b.d.line([(x, 178), (x, 250)], fill=(220, 220, 210), width=2)
        for y in range(186, 250, 18):
            b.rect((x - 11, y, x + 11, y + 14), b.rng.choice([(220, 60, 60), (60, 150, 90), (240, 200, 60), (90, 110, 200)]))
    b.grill((52, 178, 460, 360), (70, 120, 90), 46)
    b.frame((52, 178, 460, 360), (92, 70, 50), 10)
    b.rect((34, 360, 478, 392), (150, 112, 76))
    b.shadow((40, 392, 472, 412), 0.45)
    b.sign(40, 120, "SARI-SARI STORE", (196, 36, 40), (255, 236, 150))
    b.awning(124, [(236, 188, 40), (206, 50, 44)], 44)


def ground_karinderia(b):
    base_floor(b)
    b.rect((40, 190, 472, 482), (64, 46, 34))
    b.l.rectangle((40, 190, 472, 482), fill=(140, 104, 60))
    b.rect((60, 340, 452, 482), (176, 132, 88))
    for x in range(72, 440, 76):                       # pots on the counter
        b.d.ellipse((x, 312, x + 60, 340), fill=(176, 180, 186))
        b.rect((x, 326, x + 60, 358), (150, 154, 160))
        b.d.ellipse((x + 6, 314, x + 54, 332), fill=b.rng.choice([(170, 80, 40), (196, 150, 60), (110, 130, 50)]))
    for y in range(372, 478, 26):
        b.d.line([(60, y), (452, y)], fill=(140, 102, 68), width=4)
    b.sign(30, 108, "KARINDERIA", (30, 112, 70), (255, 255, 255))
    b.awning(118, [(40, 130, 86), (238, 238, 226)], 58)


def shutter(b, name, bg):
    base_floor(b)
    b.rect((36, 150, 476, 482), (168, 172, 176))
    for y in range(154, 480, 17):
        b.d.line([(38, y), (474, y)], fill=(112, 116, 122), width=5)
        b.d.line([(38, y + 5), (474, y + 5)], fill=(204, 208, 212), width=3)
    b.rect((36, 134, 476, 152), (96, 100, 106))
    b.rect((238, 446, 274, 466), (70, 70, 74))
    b.streaks(60, 450, 160, 16, (60, 200), 45)
    b.sign(34, 120, name, bg)


def ground_hardware(b):
    shutter(b, "HARDWARE & PAINTS", (30, 74, 150))


def ground_vulcanizing(b):
    shutter(b, "VULCANIZING", (222, 120, 24))
    for i in range(4):                      # a flat stack of tires
        box = (378 + (i % 2) * 8, 446 - i * 36, 492 + (i % 2) * 8, 480 - i * 36)
        b.d.rounded_rectangle(box, radius=16, fill=(32, 32, 34))
        b.d.line([(box[0] + 12, box[1] + 9), (box[2] - 12, box[1] + 9)], fill=(78, 78, 82), width=4)
        b.m.rounded_rectangle(box, radius=16, fill=KEEP)


def ground_bakery(b):
    base_floor(b)
    box = (46, 168, 466, 380)
    b.glass(box, lit=False)
    b.l.rectangle(box, fill=(190, 150, 90))
    for y in (262, 342):                    # trays of bread
        b.rect((56, y + 22, 456, y + 32), (150, 150, 154))
        for x in range(66, 440, 40):
            b.d.ellipse((x, y - 4, x + 34, y + 22), fill=b.rng.choice([(214, 156, 80), (192, 128, 62), (232, 184, 108)]))
    b.frame(box, (110, 74, 48), 12)
    b.rect((46, 392, 466, 482), (198, 160, 112))
    b.sign(40, 118, "PANADERIA", (128, 70, 36), (255, 240, 200))
    b.awning(122, [(150, 80, 40), (244, 226, 190)], 34)


def ground_house(b):
    base_floor(b)
    b.window((56, 190, 270, 360))
    door = (320, 150, 456, 482)
    b.shadow((306, 134, 470, 150), 0.45)
    b.rect(door, (96, 62, 44))
    for y in (172, 260, 360):
        b.d.rectangle((340, y, 436, y + 70), outline=(66, 42, 30), width=7)
    b.d.ellipse((428, 316, 446, 334), fill=(222, 190, 100))
    b.grill((314, 150, 462, 482), (46, 46, 50), 40)
    b.rect((300, 108, 476, 128), (120, 124, 130))
    # potted plants
    for x in (284, 470):
        b.rect((x - 18, 448, x + 18, 482), (170, 92, 60))
        for _ in range(14):
            px, py = x + b.rng.randint(-24, 24), 428 + b.rng.randint(-26, 16)
            b.d.ellipse((px - 12, py - 9, px + 12, py + 9), fill=(52, b.rng.randint(110, 160), 62))
            b.m.ellipse((px - 12, py - 9, px + 12, py + 9), fill=KEEP)


def church(b):
    b.img.paste((214, 204, 182), (0, 0, S, S))
    b.d = ImageDraw.Draw(b.img)
    for row, y in enumerate(range(0, S, 52)):        # stone blocks
        for x in range(-60 + (row % 2) * 60, S, 120):
            v = b.rng.randint(-14, 10)
            b.d.rectangle((x + 2, y + 2, x + 118, y + 50), fill=(212 + v, 202 + v, 180 + v))
    b.grime(0.15)
    for box, color in (((170, 120, 342, 420), (150, 138, 118)), ((188, 150, 324, 404), (52, 66, 108))):
        b.d.rectangle(box, fill=color)
        b.d.pieslice((box[0], box[1] - (box[2] - box[0]) // 2, box[2], box[1] + (box[2] - box[0]) // 2), 180, 360, fill=color)
    for i, x in enumerate(range(192, 324, 33)):
        for j, y in enumerate(range(140, 400, 44)):
            b.d.rectangle((x, y, x + 27, y + 38), fill=[(170, 60, 60), (60, 100, 170), (200, 160, 60), (70, 130, 90)][(i + j) % 4])
    b.m.rectangle((170, 60, 342, 420), fill=KEEP)
    b.l.rectangle((192, 150, 320, 396), fill=(190, 140, 90))
    b.streaks(150, 362, 424, 14)


UPPER = [upper_home, upper_jalousie, upper_office, upper_balcony]
GROUND = [ground_sarisari, ground_karinderia, ground_hardware, ground_vulcanizing, ground_bakery, ground_house]
NAMES = [f.__name__ for f in UPPER + GROUND + [church]]


def roof():
    """Corrugated GI sheet with rust, 2 m x 2 m."""
    gen = np.random.default_rng(7)
    x = np.arange(256)
    wave = 0.78 + 0.18 * np.sin(x / 256 * 2 * np.pi * 14)
    a = np.repeat(wave[None, :], 256, axis=0) * 225
    a = a + gen.normal(0, 6, a.shape)
    rgb = np.stack([a, a, a * 1.01], axis=2)
    blot = np.array(Image.fromarray((gen.random((12, 12)) * 255).astype(np.uint8)).resize((256, 256), Image.BICUBIC)) / 255.0
    rust = np.clip((blot - 0.72) * 2.6, 0, 0.8)[..., None]
    rgb = rgb * (1 - rust) + np.array([150, 92, 58]) * rust * (wave[None, :, None])
    rgb[0:3] *= 0.6                  # sheet overlap line
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(OUT / "roof.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for i, fn in enumerate(UPPER + GROUND + [church]):
        b = Bay(100 + i)
        fn(b)
        b.save(fn.__name__)
    roof()
    print("saved", len(NAMES), "bays + roof to", OUT)


main()
