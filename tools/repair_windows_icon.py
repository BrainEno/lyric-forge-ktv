"""Rebuild the Windows runner icon from assets/images/icon.png.

Usage: python tools/repair_windows_icon.py
Requires: python -m pip install Pillow
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/images/icon.png"
ICON = ROOT / "windows/runner/resources/app_icon.ico"
SIZES = (16, 24, 32, 48, 64, 128, 256)


def main():
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Source icon not found: {SOURCE}")

    ICON.parent.mkdir(parents=True, exist_ok=True)

    with Image.open(SOURCE) as source:
        image = source.convert("RGBA").copy()

    image.save(
        ICON,
        format="ICO",
        sizes=[(size, size) for size in SIZES],
        bitmap_format="bmp",
    )

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
