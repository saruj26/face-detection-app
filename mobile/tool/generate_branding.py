"""Generate the Frame Finder logo / launcher icon artwork with Pillow.

Outputs (assets/branding/):
  icon.png             1024² full icon (gradient tile + glasses) - legacy/iOS icon and in-app logo
  icon_foreground.png  1024² transparent glasses mark for the Android adaptive icon
  icon_background.png  1024² gradient for the Android adaptive icon
  icon_monochrome.png  1024² single-colour mark for Android 13+ themed icons

Usage (from mobile/):  python tool/generate_branding.py
Then:                  dart run flutter_launcher_icons
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "branding"
S = 1024
SS = 4  # supersampling
TOP = (61, 90, 254)  # #3D5AFE, the app's seed colour
BOTTOM = (124, 77, 255)  # #7C4DFF


def gradient(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)) + (255,))
    # soft diagonal sheen
    sheen = Image.new("L", (size, size), 0)
    ImageDraw.Draw(sheen).ellipse([-size * 0.3, -size * 0.6, size * 0.9, size * 0.45], fill=55)
    sheen = sheen.filter(ImageFilter.GaussianBlur(size // 10))
    white = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    white.putalpha(sheen)
    return Image.alpha_composite(img, white)


def glasses_mark(scale: float, color=(255, 255, 255, 255)) -> Image.Image:
    """White eyeglasses with a small sparkle, centred, occupying `scale` of the width."""
    n = S * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = n * scale
    cx, cy = n / 2, n / 2 + n * 0.03
    lens_r = w * 0.2
    gap = w * 0.09
    stroke = int(w * 0.055)
    lx, rx = cx - gap / 2 - lens_r, cx + gap / 2 + lens_r
    for x in (lx, rx):
        # rounded-square lenses with a faint fill
        box = [x - lens_r, cy - lens_r * 0.82, x + lens_r, cy + lens_r * 0.82]
        d.rounded_rectangle(box, radius=lens_r * 0.55, fill=color[:3] + (46,), outline=color, width=stroke)
    # bridge
    d.arc([cx - gap * 0.9, cy - lens_r * 0.75, cx + gap * 0.9, cy + lens_r * 0.35], 200, 340, fill=color, width=stroke)
    # temples / end pieces
    for x0, x1 in ((lx - lens_r - w * 0.07, lx - lens_r + stroke * 0.3), (rx + lens_r - stroke * 0.3, rx + lens_r + w * 0.07)):
        y = cy - lens_r * 0.55
        d.rounded_rectangle([x0, y - stroke / 2, x1, y + stroke / 2], radius=stroke / 2, fill=color)
    # sparkle (four-point star) above the right lens: "smart" detection
    sx, sy, r = rx + lens_r * 0.85, cy - lens_r * 1.45, w * 0.075
    star = [(sx, sy - r), (sx + r * 0.28, sy - r * 0.28), (sx + r, sy), (sx + r * 0.28, sy + r * 0.28),
            (sx, sy + r), (sx - r * 0.28, sy + r * 0.28), (sx - r, sy), (sx - r * 0.28, sy - r * 0.28)]
    d.polygon(star, fill=color)
    return img.resize((S, S), Image.LANCZOS)


def rounded_tile(img: Image.Image, radius_frac=0.225) -> Image.Image:
    mask = Image.new("L", (S * SS, S * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S * SS - 1, S * SS - 1], radius=S * SS * radius_frac, fill=255)
    out = img.copy()
    out.putalpha(mask.resize((S, S), Image.LANCZOS))
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    bg = gradient(S)
    bg.save(OUT / "icon_background.png")
    # Adaptive icons crop to a circle/squircle: keep the mark inside the safe zone.
    glasses_mark(0.62).save(OUT / "icon_foreground.png")
    glasses_mark(0.62, color=(255, 255, 255, 255)).save(OUT / "icon_monochrome.png")
    full = Image.alpha_composite(bg, glasses_mark(0.78))
    full.save(OUT / "icon.png")  # square: launchers apply their own mask
    rounded_tile(full).save(OUT / "logo.png")  # in-app logo with rounded corners
    print(f"wrote branding to {OUT}")


if __name__ == "__main__":
    main()
