"""Re-encode the Windows runner icon as standard 32-bit BMP-backed ICO frames.

Usage: python tools/repair_windows_icon.py
Requires: python -m pip install Pillow
"""
from pathlib import Path
from PIL import Image

ICON = Path(__file__).resolve().parents[1] / "windows/runner/resources/app_icon.ico"
SIZES = (16, 24, 32, 48, 64, 128, 256)


def main():
    with Image.open(ICON) as source:
        # Decode the largest available frame before rewriting the ICO directory.
        available = source.info.get("sizes", set())
        if available:
            source.size = max(available, key=lambda item: item[0] * item[1])
        image = source.convert("RGBA").copy()
    # Pillow writes Windows-compatible BITMAPINFOHEADER frames for small sizes.
    # 256px frames are PNG-compressed, as supported by modern Windows.
    image.save(ICON, format="ICO", sizes=[(n, n) for n in SIZES])
    with Image.open(ICON) as repaired:
        assert (16, 16) in repaired.info["sizes"]
        assert (256, 256) in repaired.info["sizes"]
    print(f"Rebuilt {ICON}")


if __name__ == "__main__":
    main()
