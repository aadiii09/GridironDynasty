"""Generates Gridiron Dynasty's 2D art (no fonts used: all shapes, so no font licensing).

Outputs PNGs to art/out/. Most art is white/grayscale so Roblox can tint it with
ImageColor3 (tier colors, team colors, pack colors).

Run: .venv\\Scripts\\python.exe -I -X utf8 art\\generate.py
"""

import json
import math
import random
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art" / "out"
OUT.mkdir(parents=True, exist_ok=True)
SS = 2  # supersampling


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def finish(img, w, h, name):
    img.resize((w, h), Image.LANCZOS).save(OUT / f"{name}.png")
    print("  wrote", name)


def chamfer_poly(x0, y0, x1, y1, c):
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]


def glow(layer, radius):
    """Neon: blurred copy under the crisp layer."""
    blurred = layer.filter(ImageFilter.GaussianBlur(radius))
    out = Image.alpha_composite(blurred, blurred)
    return Image.alpha_composite(out, layer)


# ----------------------------------------------------------------------------- cards
CW, CH = 512, 768


def P(x, y):
    return (x * CW * SS, y * CH * SS)


def card_base():
    img = canvas(CW, CH)
    d = ImageDraw.Draw(img)
    poly = chamfer_poly(6 * SS, 6 * SS, (CW - 6) * SS, (CH - 6) * SS, 46 * SS)
    d.polygon(poly, fill=(10, 13, 20, 255))
    # subtle diagonal tech stripes
    stripes = canvas(CW, CH)
    sd = ImageDraw.Draw(stripes)
    for i in range(-CH, CW, 18):
        sd.line([(i * SS, 0), ((i + CH) * SS, CH * SS)], fill=(255, 255, 255, 10), width=2 * SS)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    stripes.putalpha(ImageChops.multiply(stripes.getchannel("A"), mask))
    img = Image.alpha_composite(img, stripes)
    finish(img, CW, CH, "card_base")


def card_tint():
    """White shape with fading alpha + energy crackle: tinted with the team's primary color."""
    img = canvas(CW, CH)
    w, h = img.size
    poly = chamfer_poly(6 * SS, 6 * SS, (CW - 6) * SS, (CH - 6) * SS, 46 * SS)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    grad = Image.new("L", img.size, 0)
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        t = y / h
        a = int(235 * (1 - t) ** 1.3 + 25)
        gd.line([(0, y), (w, y)], fill=a)
    # radial light behind the player
    rad = Image.new("L", img.size, 0)
    ImageDraw.Draw(rad).ellipse([w * 0.12, h * 0.12, w * 0.88, h * 0.62], fill=120)
    rad = rad.filter(ImageFilter.GaussianBlur(60 * SS))
    alpha = ImageChops.add(grad, rad)
    # energy crackle (random forking lines)
    crack = Image.new("L", img.size, 0)
    cd = ImageDraw.Draw(crack)
    rng = random.Random(7)

    def bolt(x, y, ang, length, width, depth):
        for _ in range(int(length / (14 * SS))):
            nx = x + math.cos(ang) * 14 * SS
            ny = y + math.sin(ang) * 14 * SS
            cd.line([(x, y), (nx, ny)], fill=200, width=max(1, int(width)))
            x, y = nx, ny
            ang += rng.uniform(-0.6, 0.6)
            if depth < 3 and rng.random() < 0.12:
                bolt(x, y, ang + rng.choice([-1, 1]) * rng.uniform(0.5, 1.1), length * 0.5, width * 0.7, depth + 1)

    for _ in range(9):
        side = rng.choice(["l", "r", "t"])
        if side == "l":
            bolt(0, rng.uniform(0.1, 0.6) * h, rng.uniform(-0.4, 0.4), w * 0.45, 2.5 * SS, 0)
        elif side == "r":
            bolt(w, rng.uniform(0.1, 0.6) * h, math.pi + rng.uniform(-0.4, 0.4), w * 0.45, 2.5 * SS, 0)
        else:
            bolt(rng.uniform(0.2, 0.8) * w, 0, math.pi / 2 + rng.uniform(-0.5, 0.5), h * 0.35, 2.5 * SS, 0)
    crack_glow = crack.filter(ImageFilter.GaussianBlur(6 * SS))
    alpha = ImageChops.add(alpha, ImageChops.add(crack, crack_glow))
    alpha = ImageChops.multiply(alpha, mask)
    img = Image.new("RGBA", img.size, (255, 255, 255, 0))
    img.putalpha(alpha)
    finish(img, CW, CH, "card_tint")


def card_frame():
    """White neon frame + dark plates; tinted by tier color (dark plates stay dark)."""
    plates = canvas(CW, CH)
    pd = ImageDraw.Draw(plates)
    lines = canvas(CW, CH)
    ld = ImageDraw.Draw(lines)
    W = 255

    # name plate + archetype pill + brand plate (dark translucent)
    name = chamfer_poly(*P(0.04, 0.675), *P(0.96, 0.855), 16 * SS)
    pd.polygon(name, fill=(0, 0, 0, 175))
    pill = chamfer_poly(*P(0.14, 0.905), *P(0.86, 0.968), 12 * SS)
    pd.polygon(pill, fill=(0, 0, 0, 200))
    brand = [P(0.56, 0.045), P(0.955, 0.045), P(0.955, 0.13), P(0.53, 0.13)]
    pd.polygon(brand, fill=(0, 0, 0, 170))
    # OVR shadow block
    ovr = Image.new("L", plates.size, 0)
    ImageDraw.Draw(ovr).ellipse([*P(-0.05, -0.04), *P(0.45, 0.3)], fill=120)
    ovr = ovr.filter(ImageFilter.GaussianBlur(30 * SS))
    shadow = Image.new("RGBA", plates.size, (0, 0, 0, 0))
    shadow.putalpha(ovr)
    plates = Image.alpha_composite(shadow, plates)

    # outer neon border
    outer = chamfer_poly(14 * SS, 14 * SS, (CW - 14) * SS, (CH - 14) * SS, 44 * SS)
    ld.line(outer + [outer[0]], fill=(W, W, W, 255), width=5 * SS, joint="curve")
    inner = chamfer_poly(30 * SS, 30 * SS, (CW - 30) * SS, (CH - 30) * SS, 34 * SS)
    ld.line(inner + [inner[0]], fill=(W, W, W, 120), width=2 * SS, joint="curve")
    ld.line(name + [name[0]], fill=(W, W, W, 200), width=3 * SS, joint="curve")
    ld.line(pill + [pill[0]], fill=(W, W, W, 230), width=3 * SS, joint="curve")
    ld.line(brand + [brand[0]], fill=(W, W, W, 160), width=2 * SS)
    # divider in name plate
    ld.line([P(0.3, 0.7), P(0.3, 0.83)], fill=(W, W, W, 200), width=2 * SS)
    # slashes like a broadcast graphic
    for i in range(4):
        x = 0.79 + i * 0.035
        ld.polygon([P(x, 0.145), P(x + 0.018, 0.145), P(x + 0.006, 0.165), P(x - 0.012, 0.165)], fill=(W, W, W, 210))
    for i in range(4):
        x = 0.06 + i * 0.03
        ld.polygon([P(x, 0.925), P(x + 0.015, 0.925), P(x + 0.005, 0.948), P(x - 0.01, 0.948)], fill=(W, W, W, 210))
        x = 0.89 + i * 0.03 - 0.03
        ld.polygon([P(x, 0.925), P(x + 0.015, 0.925), P(x + 0.005, 0.948), P(x - 0.01, 0.948)], fill=(W, W, W, 210))
    # circuit traces from the corners
    for pts in (
        [P(0.06, 0.3), P(0.06, 0.45), P(0.1, 0.49), P(0.1, 0.6)],
        [P(0.94, 0.3), P(0.94, 0.42), P(0.9, 0.46), P(0.9, 0.6)],
        [P(0.2, 0.03), P(0.35, 0.03)],
        [P(0.45, 0.985), P(0.55, 0.985)],
    ):
        ld.line(pts, fill=(W, W, W, 150), width=2 * SS)
        for p in (pts[0], pts[-1]):
            ld.ellipse([p[0] - 4 * SS, p[1] - 4 * SS, p[0] + 4 * SS, p[1] + 4 * SS], fill=(W, W, W, 220))
    # OVR underline accent
    ld.polygon([P(0.07, 0.272), P(0.3, 0.272), P(0.28, 0.282), P(0.07, 0.282)], fill=(W, W, W, 230))

    lines = glow(lines, 10 * SS)
    img = Image.alpha_composite(plates, lines)
    finish(img, CW, CH, "card_frame")


def card_back():
    img = canvas(CW, CH)
    d = ImageDraw.Draw(img)
    poly = chamfer_poly(6 * SS, 6 * SS, (CW - 6) * SS, (CH - 6) * SS, 46 * SS)
    d.polygon(poly, fill=(16, 20, 32, 255))
    # hex pattern
    pat = canvas(CW, CH)
    pdw = ImageDraw.Draw(pat)
    r = 26 * SS
    for row in range(-1, 40):
        for col in range(-1, 20):
            cx = col * r * 1.75 + (row % 2) * r * 0.875
            cy = row * r * 1.5
            pts = [(cx + r * 0.9 * math.cos(math.pi / 3 * k + math.pi / 6), cy + r * 0.9 * math.sin(math.pi / 3 * k + math.pi / 6)) for k in range(6)]
            pdw.line(pts + [pts[0]], fill=(255, 255, 255, 22), width=2 * SS)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    pat.putalpha(ImageChops.multiply(pat.getchannel("A"), mask))
    img = Image.alpha_composite(img, pat)
    # shield emblem
    em = canvas(CW, CH)
    ed = ImageDraw.Draw(em)
    shield = [P(0.5, 0.3), P(0.72, 0.36), P(0.7, 0.55), P(0.5, 0.7), P(0.3, 0.55), P(0.28, 0.36)]
    ed.line(shield + [shield[0]], fill=(255, 255, 255, 255), width=6 * SS, joint="curve")
    ball = [*P(0.39, 0.44), *P(0.61, 0.56)]
    ed.ellipse(ball, outline=(255, 255, 255, 255), width=5 * SS)
    ed.line([P(0.45, 0.5), P(0.55, 0.5)], fill=(255, 255, 255, 255), width=4 * SS)
    for i in range(4):
        x = 0.465 + i * 0.023
        ed.line([P(x, 0.485), P(x, 0.515)], fill=(255, 255, 255, 255), width=3 * SS)
    em = glow(em, 14 * SS)
    img = Image.alpha_composite(img, em)
    finish(img, CW, CH, "card_back")


# ----------------------------------------------------------------------------- packs
def pack_art():
    W_, H_ = 400, 580
    img = canvas(W_, H_)
    w, h = img.size
    d = ImageDraw.Draw(img)
    teeth = 16
    top, bot = [], []
    for i in range(teeth + 1):
        x = 20 * SS + (w - 40 * SS) * i / teeth
        top.append((x, (34 if i % 2 else 20) * SS))
        bot.append((x, h - (34 if i % 2 else 20) * SS))
    body = top + [(w - 20 * SS, h - 20 * SS)] + list(reversed(bot)) + [(20 * SS, 20 * SS)]
    d.polygon(body, fill=(200, 200, 200, 255))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(body, fill=255)
    # metallic sheen: diagonal bands
    sheen = Image.new("L", img.size, 0)
    sd = ImageDraw.Draw(sheen)
    for i, (off, width, val) in enumerate([(0.15, 0.08, 255), (0.32, 0.03, 220), (0.6, 0.12, 245), (0.85, 0.04, 210)]):
        x = off * w
        sd.polygon([(x, 0), (x + width * w, 0), (x + width * w - h * 0.5, h), (x - h * 0.5, h)], fill=val)
    sheen = sheen.filter(ImageFilter.GaussianBlur(14 * SS))
    base = Image.new("L", img.size, 150)
    lum = ImageChops.lighter(base, sheen)
    # vertical darkening to bottom
    grad = Image.new("L", img.size, 0)
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        gd.line([(0, y), (w, y)], fill=int(90 * (y / h)))
    lum = ImageChops.subtract(lum, grad)
    rgb = Image.merge("RGBA", (lum, lum, lum, mask))
    img = rgb
    d = ImageDraw.Draw(img)
    # crimp lines
    d.line([(20 * SS, 52 * SS), (w - 20 * SS, 52 * SS)], fill=(255, 255, 255, 200), width=2 * SS)
    d.line([(20 * SS, h - 52 * SS), (w - 20 * SS, h - 52 * SS)], fill=(255, 255, 255, 200), width=2 * SS)
    # emblem: football in a shield
    em = canvas(W_, H_)
    ed = ImageDraw.Draw(em)
    cx, cy = w / 2, h * 0.42
    s = w * 0.3
    shield = [(cx, cy - s), (cx + s * 0.85, cy - s * 0.72), (cx + s * 0.78, cy + s * 0.25), (cx, cy + s * 0.95), (cx - s * 0.78, cy + s * 0.25), (cx - s * 0.85, cy - s * 0.72)]
    ed.polygon(shield, fill=(20, 20, 24, 210))
    ed.line(shield + [shield[0]], fill=(255, 255, 255, 255), width=5 * SS, joint="curve")
    ed.ellipse([cx - s * 0.5, cy - s * 0.3, cx + s * 0.5, cy + s * 0.3], fill=(255, 255, 255, 255))
    ed.line([(cx - s * 0.22, cy), (cx + s * 0.22, cy)], fill=(20, 20, 24, 255), width=4 * SS)
    for i in range(5):
        x = cx - s * 0.16 + i * s * 0.08
        ed.line([(x, cy - s * 0.07), (x, cy + s * 0.07)], fill=(20, 20, 24, 255), width=3 * SS)
    em = glow(em, 8 * SS)
    img = Image.alpha_composite(img, em)
    finish(img, W_, H_, "pack")


def rays():
    S = 512
    img = canvas(S, S)
    w, h = img.size
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2
    n = 18
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = a0 + math.pi / n * 0.6
        d.polygon([(cx, cy), (cx + math.cos(a0) * w, cy + math.sin(a0) * h), (cx + math.cos(a1) * w, cy + math.sin(a1) * h)], fill=(255, 255, 255, 160))
    radial = Image.new("L", img.size, 0)
    rd = ImageDraw.Draw(radial)
    for r in range(int(w / 2), 0, -4):
        rd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=int(255 * (1 - r / (w / 2)) ** 0.8))
    img.putalpha(ImageChops.multiply(img.getchannel("A"), radial))
    img = img.filter(ImageFilter.GaussianBlur(3 * SS))
    finish(img, S, S, "rays")


# ----------------------------------------------------------------------------- icons (white)
def icon(name, draw_fn, size=256):
    img = canvas(size, size)
    d = ImageDraw.Draw(img)
    s = size * SS
    draw_fn(d, s)
    finish(img, size, size, "icon_" + name)


def ic_football(d, s):
    d.ellipse([s * 0.08, s * 0.26, s * 0.92, s * 0.74], fill=(255, 255, 255, 255))
    d.line([(s * 0.32, s * 0.5), (s * 0.68, s * 0.5)], fill=(0, 0, 0, 0), width=int(s * 0.05))
    for i in range(5):
        x = s * (0.38 + i * 0.06)
        d.line([(x, s * 0.43), (x, s * 0.57)], fill=(0, 0, 0, 0), width=int(s * 0.035))


def ic_packs(d, s):
    for i, (dx, rot) in enumerate([(-0.12, -14), (0.0, 0), (0.12, 14)]):
        card = Image.new("RGBA", (int(s * 0.42), int(s * 0.6)), (0, 0, 0, 0))
        cd = ImageDraw.Draw(card)
        cd.rounded_rectangle([0, 0, card.width - 1, card.height - 1], radius=int(s * 0.05), fill=(255, 255, 255, 255 if i == 1 else 200), outline=(0, 0, 0, 0))
        card = card.rotate(-rot, expand=True, resample=Image.BICUBIC)
        d._image.alpha_composite(card, (int(s * (0.5 + dx) - card.width / 2), int(s * 0.5 - card.height / 2)))


def ic_lineup(d, s):
    w = int(s * 0.06)
    for cx, cy in [(0.28, 0.32), (0.72, 0.32), (0.5, 0.5)]:
        r = s * 0.09
        d.line([(s * cx - r, s * cy - r), (s * cx + r, s * cy + r)], fill="white", width=w)
        d.line([(s * cx - r, s * cy + r), (s * cx + r, s * cy - r)], fill="white", width=w)
    for cx, cy in [(0.28, 0.75), (0.72, 0.75)]:
        r = s * 0.1
        d.ellipse([s * cx - r, s * cy - r, s * cx + r, s * cy + r], outline="white", width=w)
    d.line([(s * 0.5, s * 0.62), (s * 0.5, s * 0.88)], fill="white", width=int(s * 0.04))


def ic_collection(d, s):
    for cx in (0.3, 0.7):
        for cy in (0.3, 0.7):
            d.rounded_rectangle([s * (cx - 0.15), s * (cy - 0.18), s * (cx + 0.15), s * (cy + 0.18)], radius=int(s * 0.04), fill="white")


def ic_coin(d, s):
    d.ellipse([s * 0.06, s * 0.06, s * 0.94, s * 0.94], fill=(255, 255, 255, 255))
    d.ellipse([s * 0.16, s * 0.16, s * 0.84, s * 0.84], fill=(0, 0, 0, 0), outline=(0, 0, 0, 0))
    d.ellipse([s * 0.16, s * 0.16, s * 0.84, s * 0.84], outline=(170, 170, 170, 255), width=int(s * 0.04))
    star = []
    for k in range(10):
        r = s * (0.25 if k % 2 == 0 else 0.11)
        a = -math.pi / 2 + k * math.pi / 5
        star.append((s * 0.5 + r * math.cos(a), s * 0.5 + r * math.sin(a)))
    d.polygon(star, fill=(170, 170, 170, 255))


def ic_trophy(d, s):
    d.polygon([(s * 0.25, s * 0.15), (s * 0.75, s * 0.15), (s * 0.68, s * 0.5), (s * 0.5, s * 0.6), (s * 0.32, s * 0.5)], fill="white")
    d.arc([s * 0.08, s * 0.18, s * 0.36, s * 0.45], 90, 270, fill="white", width=int(s * 0.05))
    d.arc([s * 0.64, s * 0.18, s * 0.92, s * 0.45], -90, 90, fill="white", width=int(s * 0.05))
    d.rectangle([s * 0.45, s * 0.58, s * 0.55, s * 0.75], fill="white")
    d.rounded_rectangle([s * 0.3, s * 0.75, s * 0.7, s * 0.86], radius=int(s * 0.03), fill="white")


def ic_close(d, s):
    w = int(s * 0.12)
    d.line([(s * 0.25, s * 0.25), (s * 0.75, s * 0.75)], fill="white", width=w)
    d.line([(s * 0.25, s * 0.75), (s * 0.75, s * 0.25)], fill="white", width=w)


def ic_switch(d, s):
    w = int(s * 0.08)
    d.arc([s * 0.15, s * 0.15, s * 0.85, s * 0.85], 200, 340, fill="white", width=w)
    d.arc([s * 0.15, s * 0.15, s * 0.85, s * 0.85], 20, 160, fill="white", width=w)
    d.polygon([(s * 0.8, s * 0.2), (s * 0.9, s * 0.42), (s * 0.68, s * 0.4)], fill="white")
    d.polygon([(s * 0.2, s * 0.8), (s * 0.1, s * 0.58), (s * 0.32, s * 0.6)], fill="white")


def ic_whistle(d, s):
    d.ellipse([s * 0.15, s * 0.35, s * 0.6, s * 0.8], fill="white")
    d.rectangle([s * 0.38, s * 0.35, s * 0.88, s * 0.52], fill="white")
    d.ellipse([s * 0.3, s * 0.5, s * 0.45, s * 0.65], fill=(0, 0, 0, 0))


def ic_jersey(d, s):
    # football jersey: shoulders, short sleeves, body, V-neck and a number
    body = [(0.34, 0.14), (0.42, 0.14), (0.5, 0.24), (0.58, 0.14), (0.66, 0.14), (0.92, 0.26), (0.84, 0.48),
            (0.74, 0.44), (0.74, 0.88), (0.26, 0.88), (0.26, 0.44), (0.16, 0.48), (0.08, 0.26)]
    d.polygon([(s * x, s * y) for x, y in body], fill="white")
    # number 1 cut out of the chest
    d.rectangle([s * 0.46, s * 0.4, s * 0.56, s * 0.76], fill=(0, 0, 0, 0))
    d.polygon([(s * 0.46, s * 0.4), (s * 0.56, s * 0.4), (s * 0.4, s * 0.5), (s * 0.4, s * 0.44)], fill=(0, 0, 0, 0))
    d.rectangle([s * 0.4, s * 0.72, s * 0.62, s * 0.78], fill=(0, 0, 0, 0))


def ic_eye(d, s, slash=False):
    w = int(s * 0.07)
    # almond outline
    d.arc([s * 0.06, s * 0.22, s * 0.94, s * 0.98], 200, 340, fill="white", width=w)
    d.arc([s * 0.06, s * 0.02, s * 0.94, s * 0.78], 20, 160, fill="white", width=w)
    d.ellipse([s * 0.36, s * 0.36, s * 0.64, s * 0.64], fill="white")
    if slash:
        d.line([(s * 0.14, s * 0.86), (s * 0.86, s * 0.14)], fill=(0, 0, 0, 0), width=int(s * 0.16))
        d.line([(s * 0.14, s * 0.86), (s * 0.86, s * 0.14)], fill="white", width=w)


def ic_eyeoff(d, s):
    ic_eye(d, s, slash=True)


def ic_chevron(d, s):
    w = int(s * 0.11)
    d.line([(s * 0.2, s * 0.36), (s * 0.5, s * 0.66), (s * 0.8, s * 0.36)], fill="white", width=w, joint="curve")


def ic_gear(d, s):
    cx = cy = s / 2
    teeth = 8
    pts = []
    for k in range(teeth * 4):
        a = k * 2 * math.pi / (teeth * 4) + math.pi / (teeth * 4)
        r = s * (0.45 if (k % 4) in (1, 2) else 0.34)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts, fill="white")
    r = s * 0.15
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0, 0, 0, 0))


def ic_invite(d, s):
    # a person with a "+" beside them
    d.ellipse([s * 0.14, s * 0.12, s * 0.48, s * 0.46], fill="white")
    d.chord([s * 0.02, s * 0.5, s * 0.6, s * 1.08], 180, 360, fill="white")
    w = int(s * 0.1)
    d.line([(s * 0.79, s * 0.3), (s * 0.79, s * 0.66)], fill="white", width=w)
    d.line([(s * 0.61, s * 0.48), (s * 0.97, s * 0.48)], fill="white", width=w)


def shadow_slice():
    """Soft drop shadow for 9-slice use: 128x128, blurred rounded rect, slice center 40..88."""
    from PIL import ImageFilter
    size = 128
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([28, 28, size - 28, size - 28], radius=18, fill=(0, 0, 0, 200))
    img = img.filter(ImageFilter.GaussianBlur(11))
    img.save(OUT / "shadow.png")
    print("  wrote shadow")


# ----------------------------------------------------------------------------- badges
# Roblox badge images: 512x512, shown cropped to a circle. Shapes only (no text).
BADGES = {
    "rookie_camp": ("2ec27e", "0f5132", "whistle"),
    "first_win": ("3b82f6", "102a5c", "trophy"),
    "wins_10": ("8b5cf6", "2e1065", "trophy2"),
    "wins_50": ("f5b301", "5c3d00", "trophy3"),
    "elite_pull": ("a855f7", "3b0764", "card"),
    "icon_pull": ("ffd54a", "6b4a00", "cardstar"),
    "ballhawk": ("0ea5e9", "0c2d48", "wings"),
    "gold_div": ("eab308", "4a3500", "shield"),
    "dynasty_div": ("ef4444", "3f0a0a", "crown"),
    "rainbow": ("ff4fd8", "1e1b4b", "rainbow"),
}


def badge(key, col, dark, emblem):
    S = 512
    s = S * SS
    img = canvas(S, S)
    d = ImageDraw.Draw(img)
    c1, c0 = hexrgb(col), hexrgb(dark)
    # background disc: radial blend from color (upper left) to dark
    for i in range(60, 0, -1):
        t = i / 60
        r = s * 0.5 * t
        cx, cy = s * (0.5 - 0.12 * (1 - t)), s * (0.5 - 0.14 * (1 - t))
        mix = tuple(int(c0[k] + (c1[k] - c0[k]) * (1 - t) ** 0.8) for k in range(3))
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=mix + (255,))
    # rings
    d.ellipse([s * 0.03, s * 0.03, s * 0.97, s * 0.97], outline=(255, 255, 255, 230), width=int(s * 0.03))
    d.ellipse([s * 0.09, s * 0.09, s * 0.91, s * 0.91], outline=c1 + (200,), width=int(s * 0.012))
    # rays behind the emblem (own layer so they blend instead of punching holes)
    rays_l = canvas(S, S)
    rd = ImageDraw.Draw(rays_l)
    for k in range(16):
        a = k * math.pi / 8
        rd.polygon([(s / 2, s / 2), (s / 2 + s * 0.42 * math.cos(a - 0.07), s / 2 + s * 0.42 * math.sin(a - 0.07)),
                   (s / 2 + s * 0.42 * math.cos(a + 0.07), s / 2 + s * 0.42 * math.sin(a + 0.07))], fill=(255, 255, 255, 26))
    img.alpha_composite(rays_l.filter(ImageFilter.GaussianBlur(2 * SS)))

    em = canvas(S, S)
    e = ImageDraw.Draw(em)
    W = (255, 255, 255, 255)

    def trophy(scale=1.0, dy=0.0):
        def q(x, y):
            return (s * (0.5 + (x - 0.5) * scale), s * (0.5 + (y - 0.5) * scale + dy))
        e.polygon([q(0.3, 0.24), q(0.7, 0.24), q(0.65, 0.5), q(0.5, 0.58), q(0.35, 0.5)], fill=W)
        e.arc([*q(0.18, 0.26), *q(0.38, 0.46)], 90, 270, fill=W, width=int(s * 0.035 * scale))
        e.arc([*q(0.62, 0.26), *q(0.82, 0.46)], -90, 90, fill=W, width=int(s * 0.035 * scale))
        e.rectangle([*q(0.46, 0.56), *q(0.54, 0.68)], fill=W)
        e.rounded_rectangle([*q(0.36, 0.68), *q(0.64, 0.76)], radius=int(s * 0.02), fill=W)

    def feather(x, y, rx, ry, angle):
        # one rounded leaf/feather (an ellipse) centered at x, y, rotated by angle degrees
        size = int(max(rx, ry) * 2 + 8)
        f = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(f).ellipse([size / 2 - rx, size / 2 - ry, size / 2 + rx, size / 2 + ry], fill=W)
        f = f.rotate(angle, resample=Image.BICUBIC)
        em.alpha_composite(f, (int(x - size / 2), int(y - size / 2)))

    def stars(n, y):
        for i in range(n):
            x = 0.5 + (i - (n - 1) / 2) * 0.12
            e.polygon(star_pts(s * x, s * y, s * 0.045, s * 0.019), fill=W)

    def card(star=False):
        cardimg = Image.new("RGBA", (int(s * 0.36), int(s * 0.5)), (0, 0, 0, 0))
        cd = ImageDraw.Draw(cardimg)
        cd.rounded_rectangle([0, 0, cardimg.width - 1, cardimg.height - 1], radius=int(s * 0.04), fill=W)
        cd.rounded_rectangle([s * 0.03, s * 0.03, cardimg.width - s * 0.03, cardimg.height - s * 0.03], radius=int(s * 0.03), outline=c0 + (255,), width=int(s * 0.012))
        if star:
            cd.polygon(star_pts(cardimg.width / 2, cardimg.height * 0.45, s * 0.11, s * 0.045), fill=c1 + (255,))
        else:
            cd.polygon([(cardimg.width / 2, cardimg.height * 0.2), (cardimg.width * 0.78, cardimg.height * 0.45),
                        (cardimg.width / 2, cardimg.height * 0.7), (cardimg.width * 0.22, cardimg.height * 0.45)], fill=c1 + (255,))
        cardimg = cardimg.rotate(-10, expand=True, resample=Image.BICUBIC)
        em.alpha_composite(cardimg, (int(s / 2 - cardimg.width / 2), int(s / 2 - cardimg.height / 2)))

    if emblem == "whistle":
        e.ellipse([s * 0.26, s * 0.4, s * 0.56, s * 0.7], fill=W)
        e.rectangle([s * 0.41, s * 0.4, s * 0.76, s * 0.52], fill=W)
        e.ellipse([s * 0.35, s * 0.49, s * 0.47, s * 0.61], fill=(0, 0, 0, 0))
        e.arc([s * 0.3, s * 0.22, s * 0.62, s * 0.5], 200, 300, fill=W, width=int(s * 0.02))
    elif emblem == "trophy":
        trophy()
    elif emblem == "trophy2":
        trophy(0.85, -0.04)
        stars(2, 0.78)
    elif emblem == "trophy3":
        trophy(0.8, -0.06)
        stars(3, 0.77)
        for side in (-1, 1):  # laurel branches: leaves along an arc, pointing up
            for k in range(5):
                a = math.radians(115 + k * 20) if side < 0 else math.radians(65 - k * 20)
                x, y = s / 2 + s * 0.33 * math.cos(a), s * 0.5 + s * 0.28 * math.sin(a)
                feather(x, y, s * 0.028, s * 0.062, -math.degrees(a) - side * 25)
    elif emblem == "card":
        card(False)
    elif emblem == "cardstar":
        card(True)
    elif emblem == "wings":
        # a football with swept-back wings
        for side in (-1, 1):
            for k, t in enumerate((12, 34, 56, 78)):
                length = s * (0.26 - k * 0.035)
                bx, by = s / 2 + side * s * 0.13, s * 0.49
                tr = math.radians(t)
                cx, cy = bx + side * math.cos(tr) * length / 2, by - math.sin(tr) * length / 2
                feather(cx, cy, s * 0.036, length / 2, (t - 90) if side > 0 else (90 - t))
        e.ellipse([s * 0.34, s * 0.42, s * 0.66, s * 0.6], fill=W)
        e.line([(s * 0.44, s * 0.51), (s * 0.56, s * 0.51)], fill=c0 + (255,), width=int(s * 0.016))
        for k in range(4):
            x = s * (0.46 + k * 0.027)
            e.line([(x, s * 0.49), (x, s * 0.53)], fill=c0 + (255,), width=int(s * 0.01))
    elif emblem == "shield":
        e.polygon([(s * 0.5, s * 0.2), (s * 0.76, s * 0.3), (s * 0.72, s * 0.6), (s * 0.5, s * 0.8), (s * 0.28, s * 0.6), (s * 0.24, s * 0.3)], fill=W)
        for k in range(2):
            y = s * (0.42 + k * 0.12)
            e.line([(s * 0.36, y), (s * 0.5, y + s * 0.08), (s * 0.64, y)], fill=c1 + (255,), width=int(s * 0.04), joint="curve")
    elif emblem == "crown":
        e.polygon([(s * 0.24, s * 0.66), (s * 0.24, s * 0.34), (s * 0.37, s * 0.48), (s * 0.5, s * 0.26), (s * 0.63, s * 0.48), (s * 0.76, s * 0.34), (s * 0.76, s * 0.66)], fill=W)
        e.rounded_rectangle([s * 0.24, s * 0.68, s * 0.76, s * 0.76], radius=int(s * 0.02), fill=W)
        for x in (0.37, 0.5, 0.63):
            e.ellipse([s * (x - 0.03), s * 0.55, s * (x + 0.03), s * 0.61], fill=c1 + (255,))
    elif emblem == "rainbow":
        cols = ["ff3b3b", "ff9f1a", "ffe14d", "3ddc84", "3b82f6", "a855f7"]
        for i, h in enumerate(cols):
            r = s * (0.33 - i * 0.04)
            e.arc([s / 2 - r, s * 0.62 - r, s / 2 + r, s * 0.62 + r], 180, 360, fill=hexrgb(h) + (255,), width=int(s * 0.04))
        e.polygon(star_pts(s * 0.5, s * 0.55, s * 0.08, s * 0.035), fill=W)
    # emblem drop shadow, then the emblem
    sh = em.getchannel("A").filter(ImageFilter.GaussianBlur(8 * SS))
    shadow = Image.new("RGBA", em.size, (0, 0, 0, 0))
    shadow.putalpha(sh.point(lambda v: int(v * 0.55)))
    img.alpha_composite(shadow, (0, int(6 * SS)))
    img.alpha_composite(em)
    finish(img, S, S, "badge_" + key)


# ----------------------------------------------------------------------------- team logos
def star_pts(cx, cy, r1, r2, n=5, rot=-math.pi / 2):
    pts = []
    for k in range(n * 2):
        r = r1 if k % 2 == 0 else r2
        a = rot + k * math.pi / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def glyph(d, kind, s, col):
    c = col
    W = int(s * 0.05)
    if kind == "ship":
        d.polygon([(s * .3, s * .65), (s * .7, s * .65), (s * .62, s * .74), (s * .38, s * .74)], fill=c)
        d.polygon([(s * .48, s * .25), (s * .48, s * .6), (s * .3, s * .6)], fill=c)
        d.polygon([(s * .52, s * .3), (s * .52, s * .6), (s * .7, s * .6)], fill=c)
    elif kind == "snowflake":
        for k in range(6):
            a = k * math.pi / 3
            x, y = s * .5 + math.cos(a) * s * .26, s * .5 + math.sin(a) * s * .26
            d.line([(s * .5, s * .5), (x, y)], fill=c, width=W)
            for t in (0.55, 0.8):
                bx, by = s * .5 + math.cos(a) * s * .26 * t, s * .5 + math.sin(a) * s * .26 * t
                for sgn in (-1, 1):
                    d.line([(bx, by), (bx + math.cos(a + sgn * 0.8) * s * .07, by + math.sin(a + sgn * 0.8) * s * .07)], fill=c, width=int(W * .7))
    elif kind == "fish":
        d.ellipse([s * .25, s * .4, s * .68, s * .6], fill=c)
        d.polygon([(s * .66, s * .5), (s * .8, s * .38), (s * .78, s * .62)], fill=c)
        d.polygon([(s * .4, s * .41), (s * .5, s * .3), (s * .55, s * .42)], fill=c)
    elif kind == "wave":
        d.pieslice([s * .25, s * .3, s * .7, s * .75], 180, 360, fill=c)
        d.rectangle([s * .2, s * .52, s * .8, s * .66], fill=c)
        d.ellipse([s * .4, s * .42, s * .56, s * .56], fill=(0, 0, 0, 0))
    elif kind == "anvil":
        d.polygon([(s * .25, s * .38), (s * .75, s * .38), (s * .68, s * .48), (s * .58, s * .5), (s * .6, s * .62), (s * .4, s * .62), (s * .42, s * .5), (s * .32, s * .48)], fill=c)
        d.rectangle([s * .35, s * .62, s * .65, s * .7], fill=c)
        d.polygon(star_pts(s * .7, s * .26, s * .07, s * .03, 4), fill=c)
    elif kind == "anchor":
        d.line([(s * .5, s * .28), (s * .5, s * .72)], fill=c, width=W)
        d.ellipse([s * .44, s * .2, s * .56, s * .32], outline=c, width=int(W * .7))
        d.line([(s * .36, s * .38), (s * .64, s * .38)], fill=c, width=W)
        d.arc([s * .28, s * .45, s * .72, s * .76], 20, 160, fill=c, width=W)
    elif kind == "bolt":
        d.polygon([(s * .55, s * .2), (s * .32, s * .55), (s * .48, s * .55), (s * .42, s * .8), (s * .68, s * .42), (s * .52, s * .42)], fill=c)
    elif kind == "wheel":
        d.ellipse([s * .27, s * .27, s * .73, s * .73], outline=c, width=W)
        for k in range(8):
            a = k * math.pi / 4
            d.line([(s * .5, s * .5), (s * .5 + math.cos(a) * s * .23, s * .5 + math.sin(a) * s * .23)], fill=c, width=int(W * .6))
        d.ellipse([s * .44, s * .44, s * .56, s * .56], fill=c)
    elif kind == "planet":
        d.ellipse([s * .34, s * .34, s * .66, s * .66], fill=c)
        d.ellipse([s * .18, s * .44, s * .82, s * .56], outline=c, width=int(W * .7))
    elif kind == "sheriff":
        d.polygon(star_pts(s * .5, s * .5, s * .27, s * .13, 6), fill=c)
        for k in range(6):
            a = -math.pi / 2 + k * math.pi / 3
            x, y = s * .5 + math.cos(a) * s * .27, s * .5 + math.sin(a) * s * .27
            d.ellipse([x - s * .03, y - s * .03, x + s * .03, y + s * .03], fill=c)
    elif kind == "mountain":
        d.polygon([(s * .2, s * .7), (s * .42, s * .32), (s * .55, s * .52), (s * .63, s * .4), (s * .8, s * .7)], fill=c)
    elif kind == "tornado":
        for i, (w_, y) in enumerate([(.5, .28), (.42, .37), (.34, .46), (.26, .55), (.18, .64), (.1, .72)]):
            x = .5 + (i % 2) * 0.02
            d.ellipse([s * (x - w_ / 2), s * (y - .035), s * (x + w_ / 2), s * (y + .035)], fill=c)
    elif kind == "dice":
        d.rounded_rectangle([s * .3, s * .3, s * .7, s * .7], radius=int(s * .06), fill=c)
        for px, py in [(.4, .4), (.6, .6), (.5, .5), (.6, .4), (.4, .6)]:
            d.ellipse([s * (px - .035), s * (py - .035), s * (px + .035), s * (py + .035)], fill=(0, 0, 0, 0))
    elif kind == "star":
        d.polygon(star_pts(s * .55, s * .45, s * .22, s * .09), fill=c)
        for i in range(3):
            d.line([(s * (.2 + i * .04), s * (.62 + i * .06)), (s * (.4 + i * .04), s * (.55 + i * .06))], fill=c, width=int(W * .6))
    elif kind == "snake":
        d.arc([s * .3, s * .22, s * .62, s * .5], 90, 360, fill=c, width=W)
        d.arc([s * .38, s * .46, s * .7, s * .76], 270, 180 + 360, fill=c, width=W)
        d.ellipse([s * .55, s * .3, s * .67, s * .38], fill=c)
    elif kind == "crown":
        d.polygon([(s * .25, s * .66), (s * .25, s * .36), (s * .37, s * .5), (s * .5, s * .3), (s * .63, s * .5), (s * .75, s * .36), (s * .75, s * .66)], fill=c)
    elif kind == "bell":
        d.pieslice([s * .3, s * .26, s * .7, s * .66], 180, 360, fill=c)
        d.polygon([(s * .3, s * .46), (s * .7, s * .46), (s * .76, s * .66), (s * .24, s * .66)], fill=c)
        d.ellipse([s * .45, s * .64, s * .55, s * .74], fill=c)
    elif kind == "shield":
        sh = [(s * .5, s * .24), (s * .72, s * .32), (s * .7, s * .52), (s * .5, s * .76), (s * .3, s * .52), (s * .28, s * .32)]
        d.polygon(sh, fill=c)
        d.line([(s * .36, s * .42), (s * .5, s * .52), (s * .64, s * .42)], fill=(0, 0, 0, 0), width=W)
    elif kind == "wind":
        for y, r in [(.36, .2), (.5, .26), (.64, .16)]:
            d.line([(s * .2, s * y), (s * (.2 + r * 2), s * y)], fill=c, width=int(W * .8))
            d.arc([s * (.2 + r * 2 - .08), s * (y - .12), s * (.2 + r * 2 + .08), s * y], 270, 180 + 360, fill=c, width=int(W * .8))
    elif kind == "gear":
        for k in range(8):
            a = k * math.pi / 4
            x, y = s * .5 + math.cos(a) * s * .25, s * .5 + math.sin(a) * s * .25
            d.ellipse([x - s * .06, y - s * .06, x + s * .06, y + s * .06], fill=c)
        d.ellipse([s * .28, s * .28, s * .72, s * .72], fill=c)
        d.ellipse([s * .42, s * .42, s * .58, s * .58], fill=(0, 0, 0, 0))
    elif kind == "axes":
        for sgn in (-1, 1):
            d.line([(s * (.5 - sgn * .22), s * .74), (s * (.5 + sgn * .14), s * .3)], fill=c, width=int(W * .8))
            hx, hy = s * (.5 + sgn * .14), s * .3
            d.polygon([(hx, hy), (hx + sgn * s * .14, hy - s * .02), (hx + sgn * s * .12, hy + s * .14)], fill=c)
    elif kind == "compass":
        d.polygon(star_pts(s * .5, s * .5, s * .28, s * .07, 4), fill=c)
        d.ellipse([s * .3, s * .3, s * .7, s * .7], outline=c, width=int(W * .5))
    elif kind == "flame":
        d.polygon([(s * .5, s * .2), (s * .66, s * .45), (s * .68, s * .62), (s * .58, s * .76), (s * .42, s * .76), (s * .32, s * .62), (s * .36, s * .44), (s * .44, s * .52)], fill=c)
    elif kind == "tree":
        for i, (y, w_) in enumerate([(.24, .14), (.38, .22), (.52, .3)]):
            d.polygon([(s * .5, s * y), (s * (.5 + w_), s * (y + .2)), (s * (.5 - w_), s * (y + .2))], fill=c)
        d.rectangle([s * .46, s * .72, s * .54, s * .8], fill=c)
    elif kind == "mask":
        d.polygon([(s * .2, s * .4), (s * .5, s * .46), (s * .8, s * .4), (s * .74, s * .58), (s * .5, s * .62), (s * .26, s * .58)], fill=c)
        d.ellipse([s * .3, s * .45, s * .42, s * .53], fill=(0, 0, 0, 0))
        d.ellipse([s * .58, s * .45, s * .7, s * .53], fill=(0, 0, 0, 0))
        d.polygon([(s * .7, s * .4), (s * .78, s * .2), (s * .8, s * .4)], fill=c)
    elif kind == "manatee":
        d.ellipse([s * .22, s * .4, s * .7, s * .62], fill=c)
        d.ellipse([s * .64, s * .42, s * .82, s * .6], fill=c)
        d.ellipse([s * .3, s * .45, s * .36, s * .5], fill=(0, 0, 0, 0))
    elif kind == "scorpion":
        d.ellipse([s * .3, s * .55, s * .55, s * .72], fill=c)
        d.arc([s * .45, s * .25, s * .75, s * .65], 270, 90 + 360, fill=c, width=W)
        d.polygon([(s * .58, s * .26), (s * .5, s * .22), (s * .56, s * .34)], fill=c)
    elif kind == "cloud":
        for bx, by, r in [(.38, .52, .13), (.52, .44, .16), (.65, .53, .12)]:
            d.ellipse([s * (bx - r), s * (by - r), s * (bx + r), s * (by + r)], fill=c)
        d.rectangle([s * .26, s * .52, s * .76, s * .65], fill=c)
    elif kind == "fin":
        d.polygon([(s * .32, s * .62), (s * .58, s * .24), (s * .6, s * .62)], fill=c)
        d.arc([s * .18, s * .58, s * .82, s * .78], 180, 360, fill=c, width=int(W * .7))
    else:
        d.ellipse([s * .35, s * .35, s * .65, s * .65], fill=c)


TEAM_GLYPH = {
    "BOS": "ship", "BUF": "snowflake", "MIA": "fish", "JER": "wave", "PIT": "anvil", "BAL": "anchor",
    "CLE": "bolt", "CIN": "wheel", "HOU": "planet", "IND": "bolt", "JAX": "wave", "NSH": "sheriff",
    "DEN": "mountain", "KCY": "tornado", "LVG": "dice", "LAS": "star", "DAL": "snake", "NYE": "crown",
    "PHI": "bell", "WAS": "shield", "CHI": "wind", "DET": "gear", "GBY": "axes", "MIN": "compass",
    "ATL": "flame", "CAR": "tree", "NOL": "mask", "TPA": "manatee", "ARZ": "scorpion", "LAW": "flame",
    "SFG": "cloud", "SEA": "fin",
}


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def team_logo(team):
    S = 256
    img = canvas(S, S)
    s = S * SS
    d = ImageDraw.Draw(img)
    p, q = hexrgb(team["primary"]), hexrgb(team["secondary"])
    if abs(lum(p) - lum(q)) < 60:
        q = (255, 255, 255) if lum(p) < 140 else (15, 15, 20)
    d.ellipse([s * .04, s * .04, s * .96, s * .96], fill=(*q, 255))
    d.ellipse([s * .1, s * .1, s * .9, s * .9], fill=(12, 14, 20, 255))
    d.ellipse([s * .13, s * .13, s * .87, s * .87], fill=(*p, 255))
    # inner shine
    shine = Image.new("L", img.size, 0)
    ImageDraw.Draw(shine).ellipse([s * .18, s * .1, s * .82, s * .55], fill=60)
    shine = shine.filter(ImageFilter.GaussianBlur(20 * SS))
    white = Image.new("RGBA", img.size, (255, 255, 255, 0))
    white.putalpha(ImageChops.multiply(shine, img.getchannel("A")))
    img = Image.alpha_composite(img, white)
    gl = canvas(S, S)
    glyph(ImageDraw.Draw(gl), TEAM_GLYPH.get(team["id"], ""), s, (*q, 255))
    # punch-out holes: draw transparent marks show the primary underneath -> use alpha composite
    shadow = gl.filter(ImageFilter.GaussianBlur(5 * SS))
    shadow_dark = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow_dark.putalpha(shadow.getchannel("A").point(lambda v: int(v * 0.6)))
    img = Image.alpha_composite(img, shadow_dark)
    img = Image.alpha_composite(img, gl)
    finish(img, S, S, "logo_" + team["id"])


# ----------------------------------------------------------------------------- play diagrams
def play_diagram(name, routes, defense=None):
    W_, H_ = 360, 240
    img = canvas(W_, H_)
    w, h = img.size
    d = ImageDraw.Draw(img)
    los = h * 0.7
    d.line([(w * .05, los), (w * .95, los)], fill=(255, 255, 255, 120), width=2 * SS)
    X = lambda x: w * (0.5 + x / 40)
    Yp = lambda y: los - y * h * 0.018
    spots = {"WR1": (-12, 0), "OL1": (-1.6, 0), "OL2": (1.6, 0), "TE": (4.2, 0), "WR2": (12, 0), "QB": (0, -4), "RB": (2, -7)}
    if defense is None:
        for slot, (x, y) in spots.items():
            r = 9 * SS
            d.ellipse([X(x) - r, Yp(y) - r, X(x) + r, Yp(y) + r], outline=(255, 255, 255, 255), width=3 * SS)
        for slot, path in routes.items():
            x0, y0 = spots[slot]
            out = 1 if x0 >= 0 else -1
            pts = [(X(x0), Yp(y0))] + [(X(x0 + out * dx), Yp(y0 + dy)) for dx, dy in path]
            d.line(pts, fill=(255, 255, 255, 255), width=4 * SS, joint="curve")
            (ax, ay), (bx, by) = pts[-2], pts[-1]
            ang = math.atan2(by - ay, bx - ax)
            L_ = 14 * SS
            d.polygon([(bx, by), (bx - L_ * math.cos(ang - 0.45), by - L_ * math.sin(ang - 0.45)), (bx - L_ * math.cos(ang + 0.45), by - L_ * math.sin(ang + 0.45))], fill=(255, 255, 255, 255))
    else:
        for (x, y), kind in defense:
            r = 9 * SS
            cx, cy = X(x), Yp(y)
            d.line([(cx - r, cy - r), (cx + r, cy + r)], fill=(255, 255, 255, 255), width=4 * SS)
            d.line([(cx - r, cy + r), (cx + r, cy - r)], fill=(255, 255, 255, 255), width=4 * SS)
            if kind == "rush":
                d.line([(cx, cy + r), (cx, Yp(-3))], fill=(255, 255, 255, 230), width=3 * SS)
            elif kind == "deep":
                d.ellipse([cx - 34 * SS, cy - 22 * SS, cx + 34 * SS, cy + 10 * SS], outline=(255, 255, 255, 140), width=3 * SS)
            elif kind == "man":
                d.line([(cx, cy), (cx, cy - 22 * SS)], fill=(255, 255, 255, 150), width=3 * SS)
    finish(img, W_, H_, "play_" + name)


def main():
    print("Cards"); card_base(); card_tint(); card_frame(); card_back()
    print("Packs"); pack_art(); rays()
    print("Icons")
    for n, f in [("football", ic_football), ("packs", ic_packs), ("lineup", ic_lineup), ("collection", ic_collection),
                 ("coin", ic_coin), ("trophy", ic_trophy), ("close", ic_close), ("switch", ic_switch), ("whistle", ic_whistle), ("jersey", ic_jersey),
                 ("eye", ic_eye), ("eyeoff", ic_eyeoff), ("chevron", ic_chevron), ("gear", ic_gear), ("invite", ic_invite)]:
        icon(n, f)
    print("Plays")
    play_diagram("quick", {"WR1": [(0, 3), (-6, 8), (-12, 14)], "WR2": [(0, 6), (7, 6)], "TE": [(0, 2), (-8, 4), (-16, 4)], "RB": [(3, 1), (9, 2)]})
    play_diagram("deep", {"WR1": [(0, 26)], "WR2": [(0, 10), (-9, 24)], "TE": [(0, 22)]})
    play_diagram("run", {"RB": [(-1, 3), (-2, 12)], "WR1": [(0, 8)], "WR2": [(0, 8)]})
    play_diagram("man", {}, [((-12, 5), "man"), ((-1.4, 2), "rush"), ((1.4, 2), "rush"), ((12, 5), "man"), ((-4.5, 5), "man"), ((4.5, 5), "man"), ((0, 12), "deep")])
    play_diagram("zone", {}, [((-12, 8), "deep"), ((-1.4, 2), "rush"), ((1.4, 2), "rush"), ((12, 8), "deep"), ((-4.5, 5), "deep"), ((4.5, 5), "deep"), ((0, 13), "deep")])
    play_diagram("blitz", {}, [((-12, 5), "man"), ((-1.4, 2), "rush"), ((1.4, 2), "rush"), ((12, 5), "man"), ((-4.5, 4), "rush"), ((4.5, 4), "rush"), ((0, 12), "deep")])
    print("Team logos")
    teams = json.loads((ROOT / "pipeline" / "teams.json").read_text())["teams"]
    for t in teams:
        team_logo(t)


def only_new():
    """Just the badge art and the settings/invite icons: generate.py badges"""
    icon("gear", ic_gear)
    icon("invite", ic_invite)
    for key, (col, dark, emblem) in BADGES.items():
        badge(key, col, dark, emblem)


if __name__ == "__main__":
    import sys
    if "badges" in sys.argv:
        only_new()
    else:
        main()
        only_new()
