#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IOS_DIR="$PROJECT_ROOT/ios"
WORKSPACE="$IOS_DIR/Runner.xcworkspace"
PODS_PROJECT="$IOS_DIR/Pods/Pods.xcodeproj"
PODS_DEBUG_CONFIG="$IOS_DIR/Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"
STATE_DIR="$IOS_DIR/.generated"
STATE_FILE="$STATE_DIR/ios_pods_state.sha256"

FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || true)}"
BUILD_MODE="debug"
BUILD_TARGET="device"
OPEN_WORKSPACE=false
PREPARE_ONLY=false
DOCTOR_ONLY=false
FORCE_REPAIR=false
RUN_DEVICE=false
DEVICE_ID=""
SELECTED_DEVICE_ID=""
SELECTED_DEVICE_NAME=""
SELECTED_DEVICE_KIND=""

usage() {
  cat <<'EOF'
Bookstore Management System iOS 构建自检 / 自愈 / 设备运行脚本。

用法：
  ./scripts/ios_build.sh [选项]

默认行为：
  1. 检查 macOS / Flutter / CocoaPods / Xcode 环境；
  2. 运行 flutter pub get；
  3. 检查 Pods、Flutter plugin symlink、Runner.xcworkspace；
  4. 仅在依赖变化或 Pods 不健康时运行 pod install；
  5. 执行 flutter build ios --debug --no-codesign；
  6. 若构建出现常见 CocoaPods module-not-found 错误，自动深度修复一次并重试。

设备运行：
  --run-device 会列出 Flutter 当前检测到的全部 iOS 运行设备（实体 iPhone + 已启动的 Simulator）。
  使用 ↑/↓ 移动，空格选中，Enter 确认后会立即执行 flutter run。
  如果使用 --device-id，则跳过交互选择，直接运行指定设备。

选项：
  --mode debug|profile|release  构建/运行模式，默认 debug
  --simulator                   构建 iOS Simulator，而不是 iphoneos
  --prepare-only                只准备依赖，不执行 flutter build
  --doctor                      只检查当前环境，不修改依赖或构建
  --repair                      构建前强制执行深度 Pods 修复
  --open                        成功后检查设备并打开 ios/Runner.xcworkspace
  --run-device                  交互选择 iOS 设备并运行 App
  --device-id ID                直接指定 Flutter/Xcode 设备 ID，跳过交互选择
  --flutter PATH                指定 Flutter 可执行文件
  -h, --help                    显示帮助

常用示例：
  ./scripts/ios_build.sh
  ./scripts/ios_build.sh --open
  ./scripts/ios_build.sh --run-device
  ./scripts/ios_build.sh --run-device --device-id 00008110-XXXXXXXXXXXX
  ./scripts/ios_build.sh --prepare-only --open
  ./scripts/ios_build.sh --doctor
  ./scripts/ios_repair.sh
EOF
}

die() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

info() {
  printf '[iOS] %s\n' "$*"
}

ok() {
  printf '[iOS] ✓ %s\n' "$*"
}

warn() {
  printf '[iOS] ! %s\n' "$*" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      [[ $# -ge 2 ]] || die "--mode 缺少参数"
      BUILD_MODE="$2"
      shift 2
      ;;
    --simulator)
      BUILD_TARGET="simulator"
      shift
      ;;
    --prepare-only)
      PREPARE_ONLY=true
      shift
      ;;
    --doctor)
      DOCTOR_ONLY=true
      PREPARE_ONLY=true
      shift
      ;;
    --repair)
      FORCE_REPAIR=true
      shift
      ;;
    --open)
      OPEN_WORKSPACE=true
      shift
      ;;
    --run-device|--run)
      RUN_DEVICE=true
      shift
      ;;
    --device-id)
      [[ $# -ge 2 ]] || die "--device-id 缺少参数"
      DEVICE_ID="$2"
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

[[ "$BUILD_MODE" == "debug" || "$BUILD_MODE" == "profile" || "$BUILD_MODE" == "release" ]] || \
  die "--mode 只接受 debug、profile 或 release"

[[ "$RUN_DEVICE" != "true" || "$PREPARE_ONLY" != "true" ]] || \
  die "--run-device 不能与 --prepare-only/--doctor 同时使用"

check_command() {
  local command_name="$1"
  local label="$2"
  if command -v "$command_name" >/dev/null 2>&1; then
    ok "$label"
    return 0
  fi
  warn "${label}：未找到 ${command_name}"
  return 1
}

pod_input_hash() {
  local files=("$PROJECT_ROOT/pubspec.lock" "$IOS_DIR/Podfile")
  if [[ -f "$IOS_DIR/Podfile.lock" ]]; then
    files+=("$IOS_DIR/Podfile.lock")
  fi
  /usr/bin/shasum -a 256 "${files[@]}" | /usr/bin/shasum -a 256 | awk '{print $1}'
}

plugin_symlinks_healthy() {
  [[ -d "$IOS_DIR/.symlinks/plugins" ]] || return 1
  [[ -f "$IOS_DIR/Podfile.lock" ]] || return 1

  local plugin_path
  while IFS= read -r plugin_path; do
    [[ -n "$plugin_path" ]] || continue
    [[ -e "$IOS_DIR/$plugin_path" ]] || return 1
  done < <(
    sed -n 's/^[[:space:]]*:path: "\(.symlinks\/plugins\/[^\"]*\)"/\1/p' "$IOS_DIR/Podfile.lock"
  )

  return 0
}

workspace_healthy() {
  [[ -d "$WORKSPACE" ]] || return 1
  [[ -f "$WORKSPACE/contents.xcworkspacedata" ]] || return 1
  grep -q 'Pods/Pods.xcodeproj' "$WORKSPACE/contents.xcworkspacedata" || return 1
  return 0
}

pods_healthy() {
  [[ -d "$PODS_PROJECT" ]] || return 1
  [[ -f "$PODS_DEBUG_CONFIG" ]] || return 1
  plugin_symlinks_healthy || return 1
  workspace_healthy || return 1
  return 0
}

state_matches() {
  [[ -f "$STATE_FILE" ]] || return 1
  local expected actual
  expected="$(cat "$STATE_FILE" 2>/dev/null || true)"
  actual="$(pod_input_hash)"
  [[ -n "$expected" && "$expected" == "$actual" ]]
}

write_state() {
  mkdir -p "$STATE_DIR"
  pod_input_hash >"$STATE_FILE"
}

run_pod_install() {
  local update_repo="${1:-false}"
  info "安装/同步 CocoaPods 依赖"
  if [[ "$update_repo" == "true" ]]; then
    (cd "$IOS_DIR" && pod install --repo-update)
  else
    if ! (cd "$IOS_DIR" && pod install); then
      warn "pod install 失败，升级为 pod install --repo-update 后重试"
      (cd "$IOS_DIR" && pod install --repo-update)
    fi
  fi

  pods_healthy || die "pod install 完成，但 Pods/plugin symlink/workspace 仍不完整"
  write_state
  ok "CocoaPods 与 Flutter plugins 已同步"
}

repair_ios_environment() {
  warn "执行 iOS 深度修复：清理 Flutter 构建缓存、Pods、plugin symlink 和 Runner DerivedData"
  cd "$PROJECT_ROOT"
  "$FLUTTER_BIN" clean
  rm -rf "$IOS_DIR/Pods" "$IOS_DIR/.symlinks" "$STATE_DIR"
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData/Runner-"* 2>/dev/null || true
  "$FLUTTER_BIN" pub get
  run_pod_install true
  ok "iOS 深度修复完成"
}

ios_run_devices() {
  if ! command -v python3 >/dev/null 2>&1; then
    warn "缺少 python3，无法可靠解析 flutter devices --machine"
    return 1
  fi

  "$FLUTTER_BIN" devices --machine 2>/dev/null | python3 -c '
import json
import sys

try:
    devices = json.load(sys.stdin)
except Exception:
    sys.exit(2)

for device in devices:
    platform = str(device.get("targetPlatform", ""))
    if not platform.startswith("ios"):
        continue

    device_id = str(device.get("id", "")).strip()
    if not device_id:
        continue

    name = str(device.get("name", "iOS device")).replace("\t", " ").replace("\n", " ")
    emulator = bool(device.get("emulator", False))
    kind = "Simulator" if emulator else "iPhone"
    print(f"{device_id}\t{name}\t{kind}")
'
}

print_device_help() {
  cat >&2 <<'EOF'

[iOS] Flutter 当前没有找到可运行的 iOS 设备。请确认：
  • 实体 iPhone：手机已解锁、信任此电脑、开启 Developer Mode，并在 Xcode > Window > Devices and Simulators 完成 Pair/Preparing；
  • Simulator：先打开 Xcode Simulator，等待模拟器启动完成；
  • 当前 Xcode 版本支持目标设备上的 iOS 版本。

诊断命令：
  flutter devices
  xcrun xctrace list devices
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -showdestinations
EOF
}

print_device_diagnostics() {
  printf '\n[iOS] Flutter devices:\n'
  "$FLUTTER_BIN" devices || true

  if command -v xcrun >/dev/null 2>&1; then
    printf '\n[iOS] Xcode devices:\n'
    xcrun xctrace list devices 2>/dev/null || true

    if xcrun devicectl help >/dev/null 2>&1; then
      printf '\n[iOS] CoreDevice devices:\n'
      xcrun devicectl list devices 2>/dev/null || true
    fi
  fi

  if workspace_healthy; then
    printf '\n[iOS] Runner destinations:\n'
    xcodebuild -workspace "$WORKSPACE" -scheme Runner -showdestinations 2>&1 || true
  fi
}

read_device_line() {
  local devices_file="$1"
  local index="$2"
  sed -n "$((index + 1))p" "$devices_file"
}

interactive_select_device() {
  local devices_file="$1"
  local count="$2"
  local cursor=0
  local selected=-1
  local first_render=true
  local menu_lines=0
  local key=""
  local key_tail=""
  local i line item_id item_name item_kind marker pointer
  local selected_line=""

  if [[ ! -t 0 || ! -t 1 ]]; then
    if [[ "$count" -eq 1 ]]; then
      selected=0
    else
      warn "当前不是交互式终端，无法显示设备选择菜单。请使用 --device-id 指定目标设备。"
      return 1
    fi
  else
    printf '\n'
    while true; do
      if [[ "$first_render" == "false" && "$menu_lines" -gt 0 ]]; then
        printf '\033[%dA\r' "$menu_lines"
      fi

      printf '\033[J'
      printf '[iOS] 请选择运行设备\n'
      printf '      ↑/↓ 移动   Space 选中   Enter 确认   q 取消\n\n'
      menu_lines=$((3 + count))

      i=0
      while [[ "$i" -lt "$count" ]]; do
        line="$(read_device_line "$devices_file" "$i")"
        IFS=$'\t' read -r item_id item_name item_kind <<<"$line"

        pointer=" "
        marker="[ ]"
        [[ "$i" -eq "$cursor" ]] && pointer=">"
        [[ "$i" -eq "$selected" ]] && marker="[x]"

        printf '  %s %s %-10s %s\n' "$pointer" "$marker" "$item_kind" "$item_name"
        i=$((i + 1))
      done

      first_render=false
      IFS= read -rsn1 key || true

      case "$key" in
        $'\x1b')
          key_tail=""
          IFS= read -rsn2 -t 1 key_tail || true
          case "$key_tail" in
            "[A")
              cursor=$((cursor - 1))
              [[ "$cursor" -lt 0 ]] && cursor=$((count - 1))
              ;;
            "[B")
              cursor=$((cursor + 1))
              [[ "$cursor" -ge "$count" ]] && cursor=0
              ;;
          esac
          ;;
        " ")
          selected="$cursor"
          ;;
        "")
          if [[ "$selected" -lt 0 ]]; then
            selected="$cursor"
          fi
          break
          ;;
        q|Q)
          printf '\n'
          warn "已取消设备选择"
          return 1
          ;;
      esac
    done
    printf '\n'
  fi

  selected_line="$(read_device_line "$devices_file" "$selected")"
  IFS=$'\t' read -r SELECTED_DEVICE_ID SELECTED_DEVICE_NAME SELECTED_DEVICE_KIND <<<"$selected_line"

  [[ -n "$SELECTED_DEVICE_ID" ]] || return 1
  [[ -n "$SELECTED_DEVICE_NAME" ]] || SELECTED_DEVICE_NAME="iOS device"
  [[ -n "$SELECTED_DEVICE_KIND" ]] || SELECTED_DEVICE_KIND="iOS"

  ok "已选择：${SELECTED_DEVICE_NAME} [${SELECTED_DEVICE_KIND}] (${SELECTED_DEVICE_ID})"
}

select_run_device() {
  local devices_file line count selected_id selected_name selected_kind
  devices_file="$(mktemp "${TMPDIR:-/tmp}/bookstore-ios-devices.XXXXXX")"

  if ! ios_run_devices >"$devices_file"; then
    rm -f "$devices_file"
    print_device_help
    return 1
  fi

  count="$(awk 'NF { count += 1 } END { print count + 0 }' "$devices_file")"
  if [[ "$count" -eq 0 ]]; then
    rm -f "$devices_file"
    print_device_help
    return 1
  fi

  if [[ -n "$DEVICE_ID" ]]; then
    line="$(awk -F '\t' -v wanted="$DEVICE_ID" '$1 == wanted { print; exit }' "$devices_file")"
    if [[ -z "$line" ]]; then
      warn "指定的设备 ${DEVICE_ID} 不在 Flutter 的 iOS 设备列表中"
      while IFS=$'\t' read -r selected_id selected_name selected_kind; do
        [[ -n "$selected_id" ]] || continue
        printf '  %-10s %-24s %s\n' "$selected_kind" "$selected_name" "$selected_id" >&2
      done <"$devices_file"
      rm -f "$devices_file"
      return 1
    fi

    IFS=$'\t' read -r SELECTED_DEVICE_ID SELECTED_DEVICE_NAME SELECTED_DEVICE_KIND <<<"$line"
    rm -f "$devices_file"
    ok "已指定：${SELECTED_DEVICE_NAME} [${SELECTED_DEVICE_KIND}] (${SELECTED_DEVICE_ID})"
    return 0
  fi

  if ! interactive_select_device "$devices_file" "$count"; then
    rm -f "$devices_file"
    return 1
  fi

  rm -f "$devices_file"
  return 0
}

xcode_can_run_selected_device() {
  local destinations
  destinations="$(xcodebuild -workspace "$WORKSPACE" -scheme Runner -showdestinations 2>&1 || true)"

  if printf '%s\n' "$destinations" | grep -F "$SELECTED_DEVICE_ID" >/dev/null 2>&1; then
    ok "Xcode Runner scheme 已识别 ${SELECTED_DEVICE_NAME} 为 Run Destination"
    return 0
  fi

  warn "Flutter 找到了 ${SELECTED_DEVICE_NAME}，但 Xcode Runner scheme 没有把它列为可运行目标。"
  printf '%s\n' "$destinations" >&2
  print_device_help
  return 1
}

prepare_run_device() {
  select_run_device || return 1
  xcode_can_run_selected_device || return 1
  return 0
}

open_workspace() {
  local device_ready=true

  if [[ "$BUILD_TARGET" == "device" ]]; then
    if ! select_run_device || ! xcode_can_run_selected_device; then
      device_ready=false
      warn "仍会打开 Xcode，但在设备问题解决前 Run/播放按钮可能不可用。"
      print_device_diagnostics
    fi
  fi

  info "打开 Runner.xcworkspace"
  open -a Xcode "$WORKSPACE"

  if [[ "$device_ready" == "true" && "$BUILD_TARGET" == "device" ]]; then
    ok "Xcode 已能看到 ${SELECTED_DEVICE_NAME}。若没有自动选中，请在顶部 Run Destination 菜单选中它后点击 ▶。"
  fi
}

print_doctor() {
  local failed=0

  printf '\niOS environment doctor\n'
  printf '%s\n' '----------------------'

  [[ "$(uname -s)" == "Darwin" ]] && ok "macOS" || { warn "当前系统不是 macOS"; failed=1; }
  [[ -n "$FLUTTER_BIN" && -x "$FLUTTER_BIN" ]] && ok "Flutter: $FLUTTER_BIN" || { warn "Flutter 未找到"; failed=1; }
  check_command xcodebuild "Xcode command line tools" || failed=1
  check_command pod "CocoaPods" || failed=1
  check_command /usr/bin/shasum "shasum" || failed=1

  [[ -f "$PROJECT_ROOT/pubspec.lock" ]] && ok "pubspec.lock" || { warn "pubspec.lock 不存在"; failed=1; }
  [[ -f "$IOS_DIR/Podfile" ]] && ok "ios/Podfile" || { warn "ios/Podfile 不存在"; failed=1; }
  [[ -f "$IOS_DIR/Podfile.lock" ]] && ok "ios/Podfile.lock" || { warn "ios/Podfile.lock 不存在"; failed=1; }

  workspace_healthy && ok "Runner.xcworkspace 正确引用 Pods" || { warn "Runner.xcworkspace 不完整"; failed=1; }
  [[ -d "$PODS_PROJECT" ]] && ok "Pods.xcodeproj" || { warn "Pods.xcodeproj 不存在"; failed=1; }
  [[ -f "$PODS_DEBUG_CONFIG" ]] && ok "Pods-Runner.debug.xcconfig" || { warn "Pods-Runner.debug.xcconfig 不存在"; failed=1; }
  plugin_symlinks_healthy && ok "Flutter iOS plugin symlinks" || { warn "Flutter iOS plugin symlink 缺失或过期"; failed=1; }

  if ios_run_devices >/dev/null 2>&1; then
    ok "Flutter 可枚举 iOS 运行设备"
  else
    warn "Flutter 无法枚举 iOS 运行设备"
  fi

  if [[ "$failed" -eq 0 ]]; then
    ok "iOS build environment healthy"
    return 0
  fi

  warn "iOS build environment unhealthy；运行 ./scripts/ios_repair.sh 可自动修复 Pods/Flutter 集成问题"
  return 1
}

run_flutter_build() {
  local log_file="$1"
  local args=(build ios "--$BUILD_MODE")

  if [[ "$BUILD_TARGET" == "simulator" ]]; then
    args+=(--simulator)
  else
    args+=(--no-codesign)
  fi

  info "执行：flutter ${args[*]}"
  set +e
  "$FLUTTER_BIN" "${args[@]}" 2>&1 | tee "$log_file"
  local build_status=${PIPESTATUS[0]}
  set -e
  return "$build_status"
}

run_flutter_on_device() {
  local log_file="$1"
  local args=(run -d "$SELECTED_DEVICE_ID" "--$BUILD_MODE")

  info "直接运行到 ${SELECTED_DEVICE_NAME}：flutter ${args[*]}"
  if [[ "$SELECTED_DEVICE_KIND" == "iPhone" ]]; then
    info "此步骤会使用 Xcode signing 构建、安装并启动 App；按 q 可结束 flutter run。"
  else
    info "此步骤会构建并启动 Simulator App；按 q 可结束 flutter run。"
  fi

  set +e
  "$FLUTTER_BIN" "${args[@]}" 2>&1 | tee "$log_file"
  local run_status=${PIPESTATUS[0]}
  set -e
  return "$run_status"
}

is_repairable_pods_failure() {
  local log_file="$1"
  grep -Eiq \
    "Module ['\"]?[^'\"]+['\"]? not found|No such module|framework .* not found|could not build module|Pods-Runner\..*\.xcconfig.*(not found|unable)|GeneratedPluginRegistrant.*(module|plugin)" \
    "$log_file"
}

[[ "$(uname -s)" == "Darwin" ]] || die "iOS 构建只能在 macOS 上执行"
[[ -n "$FLUTTER_BIN" && -x "$FLUTTER_BIN" ]] || \
  die "找不到 Flutter；请设置 FLUTTER_BIN 或使用 --flutter"
command -v xcodebuild >/dev/null 2>&1 || die "找不到 Xcode command line tools"
command -v pod >/dev/null 2>&1 || die "找不到 CocoaPods；请先安装 CocoaPods"
[[ -f "$PROJECT_ROOT/pubspec.lock" ]] || die "缺少 pubspec.lock"
[[ -f "$IOS_DIR/Podfile" ]] || die "缺少 ios/Podfile"

if [[ "$DOCTOR_ONLY" == "true" ]]; then
  print_doctor
  exit $?
fi

cd "$PROJECT_ROOT"
info "同步 Dart/Flutter 依赖"
"$FLUTTER_BIN" pub get

if [[ "$FORCE_REPAIR" == "true" ]]; then
  repair_ios_environment
elif ! pods_healthy || ! state_matches; then
  info "检测到 Pods 缺失、plugin symlink 异常或依赖版本发生变化"
  run_pod_install false
else
  ok "Pods 与当前依赖一致，无需重复安装"
fi

if [[ "$PREPARE_ONLY" == "true" ]]; then
  ok "iOS 构建环境准备完成"
  if [[ "$OPEN_WORKSPACE" == "true" ]]; then
    open_workspace
  fi
  exit 0
fi

BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/bookstore-ios-build.XXXXXX.log")"
trap 'rm -f "$BUILD_LOG"' EXIT

if [[ "$RUN_DEVICE" == "true" ]]; then
  prepare_run_device || {
    print_device_diagnostics
    die "没有可供 Runner 使用的 iOS 设备；请按上面的设备诊断处理后重试"
  }

  if [[ "$OPEN_WORKSPACE" == "true" ]]; then
    info "先打开 Runner.xcworkspace；所选设备已被 Xcode 识别"
    open -a Xcode "$WORKSPACE"
  fi

  if run_flutter_on_device "$BUILD_LOG"; then
    ok "App 已在 ${SELECTED_DEVICE_NAME} 上启动"
    exit 0
  fi

  if is_repairable_pods_failure "$BUILD_LOG"; then
    warn "设备运行遇到 CocoaPods/Flutter plugin module 异常，将自动深度修复并重试一次"
    repair_ios_environment
    [[ -n "$SELECTED_DEVICE_ID" ]] || die "修复后目标设备信息丢失"
    xcode_can_run_selected_device || die "修复后所选设备不再可用于 Runner"
    : >"$BUILD_LOG"
    run_flutter_on_device "$BUILD_LOG" || die "自动修复后设备运行仍失败，请保留上方日志进一步排查"
    ok "App 已在自动修复后于 ${SELECTED_DEVICE_NAME} 上启动"
    exit 0
  fi

  die "设备运行失败；若日志包含 Signing/Provisioning/Developer Mode，请按 Xcode 提示完成设备信任和签名设置"
fi

if run_flutter_build "$BUILD_LOG"; then
  ok "iOS build 成功"
else
  if is_repairable_pods_failure "$BUILD_LOG"; then
    warn "检测到 CocoaPods/Flutter plugin module 异常，将自动深度修复并重试一次"
    repair_ios_environment
    : >"$BUILD_LOG"
    run_flutter_build "$BUILD_LOG" || die "自动修复后 iOS build 仍失败，请保留上方构建日志进一步排查"
    ok "iOS build 在自动修复后成功"
  else
    die "iOS build 失败，但日志不像 Pods/plugin 集成问题；未执行破坏缓存的无意义修复"
  fi
fi

if [[ "$OPEN_WORKSPACE" == "true" ]]; then
  open_workspace
fi
