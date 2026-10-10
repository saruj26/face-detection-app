"""Procedurally generate the demo eyeglass assets.

Why generated instead of downloaded: product photos found through image search
are copyrighted and are not front-facing transparent cut-outs with known lens
positions. Drawing the frames in code gives us (a) assets we are free to ship,
(b) true alpha transparency, and (c) exact lens geometry, from which the
fitting metadata stored in PostgreSQL is computed instead of guessed.

For every frame this writes:
  static/glasses/<slug>_overlay.png    transparent front view used for try-on
  static/glasses/<slug>_catalogue.png  product image for the catalogue
and the catalogue data file `static/glasses/catalogue.json`, which is the input
of scripts/seed_glasses.py and of the Flutter offline fallback.

Usage (from backend/):
    python -m scripts.generate_glasses_assets [--flutter-assets ../mobile/assets/glasses]
"""
from __future__ import annotations

import argparse
import json
import math
import random
import shutil
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

BACKEND_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = BACKEND_DIR / "static" / "glasses"

SS = 4  # supersampling factor for anti-aliasing
W, H = 1000, 440  # overlay canvas size (final pixels)
CY = 205  # vertical centre of the lenses
BRIDGE_HALF = 44  # half of the nose-bridge gap between the lenses (px)
# Average adult interpupillary distance / average total frame width
# (~63 mm / ~140 mm). Used to size the frame relative to the detected eyes.
PD_TO_FRAME_WIDTH = 0.45

RGBA = tuple[int, int, int, int]


@dataclass
class Style:
    slug: str
    name: str
    category: str
    price: float
    description: str
    shape: str  # lens outline generator name
    a: float  # lens half width
    b: float  # lens half height
    rim: float  # rim thickness (px, final scale)
    rim_color: RGBA
    lens_tint: RGBA
    material: str = "acetate"  # acetate | metal | tortoise | rimless | browline | semi
    bridge: str = "keyhole"  # keyhole | arc | double
    eye_y_offset: float = 0.0  # where the pupils sit relative to lens centre (px)
    params: dict = field(default_factory=dict)


STYLES: list[Style] = [
    Style("aviator-classic", "Aviator Classic", "Aviator", 129.00,
          "Gold wire teardrop aviator with double bridge and gradient grey lenses.",
          "teardrop", 128, 108, 7, (196, 158, 72, 255), (60, 70, 80, 95),
          material="metal", bridge="double", eye_y_offset=-22),
    Style("wayfarer-black", "Wayfarer Black", "Wayfarer", 99.00,
          "Bold black acetate trapezoid frame with a strong brow line.",
          "trapezoid", 125, 82, 24, (22, 22, 26, 255), (40, 45, 55, 55),
          bridge="keyhole", eye_y_offset=-6),
    Style("round-wire-gold", "Round Wire Gold", "Round", 89.00,
          "Thin gold round frame inspired by vintage 1960s eyewear.",
          "superellipse", 104, 104, 6, (205, 168, 80, 255), (200, 210, 220, 28),
          material="metal", bridge="arc", params={"n": 2.0}),
    Style("cat-eye-tortoise", "Cat-Eye Tortoise", "Cat-Eye", 115.00,
          "Upswept tortoiseshell acetate cat-eye with a feminine silhouette.",
          "cateye", 118, 76, 20, (110, 62, 28, 255), (180, 150, 130, 30),
          material="tortoise", bridge="keyhole", eye_y_offset=-4),
    Style("browline-classic", "Browline Classic", "Browline", 109.00,
          "Black acetate brow bar over a thin silver lower rim.",
          "superellipse", 120, 84, 22, (24, 24, 28, 255), (210, 215, 225, 25),
          material="browline", bridge="arc", params={"n": 3.0, "lower": (175, 178, 186, 255)}),
    Style("slim-rectangle", "Slim Rectangle", "Rectangle", 79.00,
          "Lightweight matte black rectangular frame for everyday wear.",
          "superellipse", 124, 64, 11, (35, 35, 40, 255), (210, 220, 230, 25),
          bridge="arc", params={"n": 6.0}),
    Style("oversized-crystal", "Oversized Square Crystal", "Square", 119.00,
          "Large square frame in transparent crystal acetate.",
          "superellipse", 140, 112, 22, (168, 186, 204, 200), (220, 230, 240, 22),
          bridge="keyhole", eye_y_offset=-12, params={"n": 4.5}),
    Style("rimless-titanium", "Rimless Titanium", "Rimless", 149.00,
          "Minimal rimless lenses with titanium bridge and hinges.",
          "superellipse", 118, 74, 3, (170, 175, 185, 120), (200, 215, 230, 34),
          material="rimless", bridge="arc", params={"n": 3.2}),
    Style("hexagon-silver", "Hexagon Silver", "Geometric", 95.00,
          "Six-sided thin silver metal frame with a modern geometric look.",
          "hexagon", 116, 96, 7, (178, 182, 190, 255), (200, 210, 220, 28),
          material="metal", bridge="arc"),
    Style("semi-rimless-navy", "Semi-Rimless Navy", "Semi-Rimless", 105.00,
          "Navy upper rim with a nearly invisible lower nylon line.",
          "superellipse", 122, 72, 16, (28, 42, 82, 255), (210, 220, 230, 25),
          material="semi", bridge="arc", params={"n": 3.5}),
]


# --------------------------------------------------------------------------
# Lens outline generators. Return points relative to the lens centre for the
# LEFT lens of the image (the nose is towards +x). The right lens is mirrored.
# --------------------------------------------------------------------------
def _superellipse(a: float, b: float, n: float, steps: int = 360) -> list[tuple[float, float]]:
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = a * math.copysign(abs(c) ** (2 / n), c)
        y = b * math.copysign(abs(s) ** (2 / n), s)
        pts.append((x, y))
    return pts


def lens_outline(style: Style) -> list[tuple[float, float]]:
    a, b = style.a, style.b
    if style.shape == "superellipse":
        return _superellipse(a, b, style.params.get("n", 2.0))
    if style.shape == "trapezoid":
        pts = []
        for x, y in _superellipse(a, b, 4.0):
            # wider at the top, narrower at the bottom; top edge slightly raised
            # towards the temple
            k = 1.0 + 0.10 * (-y / b)
            pts.append((x * k, y - 0.08 * b * (-x / a) * (y < 0)))
        return pts
    if style.shape == "cateye":
        pts = []
        for x, y in _superellipse(a, b, 2.6):
            lift = 0.0
            if y < 0:
                y *= 0.88  # flatter top
                if x < 0:  # upper outer corner swept up and out
                    k = (-x / a) ** 3 * (-y / b) ** 0.5
                    lift = 0.55 * b * k
                    x -= 0.10 * a * k
            narrow = 1.0 - 0.18 * max(0.0, y / b)  # narrower towards the cheek
            pts.append((x * narrow, y - lift))
        return pts
    if style.shape == "teardrop":
        pts = []
        for x, y in _superellipse(a, b, 2.3):
            if y > 0:  # lower half drops towards the nose
                y *= 1.0 + 0.18 * (x / a + 1) / 2
                x += 0.10 * a * (y / b)
            else:  # flatter top
                y *= 0.80
            pts.append((x, y))
        return pts
    if style.shape == "hexagon":
        return [(a * math.cos(math.radians(d)), b * 0.92 * math.sin(math.radians(d)))
                for d in (0, 60, 120, 180, 240, 300)]
    raise ValueError(style.shape)


def _top_arc(pts):
    """Contiguous part of the outline from its leftmost to rightmost point
    passing over the top (negative y)."""
    n = len(pts)
    i0 = min(range(n), key=lambda i: pts[i][0])
    i1 = max(range(n), key=lambda i: pts[i][0])
    for step in (1, -1):
        arc, i = [pts[i0]], i0
        while i != i1:
            i = (i + step) % n
            arc.append(pts[i])
        if sum(y for _, y in arc) < 0:
            return arc
    raise ValueError("no top arc")


def _place(pts, cx, cy, mirror):
    return [((cx + (-x if mirror else x)) * SS, (cy + y) * SS) for x, y in pts]


def _stroke(draw: ImageDraw.ImageDraw, pts, width: float, fill=255):
    draw.line(pts + [pts[0]], fill=fill, width=max(1, int(width * SS)), joint="curve")
    r = width * SS / 2
    for x, y in pts[:: max(1, len(pts) // 90)]:  # round out corners/joins
        draw.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def _tortoise_texture(size) -> Image.Image:
    rnd = random.Random(7)
    tex = Image.new("RGBA", size, (92, 50, 20, 255))
    d = ImageDraw.Draw(tex)
    for _ in range(900):
        x, y = rnd.uniform(0, size[0]), rnd.uniform(0, size[1])
        r = rnd.uniform(6, 34) * SS / 2
        tone = rnd.choice([(40, 20, 8, 255), (150, 92, 38, 255), (185, 125, 55, 255), (60, 30, 12, 255)])
        d.ellipse([x - r * 1.6, y - r, x + r * 1.6, y + r], fill=tone)
    return tex.filter(ImageFilter.GaussianBlur(5 * SS))


def _metal_fill(size, color: RGBA) -> Image.Image:
    """Vertical highlight gradient that reads as polished metal."""
    w, h = size
    grad = Image.new("RGBA", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        shine = 1.25 - 0.55 * abs(t - 0.35) * 2
        grad.putpixel((0, y), tuple(min(255, int(c * shine)) for c in color[:3]) + (color[3],))
    return grad.resize(size)


def render_overlay(style: Style) -> tuple[Image.Image, dict]:
    size = (W * SS, H * SS)
    lens_layer = Image.new("RGBA", size, (0, 0, 0, 0))
    rim_mask = Image.new("L", size, 0)
    lower_mask = Image.new("L", size, 0)  # thin lower rim (browline / semi)
    ld, md, lmd = ImageDraw.Draw(lens_layer), ImageDraw.Draw(rim_mask), ImageDraw.Draw(lower_mask)

    outline = lens_outline(style)
    lens_dx = max(x for x, _ in outline) + BRIDGE_HALF + style.rim * 0.5
    cx_l, cx_r = W / 2 - lens_dx, W / 2 + lens_dx
    lens_polys = [_place(outline, cx_l, CY, False), _place(outline, cx_r, CY, True)]

    top = _top_arc(outline)
    top_polys = [_place(top, cx_l, CY, False), _place(top, cx_r, CY, True)]
    for poly, top_poly in zip(lens_polys, top_polys):
        if style.material == "metal" and style.slug == "aviator-classic":
            # gradient tint: darker at the top, like real gradient sunglass lenses
            m = Image.new("L", size, 0)
            ImageDraw.Draw(m).polygon(poly, fill=255)
            top = min(p[1] for p in poly)
            bot = max(p[1] for p in poly)
            grad = Image.new("L", (1, size[1]))
            for y in range(size[1]):
                t = min(1, max(0, (y - top) / max(1, bot - top)))
                grad.putpixel((0, y), int(style.lens_tint[3] * (1.5 - 0.9 * t)))
            alpha = ImageChops.multiply(m, grad.resize(size))
            tint = Image.new("RGBA", size, style.lens_tint[:3] + (0,))
            tint.putalpha(alpha)
            lens_layer = Image.alpha_composite(lens_layer, tint)
            ld = ImageDraw.Draw(lens_layer)
        else:
            ld.polygon(poly, fill=style.lens_tint)

        if style.material in ("browline", "semi"):
            # thick upper rim follows the top part of the lens only
            width = style.rim * (1.25 if style.material == "browline" else 1.0)
            md.line(top_poly, fill=255, width=int(width * SS), joint="curve")
            r = width * SS / 2
            for x, y in top_poly[:: max(1, len(top_poly) // 60)] + [top_poly[-1]]:
                md.ellipse([x - r, y - r, x + r, y + r], fill=255)
            if style.material == "browline":
                _stroke(lmd, poly, 4)
            else:
                _stroke(lmd, poly, 2)
        elif style.material == "rimless":
            _stroke(lmd, poly, style.rim)
        else:
            _stroke(md, poly, style.rim)

    # Bridge
    gap_l = cx_l + max(x for x, _ in outline) - style.rim * 0.3
    gap_r = cx_r - max(x for x, _ in outline) + style.rim * 0.3
    top_y = CY - style.b * (0.62 if style.material != "browline" else 0.78)
    bw = style.rim if style.material not in ("rimless", "metal") else max(5, style.rim)
    if style.bridge == "keyhole":
        bbox = [gap_l * SS, (top_y - 6) * SS, gap_r * SS, (top_y + 70) * SS]
        md.arc(bbox, 195, 345, fill=255, width=int(bw * 1.15 * SS))
        md.rectangle([gap_l * SS, (top_y - 8) * SS, gap_r * SS, (top_y + bw * 0.6) * SS], fill=255)
    elif style.bridge == "double":
        bbox = [gap_l * SS, (top_y + 10) * SS, gap_r * SS, (top_y + 80) * SS]
        md.arc(bbox, 200, 340, fill=255, width=int(bw * SS))
        y2 = CY - style.b * 0.80
        md.line([((gap_l - 40) * SS, y2 * SS), ((gap_r + 40) * SS, y2 * SS)], fill=255, width=int(bw * SS))
    else:  # arc
        bbox = [gap_l * SS, (top_y + 6) * SS, gap_r * SS, (top_y + 76) * SS]
        md.arc(bbox, 195, 345, fill=255, width=int(bw * SS))

    # End pieces / hinges where the temples attach
    x_outer_l = cx_l - max(abs(x) for x, _ in outline)
    x_outer_r = cx_r + max(abs(x) for x, _ in outline)
    hinge_y = CY - style.b * 0.55
    hl = 26 if style.material not in ("metal", "rimless") else 20
    hw = max(style.rim * 0.9, 9)
    for x0, x1 in ((x_outer_l - hl, x_outer_l + 6), (x_outer_r - 6, x_outer_r + hl)):
        md.rounded_rectangle([x0 * SS, (hinge_y - hw / 2) * SS, x1 * SS, (hinge_y + hw / 2) * SS],
                             radius=hw * SS / 2, fill=255)

    # Nose pads for metal / rimless frames
    pad_mask = Image.new("L", size, 0)
    if style.material in ("metal", "rimless", "semi", "browline"):
        pd = ImageDraw.Draw(pad_mask)
        for x in (gap_l - 6, gap_r + 6):
            pd.ellipse([(x - 9) * SS, (CY + 8) * SS, (x + 9) * SS, (CY + 36) * SS], fill=170)

    # Fill the masks with their material
    if style.material == "tortoise":
        rim_fill = _tortoise_texture(size)
    elif style.material in ("metal", "rimless"):
        rim_fill = _metal_fill(size, style.rim_color)
    else:
        rim_fill = Image.new("RGBA", size, style.rim_color)
        if style.rim_color[3] < 255:  # translucent crystal: keep its alpha
            rim_mask = ImageChops.multiply(rim_mask, Image.new("L", size, style.rim_color[3]))
    rim_layer = rim_fill.copy()
    rim_layer.putalpha(ImageChops.multiply(rim_mask, rim_fill.getchannel("A")))

    lower_color = style.params.get("lower", (190, 195, 205, 255))
    if style.material == "rimless":
        lower_color = (230, 238, 245, 140)  # polished lens edge
    if style.material == "semi":
        lower_color = (200, 205, 215, 110)  # nylon line
    lower_layer = _metal_fill(size, lower_color) if style.material == "browline" else Image.new("RGBA", size, lower_color)
    lower_layer.putalpha(ImageChops.multiply(lower_mask, Image.new("L", size, lower_color[3])))
    if style.material == "rimless":  # hinges and bridge in titanium
        rim_layer.putalpha(ImageChops.multiply(rim_mask, Image.new("L", size, 255)))

    pads = Image.new("RGBA", size, (235, 238, 242, 0))
    pads.putalpha(pad_mask)

    img = Image.new("RGBA", size, (0, 0, 0, 0))
    for layer in (lens_layer, pads, lower_layer, rim_layer):
        img = Image.alpha_composite(img, layer)

    # subtle specular highlight on each lens
    hl_layer = Image.new("RGBA", size, (255, 255, 255, 0))
    hd = ImageDraw.Draw(hl_layer)
    for cx in (cx_l, cx_r):
        hd.line([((cx - style.a * 0.55) * SS, (CY - style.b * 0.25) * SS),
                 ((cx - style.a * 0.25) * SS, (CY - style.b * 0.55) * SS)],
                fill=(255, 255, 255, 60), width=int(9 * SS))
    lens_union = Image.new("L", size, 0)
    top = _top_arc(outline)
    top_polys = [_place(top, cx_l, CY, False), _place(top, cx_r, CY, True)]
    for poly, top_poly in zip(lens_polys, top_polys):
        ImageDraw.Draw(lens_union).polygon(poly, fill=255)
    hl_layer.putalpha(ImageChops.multiply(hl_layer.getchannel("A"), lens_union))
    img = Image.alpha_composite(img, hl_layer)

    img = img.resize((W, H), Image.LANCZOS)

    # Fitting metadata derived from the exact geometry drawn above.
    bbox = img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    frame_left, _, frame_right, _ = bbox
    frame_width = frame_right - frame_left
    fit = {
        "image_width": W,
        "image_height": H,
        # Point of the PNG (normalised 0..1) placed at the midpoint between the eyes.
        "anchor_x": 0.5,
        "anchor_y": round((CY + style.eye_y_offset) / H, 4),
        # Fraction of the PNG width covered by the wearer's interpupillary distance.
        "eye_span_ratio": round(PD_TO_FRAME_WIDTH * frame_width / W, 4),
        "left_lens_center": [round(cx_l / W, 4), round(CY / H, 4)],
        "right_lens_center": [round(cx_r / W, 4), round(CY / H, 4)],
        "frame_bounds": [round(frame_left / W, 4), round(bbox[1] / H, 4),
                         round(frame_right / W, 4), round(bbox[3] / H, 4)],
        "default_scale": 1.0,
    }
    return img, fit


def render_catalogue(overlay: Image.Image) -> Image.Image:
    cw, ch = 900, 540
    bg = Image.new("RGBA", (cw, ch))
    for y in range(ch):  # soft studio gradient
        t = y / ch
        c = int(248 - 14 * t)
        ImageDraw.Draw(bg).line([(0, y), (cw, y)], fill=(c, c, min(255, c + 3), 255))
    bbox = overlay.getchannel("A").getbbox()
    item = overlay.crop(bbox)
    scale = min((cw * 0.84) / item.width, (ch * 0.6) / item.height)
    item = item.resize((int(item.width * scale), int(item.height * scale)), Image.LANCZOS)
    ox, oy = (cw - item.width) // 2, (ch - item.height) // 2 - 10
    shadow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    sh = Image.new("RGBA", item.size, (30, 30, 40, 0))
    sh.putalpha(item.getchannel("A").point(lambda v: int(v * 0.28)))
    shadow.paste(sh, (ox, oy + 26), sh)
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    bg = Image.alpha_composite(bg, shadow)
    bg.alpha_composite(item, (ox, oy))
    return bg.convert("RGB")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--flutter-assets", type=Path, help="also copy assets + catalogue.json here")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    catalogue = []
    for style in STYLES:
        overlay, fit = render_overlay(style)
        overlay.save(OUT_DIR / f"{style.slug}_overlay.png", optimize=True)
        render_catalogue(overlay).save(OUT_DIR / f"{style.slug}_catalogue.png", optimize=True)
        catalogue.append({
            "slug": style.slug,
            "name": style.name,
            "category": style.category,
            "description": style.description,
            "price": style.price,
            "currency": "USD",
            # Relative paths: resolved against ASSET_BASE_URL or the API's own
            # /static mount when served. Replace with object-storage URLs later.
            "catalogue_image_url": f"/static/glasses/{style.slug}_catalogue.png",
            "transparent_overlay_url": f"/static/glasses/{style.slug}_overlay.png",
            "fit_metadata": fit,
        })
        print(f"generated {style.slug}: eye_span_ratio={fit['eye_span_ratio']}")

    (OUT_DIR / "catalogue.json").write_text(json.dumps(catalogue, indent=2), encoding="utf-8")

    if args.flutter_assets:
        dest = args.flutter_assets
        dest.mkdir(parents=True, exist_ok=True)
        for f in OUT_DIR.iterdir():
            shutil.copy2(f, dest / f.name)
        print(f"copied assets to {dest}")


if __name__ == "__main__":
    main()
