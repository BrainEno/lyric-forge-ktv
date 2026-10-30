#!/usr/bin/env bash
set -euo pipefail

readonly app_id='io.github.braineno.lyricforge'
readonly android_gradle='android/app/build.gradle.kts'
readonly android_activity='android/app/src/main/kotlin/io/github/braineno/lyricforge/MainActivity.kt'
readonly ios_project='ios/Runner.xcodeproj/project.pbxproj'
readonly macos_project='macos/Runner.xcodeproj/project.pbxproj'
readonly macos_config='macos/Runner/Configs/AppInfo.xcconfig'
readonly linux_config='linux/CMakeLists.txt'
readonly windows_resources='windows/runner/Runner.rc'

fail() {
  printf 'App identifier contract failed: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || fail "$file must contain: $expected"
}

assert_not_contains() {
  local file="$1"
  local forbidden="$2"
  if grep -Fq -- "$forbidden" "$file"; then
    fail "$file still contains forbidden template value: $forbidden"
  fi
}

assert_contains "$android_gradle" "namespace = \"$app_id\""
assert_contains "$android_gradle" "applicationId = \"$app_id\""
assert_contains "$android_activity" "package $app_id"
if [[ -e "android/app/src/main/kotlin/com/example/lyric_forge_ktv/MainActivity.kt" ]]; then
  fail "old Android activity package still exists"
fi
assert_contains "$ios_project" "PRODUCT_BUNDLE_IDENTIFIER = $app_id;"
assert_contains "$ios_project" "PRODUCT_BUNDLE_IDENTIFIER = $app_id.RunnerTests;"
assert_contains "$macos_project" "PRODUCT_BUNDLE_IDENTIFIER = $app_id.RunnerTests;"
assert_contains "$macos_config" "PRODUCT_BUNDLE_IDENTIFIER = $app_id"
assert_contains "$linux_config" "set(APPLICATION_ID \"$app_id\")"
assert_contains "$windows_resources" 'VALUE "CompanyName", "BrainEno"'

for file in "$android_gradle" "$android_activity" "$ios_project" "$macos_project" "$macos_config" "$linux_config" "$windows_resources"; do
  assert_not_contains "$file" 'com.example'
done

printf 'App identifier contract passed: %s\n' "$app_id"
