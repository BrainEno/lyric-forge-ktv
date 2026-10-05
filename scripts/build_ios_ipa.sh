#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="unsigned"
EXPORT_METHOD="development"
EXPORT_OPTIONS_PLIST=""
BUILD_NAME=""
BUILD_NUMBER=""
OUTPUT_DIR="$PROJECT_ROOT/release/ios"
FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || true)}"

usage() {
  cat <<'EOF'
构建用于 iOS 实机 sideload 的 IPA。

用法：
  scripts/build_ios_ipa.sh [选项]

选项：
  --mode unsigned|signed       构建模式，默认 unsigned
  --export-method METHOD       signed 模式的导出方式，默认 development
                               可用值由当前 Flutter/Xcode 决定，常用：
                               development、ad-hoc、app-store、enterprise
  --export-options-plist PATH  signed 模式使用自定义 ExportOptions.plist
  --build-name VERSION         覆盖 pubspec.yaml 的版本名，例如 1.0.1
  --build-number NUMBER        覆盖 pubspec.yaml 的构建号，例如 2026092201
  --output-dir PATH            IPA 输出目录，默认 release/ios
  --flutter PATH               Flutter 可执行文件路径
  -h, --help                   显示帮助

说明：
  unsigned 产物供 AltStore、SideStore、Sideloadly 等工具重新签名后安装。
  signed 需要本机已配置 Apple 开发证书、Team 和 provisioning profile。
EOF
}

die() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || die "--mode 缺少参数"
      MODE="$2"
      shift 2
      ;;
    --export-method)
      [[ $# -ge 2 ]] || die "--export-method 缺少参数"
      EXPORT_METHOD="$2"
      shift 2
      ;;
    --export-options-plist)
      [[ $# -ge 2 ]] || die "--export-options-plist 缺少参数"
      EXPORT_OPTIONS_PLIST="$2"
      shift 2
      ;;
    --build-name)
      [[ $# -ge 2 ]] || die "--build-name 缺少参数"
      BUILD_NAME="$2"
      shift 2
      ;;
    --build-number)
      [[ $# -ge 2 ]] || die "--build-number 缺少参数"
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir 缺少参数"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --flutter)
      [[ $# -ge 2 ]] || die "--flutter 缺少参数"
      FLUTTER_BIN="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数：$1"
      ;;
  esac
done

[[ "$MODE" == "unsigned" || "$MODE" == "signed" ]] || \
  die "--mode 只接受 unsigned 或 signed"
[[ "$(uname -s)" == "Darwin" ]] || die "iOS IPA 只能在 macOS 上构建"
[[ -n "$FLUTTER_BIN" && -x "$FLUTTER_BIN" ]] || \
  die "找不到 Flutter；请设置 FLUTTER_BIN 或使用 --flutter"
command -v xcodebuild >/dev/null || die "找不到 Xcode 命令行工具"
command -v /usr/libexec/PlistBuddy >/dev/null || die "找不到 PlistBuddy"
command -v zip >/dev/null || die "找不到 zip"

if [[ -n "$EXPORT_OPTIONS_PLIST" ]]; then
  [[ "$MODE" == "signed" ]] || \
    die "--export-options-plist 只能与 --mode signed 一起使用"
  [[ -f "$EXPORT_OPTIONS_PLIST" ]] || \
    die "ExportOptions.plist 不存在：$EXPORT_OPTIONS_PLIST"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

FLUTTER_ARGS=(--release)
if [[ -n "$BUILD_NAME" ]]; then
  FLUTTER_ARGS+=(--build-name "$BUILD_NAME")
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  FLUTTER_ARGS+=(--build-number "$BUILD_NUMBER")
fi

cd "$PROJECT_ROOT"

if [[ "$MODE" == "unsigned" ]]; then
  "$FLUTTER_BIN" build ios "${FLUTTER_ARGS[@]}" --no-codesign

  APP_PATH="$PROJECT_ROOT/build/ios/iphoneos/Runner.app"
  [[ -d "$APP_PATH" ]] || die "构建完成但未找到 Runner.app：$APP_PATH"

  INFO_PLIST="$APP_PATH/Info.plist"
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
  NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
  SAFE_VERSION="${VERSION//[^A-Za-z0-9._-]/_}"
  SAFE_NUMBER="${NUMBER//[^A-Za-z0-9._-]/_}"
  IPA_PATH="$OUTPUT_DIR/bookstore_management_system-${SAFE_VERSION}+${SAFE_NUMBER}-unsigned.ipa"

  STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bookstore-ios-ipa.XXXXXX")"
  trap 'rm -rf "$STAGING_DIR"' EXIT
  mkdir -p "$STAGING_DIR/Payload"
  /usr/bin/ditto "$APP_PATH" "$STAGING_DIR/Payload/Runner.app"
  (
    cd "$STAGING_DIR"
    COPYFILE_DISABLE=1 /usr/bin/zip -qry -y packaged.ipa Payload
  )
  /bin/mv -f "$STAGING_DIR/packaged.ipa" "$IPA_PATH"
else
  SIGNED_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bookstore-ios-signed.XXXXXX")"
  trap 'rm -rf "$SIGNED_TEMP_DIR"' EXIT
  SIGNED_BUILD_MARKER="$SIGNED_TEMP_DIR/build-started"
  touch "$SIGNED_BUILD_MARKER"

  if [[ -n "$EXPORT_OPTIONS_PLIST" ]]; then
    "$FLUTTER_BIN" build ipa "${FLUTTER_ARGS[@]}" \
      --export-options-plist "$EXPORT_OPTIONS_PLIST"
  else
    "$FLUTTER_BIN" build ipa "${FLUTTER_ARGS[@]}" \
      --export-method "$EXPORT_METHOD"
  fi

  IPA_SOURCE="$(find "$PROJECT_ROOT/build/ios/ipa" -maxdepth 1 -type f -name '*.ipa' \
    -newer "$SIGNED_BUILD_MARKER" -print | head -n 1)"
  [[ -n "$IPA_SOURCE" ]] || \
    die "构建完成但 build/ios/ipa 下没有本次新生成的 IPA"
  IPA_PATH="$OUTPUT_DIR/$(basename "$IPA_SOURCE")"
  /usr/bin/ditto "$IPA_SOURCE" "$IPA_PATH"

  INSPECT_DIR="$SIGNED_TEMP_DIR/inspect"
  mkdir -p "$INSPECT_DIR"
  /usr/bin/ditto -x -k "$IPA_PATH" "$INSPECT_DIR"
  INFO_PLIST="$INSPECT_DIR/Payload/Runner.app/Info.plist"
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
  NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
fi

[[ -s "$IPA_PATH" ]] || die "IPA 文件为空：$IPA_PATH"
/usr/bin/unzip -tq "$IPA_PATH" >/dev/null

CHECKSUM="$(/usr/bin/shasum -a 256 "$IPA_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$CHECKSUM" "$(basename "$IPA_PATH")" >"$IPA_PATH.sha256"

printf '\n构建完成\n'
printf '  模式：%s\n' "$MODE"
printf '  Bundle ID：%s\n' "$BUNDLE_ID"
printf '  版本：%s (%s)\n' "$VERSION" "$NUMBER"
printf '  IPA：%s\n' "$IPA_PATH"
printf '  SHA-256：%s\n' "$CHECKSUM"
