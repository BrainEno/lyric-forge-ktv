from pathlib import Path
import runpy

# Reuse the already-reviewed UI/platform wiring, then replace the incompatible
# audio_io dependency/backend with record + flutter_soloud.
runpy.run_path("tool/apply_ktv_microphone_slice.py", run_name="__main__")


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text()
    if old not in text:
        raise SystemExit(f"Expected v2 text not found in {path}: {old[:100]!r}")
    target.write_text(text.replace(old, new, 1))


replace_once(
    "pubspec.yaml",
    "  audio_io: ^0.6.1\n  permission_handler: ^12.0.3\n",
    "  record: 6.2.1\n  flutter_soloud: 5.1.2\n",
)

replace_once(
    "lib/core/services/service_locator.dart",
    "import '../../features/player/data/services/audio_io_ktv_microphone_service.dart';\n",
    "import '../../features/player/data/services/record_soloud_ktv_microphone_service.dart';\n",
)
replace_once(
    "lib/core/services/service_locator.dart",
    "    ktvMicrophoneService = AudioIoKtvMicrophoneService();\n",
    "    ktvMicrophoneService = RecordSoloudKtvMicrophoneService();\n",
)

# permission_handler-specific compile definitions are unnecessary because
# record owns its permission request. Keep only the actual platform usage
# descriptions/entitlements added by the base script.
macro_block = (
    "    target.build_configurations.each do |config|\n"
    "      definitions = config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] || ['$(inherited)']\n"
    "      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = definitions + ['PERMISSION_MICROPHONE=1']\n"
    "    end\n"
)
for podfile in ("ios/Podfile", "macos/Podfile"):
    target = Path(podfile)
    text = target.read_text()
    if macro_block not in text:
        raise SystemExit(f"Expected permission macro block not found in {podfile}")
    target.write_text(text.replace(macro_block, "", 1))
