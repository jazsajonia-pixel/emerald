"""Generates Sapphire's Android icons from the same facet geometry as
SapphireMarkPainter (lib/app/theme.dart). Run: python3 tool/make_icons.py"""
from PIL import Image, ImageDraw, ImageFilter
import os

FACETS = [
    ([(.28, .16), (.06, .40), (.30, .40)], "#6E9CFF"),
    ([(.28, .16), (.50, .16), (.30, .40)], "#A9CBFF"),
    ([(.50, .16), (.30, .40), (.70, .40)], "#D3E6FF"),
    ([(.50, .16), (.72, .16), (.70, .40)], "#7FA9FF"),
    ([(.72, .16), (.94, .40), (.70, .40)], "#3D6CF0"),
    ([(.06, .40), (.30, .40), (.50, .90)], "#2F62E6"),
    ([(.30, .40), (.70, .40), (.50, .90)], "#1D46BE"),
    ([(.70, .40), (.94, .40), (.50, .90)], "#12318E"),
]
OUTLINE = [(.28, .16), (.72, .16), (.94, .40), (.50, .90), (.06, .40)]
BG_TOP, BG_BOTTOM = (0x14, 0x26, 0x5C), (0x05, 0x09, 0x18)
RES = "android/app/src/main/res"


def vec_paths(x0, y0, s):
    def pd(pts):
        return "M" + " L".join(f"{x0 + x * s:.2f},{y0 + y * s:.2f}" for x, y in pts) + " Z"
    out = []
    for pts, c in FACETS:
        out.append(f'    <path android:fillColor="{c}" android:pathData="{pd(pts)}" />')
    for pts, _ in FACETS:
        out.append(f'    <path android:fillColor="#00000000" android:strokeColor="#17389A" '
                   f'android:strokeWidth="{s*0.012:.2f}" android:pathData="{pd(pts)}" />')
    out.append(f'    <path android:fillColor="#00000000" android:strokeColor="#E3EEFF" '
               f'android:strokeWidth="{s*0.03:.2f}" android:strokeLineJoin="round" android:pathData="{pd(OUTLINE)}" />')
    cx, cy, r = x0 + .84 * s, y0 + .13 * s, .09 * s
    out.append(f'    <path android:fillColor="#F2F7FF" android:pathData="M{cx:.2f},{cy-r:.2f} Q{cx:.2f},{cy:.2f} {cx+r:.2f},{cy:.2f} '
               f'Q{cx:.2f},{cy:.2f} {cx:.2f},{cy+r:.2f} Q{cx:.2f},{cy:.2f} {cx-r:.2f},{cy:.2f} Q{cx:.2f},{cy:.2f} {cx:.2f},{cy-r:.2f} Z" />')
    return "\n".join(out)


def write_vectors():
    # Adaptive foreground: gem inside the 66dp safe zone of a 108dp canvas.
    s = 50.0
    x0, y0 = 54 - s / 2, 54 - s * 0.53
    head = ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="108" android:viewportHeight="108">\n')
    open(f"{RES}/drawable/ic_sapphire_mark.xml", "w").write(head + vec_paths(x0, y0, s) + "\n</vector>\n")
    # Legacy (API 21-25) icon: rounded navy tile + gem.
    s = 64.0
    x0, y0 = 54 - s / 2, 54 - s * 0.53
    tile = '    <path android:fillColor="#0B1638" android:pathData="M30,6 L78,6 Q102,6 102,30 L102,78 Q102,102 78,102 L30,102 Q6,102 6,78 L6,30 Q6,6 30,6 Z" />\n'
    open(f"{RES}/mipmap-anydpi-v21/ic_launcher.xml", "w").write(head + tile + vec_paths(x0, y0, s) + "\n</vector>\n")


def hexc(c):
    c = c.lstrip("#")
    if len(c) == 8:
        return (int(c[2:4], 16), int(c[4:6], 16), int(c[6:8], 16), int(c[0:2], 16))
    return (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), 255)


def render(size, gem_scale=0.62, rounded=True, glow=True):
    k = 4
    S = size * k
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Vertical gradient background.
    bg = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(bg)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)) + (255,))
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    if rounded:
        md.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.23), fill=255)
    else:
        md.rectangle([0, 0, S, S], fill=255)
    img.paste(bg, (0, 0), mask)
    s = S * gem_scale
    x0, y0 = S / 2 - s / 2, S / 2 - s * 0.53
    P = lambda pts: [(x0 + x * s, y0 + y * s) for x, y in pts]
    if glow:
        g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(g).polygon(P(OUTLINE), fill=(60, 110, 255, 150))
        g = g.filter(ImageFilter.GaussianBlur(S * 0.06))
        img = Image.alpha_composite(img, g)
    d = ImageDraw.Draw(img)
    for pts, c in FACETS:
        d.polygon(P(pts), fill=hexc(c))
    for pts, _ in FACETS:
        d.line(P(pts) + [P(pts)[0]], fill=hexc("#17389A"), width=max(1, int(s * 0.012)), joint="curve")
    d.line(P(OUTLINE) + [P(OUTLINE)[0]], fill=hexc("#E3EEFF"), width=max(2, int(s * 0.03)), joint="curve")
    cx, cy, r = x0 + .84 * s, y0 + .13 * s, .09 * s
    import math
    star = []
    for i in range(64):
        a = i / 64 * 2 * math.pi
        # astroid-like 4-point sparkle
        star.append((cx + r * math.cos(a) ** 3, cy + r * math.sin(a) ** 3))
    d.polygon(star, fill=hexc("#F2F7FF"))
    return img.resize((size, size), Image.LANCZOS)


def main():
    write_vectors()
    for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        render(px).save(f"{RES}/mipmap-{folder}/ic_launcher.png")
    os.makedirs("docs/assets", exist_ok=True)
    render(512).save("docs/assets/sapphire-icon-512.png")


if __name__ == "__main__":
    main()
