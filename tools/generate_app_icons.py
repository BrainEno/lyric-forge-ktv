"""Generate all platform app icons from assets/images/icon.png.

This is the single source of truth for launcher/app icons across Android, iOS,
macOS, Windows and Web. The Windows ICO is deliberately written with modern
BITMAPINFOHEADER (40-byte) DIB frames so MSVC rc.exe does not emit RC2176.

Usage:
    python -m pip install Pillow
    python tools/generate_app_icons.py
"""

from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/images/icon.png"

ANDROID = {
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
}

IOS = {
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png": 20,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png": 40,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png": 60,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png": 29,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png": 58,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png": 87,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png": 40,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png": 80,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png": 120,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png": 120,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png": 180,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png": 76,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png": 152,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png": 167,
    "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png": 1024,
}

MACOS = {
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": 16,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": 32,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": 64,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": 128,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": 256,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": 512,
    "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": 1024,
}

WEB = {
    "web/favicon.png": 32,
    "web/icons/Icon-192.png": 192,
    "web/icons/Icon-512.png": 512,
    "web/icons/Icon-maskable-192.png": 192,
    "web/icons/Icon-maskable-512.png": 512,
}

WINDOWS_ICON = ROOT / "windows/runner/resources/app_icon.ico"
WINDOWS_SIZES = (16, 24, 32, 48, 64, 128, 256)


def _write_png(source: Image.Image, relative_path: str, size: int, *, rgb: bool = True) -> None:
    target = ROOT / relative_path
    target.parent.mkdir(parents=True, exist_ok=True)
    image = source.resize((size, size), Image.Resampling.LANCZOS)
    if rgb:
        image = image.convert("RGB")
    image.save(target, format="PNG", optimize=True)


def _write_windows_ico(source: Image.Image) -> None:
    WINDOWS_ICON.parent.mkdir(parents=True, exist_ok=True)
    source.convert("RGBA").save(
        WINDOWS_ICON,
        format="ICO",
        sizes=[(size, size) for size in WINDOWS_SIZES],
        bitmap_format="bmp",
    )
    _verify_windows_ico(WINDOWS_ICON)


def _verify_windows_ico(path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 6:
        raise RuntimeError("Generated Windows ICO is truncated")

    reserved, icon_type, count = struct.unpack_from("<HHH", data, 0)
    if reserved != 0 or icon_type != 1 or count != len(WINDOWS_SIZES):
        raise RuntimeError(
            f"Unexpected ICO header: reserved={reserved}, type={icon_type}, count={count}"
        )

    found_sizes: set[int] = set()
    for index in range(count):
        entry_offset = 6 + index * 16
        width, height, _, _, _, bit_count, byte_count, image_offset = struct.unpack_from(
            "<BBBBHHII", data, entry_offset
        )
        width = 256 if width == 0 else width
        height = 256 if height == 0 else height
        if width != height:
            raise RuntimeError(f"ICO frame is not square: {width}x{height}")
        if image_offset + byte_count > len(data):
            raise RuntimeError(f"ICO frame {width}px exceeds file bounds")

        # RC2176 is emitted for legacy/old DIB resource formats. Pillow's
        # bitmap_format='bmp' should emit a modern 40-byte BITMAPINFOHEADER.
        dib_header_size = struct.unpack_from("<I", data, image_offset)[0]
        if dib_header_size != 40:
            raise RuntimeError(
                f"ICO frame {width}px uses unsupported DIB header size {dib_header_size}"
            )
        if bit_count not in (24, 32):
            raise RuntimeError(f"ICO frame {width}px has unsupported {bit_count}-bit pixels")
        found_sizes.add(width)

    missing = set(WINDOWS_SIZES) - found_sizes
    if missing:
        raise RuntimeError(f"Windows ICO is missing sizes: {sorted(missing)}")


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Source app icon not found: {SOURCE}")

    with Image.open(SOURCE) as opened:
        if opened.width != opened.height:
            raise RuntimeError(
                f"Source app icon must be square, got {opened.width}x{opened.height}"
            )
        source = opened.convert("RGBA").copy()

    for relative_path, size in ANDROID.items():
        _write_png(source, relative_path, size)

    # iOS App Store validation rejects app icons that contain an alpha channel,
    # even if every alpha value is fully opaque, so these are always RGB PNGs.
    for relative_path, size in IOS.items():
        _write_png(source, relative_path, size, rgb=True)

    for relative_path, size in MACOS.items():
        _write_png(source, relative_path, size)

    for relative_path, size in WEB.items():
        _write_png(source, relative_path, size)

    _write_windows_ico(source)

    print(f"Generated platform icons from {SOURCE}")
    print("Android: 5 launcher icons")
    print("iOS: 15 AppIcon images (RGB/no alpha)")
    print("macOS: 7 AppIcon images")
    print("Windows: 7-frame BMP-backed ICO (BITMAPINFOHEADER)")
    print("Web: favicon + 4 manifest icons")


if __name__ == "__main__":
    main()
