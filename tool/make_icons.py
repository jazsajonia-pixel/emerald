"""Generate Android launcher assets from Jazz's supplied Sapphire mark.

Input: assets/branding/sapphire-mark.png (preserved original RGBA image)
Run:   python3 tool/make_icons.py
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/sapphire-mark.png"
RES = ROOT / "android/app/src/main/res"
BACKGROUND = (0x0B, 0x16, 0x38, 255)
DENSITIES = {
    "mdpi": 1,
    "hdpi": 1.5,
    "xhdpi": 2,
    "xxhdpi": 3,
    "xxxhdpi": 4,
}


def place_mark(size: int, safe_fraction: float, *, monochrome: bool = False) -> Image.Image:
    source = Image.open(SOURCE).convert("RGBA")
    source.thumbnail((round(size * safe_fraction),) * 2, Image.Resampling.LANCZOS)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    layer.alpha_composite(source, ((size - source.width) // 2, (size - source.height) // 2))
    if monochrome:
        alpha = layer.getchannel("A")
        mask = alpha.point(lambda value: 0 if value < 10 else value)
        layer = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        layer.putalpha(mask)
    return layer


def render_legacy(size: int) -> Image.Image:
    icon = Image.new("RGBA", (size, size), BACKGROUND)
    mark = place_mark(size, 0.76)
    icon.alpha_composite(mark)
    return icon


def write_adaptive_xml() -> None:
    path = RES / "mipmap-anydpi-v26/ic_launcher.xml"
    path.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/sapphire_icon_background" />\n'
        '    <foreground android:drawable="@drawable/ic_sapphire_mark_foreground" />\n'
        '    <monochrome android:drawable="@drawable/ic_sapphire_mark_monochrome" />\n'
        '</adaptive-icon>\n',
        encoding="utf-8",
    )


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Missing supplied logo source: {SOURCE}")

    # Adaptive-icon foreground is a 108dp canvas. Keep the complete supplied
    # artwork within Android's central 66dp safe area to survive launcher masks.
    for density, factor in DENSITIES.items():
        px = round(108 * factor)
        folder = RES / f"drawable-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        place_mark(px, 66 / 108).save(folder / "ic_sapphire_mark_foreground.png")
        place_mark(px, 66 / 108, monochrome=True).save(
            folder / "ic_sapphire_mark_monochrome.png"
        )

        mipmap = RES / f"mipmap-{density}"
        mipmap.mkdir(parents=True, exist_ok=True)
        render_legacy(round(48 * factor)).save(mipmap / "ic_launcher.png")

    write_adaptive_xml()

    # API 21–25 use the density-specific legacy PNGs; an anydpi vector would
    # otherwise shadow them. Keep the separate vector used by the splash screen.
    legacy_override = RES / "mipmap-anydpi-v21/ic_launcher.xml"
    if legacy_override.exists():
        legacy_override.unlink()

    store = Image.new("RGBA", (512, 512), BACKGROUND)
    store.alpha_composite(place_mark(512, 0.80))
    (ROOT / "docs/assets").mkdir(parents=True, exist_ok=True)
    store.save(ROOT / "docs/assets/sapphire-icon-512.png")


if __name__ == "__main__":
    main()
