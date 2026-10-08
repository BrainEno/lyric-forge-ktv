"""Rebuild the Windows runner icon from the known-good macOS PNG artwork.

Usage: python tools/repair_windows_icon.py
Requires: python -m pip install Pillow
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
ICON = ROOT / "windows/runner/resources/app_icon.ico"
SIZES = (16, 24, 32, 48, 64, 128, 256)


def main():
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Source icon not found: {SOURCE}")

    ICON.parent.mkdir(parents=True, exist_ok=True)

    # Do not attempt to decode the existing Windows ICO. It may be malformed
    # (RC2176 / old DIB) and Pillow may reject it entirely. Instead, rebuild it
    # from the repository's known-good 1024px PNG artwork.
    with Image.open(SOURCE) as source:
        image = source.convert("RGBA").copy()

    image.save(
        ICON,
        format="ICO",
        sizes=[(size, size) for size in SIZES],
        bitmap_format="bmp",
    )

    # Verify that the replacement is a readable multi-resolution ICO.
    with Image.open(ICON) as repaired:
        available = repaired.info.get("sizes", set())
        required = {(16, 16), (32, 32), (48, 48), (256, 256)}
        missing = required - set(available)
        if missing:
            raise RuntimeError(f"Rebuilt ICO is missing required sizes: {sorted(missing)}")

    print(f"Rebuilt Windows icon from {SOURCE}")
    print(f"Wrote {ICON}")


if __name__ == "__main__":
    main()
