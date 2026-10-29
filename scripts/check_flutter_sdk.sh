#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
flutter_bin="${1:-${FLUTTER_BIN:-flutter}}"

fail() {
  printf 'Pinned Flutter SDK check failed: %s\n' "$1" >&2
  printf 'Use the Flutter version declared in %s/.fvmrc.\n' "$repo_root" >&2
  exit 1
}

if [[ "$flutter_bin" == */* ]]; then
  [[ -x "$flutter_bin" ]] || fail "Flutter executable is not executable: $flutter_bin"
else
  command -v "$flutter_bin" >/dev/null 2>&1 || fail "Flutter executable not found: $flutter_bin"
fi

expected_flutter="$(sed -nE 's/.*"flutter"[[:space:]]*:[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/p' .fvmrc | head -n 1)"
[[ -n "$expected_flutter" ]] || fail '.fvmrc must define a semantic Flutter version such as 3.47.7'

flutter_info="$("$flutter_bin" --version --machine 2>/dev/null)" || fail "unable to query Flutter version from $flutter_bin"
actual_flutter="$(printf '%s\n' "$flutter_info" | sed -nE 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)"
expected_dart="$(printf '%s\n' "$flutter_info" | sed -nE 's/.*"dartSdkVersion"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)"
[[ -n "$actual_flutter" && -n "$expected_dart" ]] || fail 'Flutter --version --machine did not report frameworkVersion and dartSdkVersion'
[[ "$actual_flutter" == "$expected_flutter" ]] || fail "expected Flutter $expected_flutter, found $actual_flutter"

dart_bin="${DART_BIN:-$(command -v dart || true)}"
[[ -n "$dart_bin" ]] || fail 'Dart executable not found on PATH'
dart_info="$("$dart_bin" --version 2>&1)" || fail "unable to query Dart version from $dart_bin"
actual_dart="$(printf '%s\n' "$dart_info" | sed -nE 's/.*Dart SDK version: ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1)"
[[ -n "$actual_dart" ]] || fail 'unable to parse `dart --version` output'
[[ "$actual_dart" == "$expected_dart" ]] || fail "Flutter $actual_flutter bundles Dart $expected_dart, but PATH resolves Dart $actual_dart ($dart_bin)"

printf 'Pinned toolchain verified: Flutter %s / Dart %s\n' "$actual_flutter" "$actual_dart"
