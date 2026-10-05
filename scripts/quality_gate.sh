#!/usr/bin/env bash
set -euo pipefail

mode="all"
skip_pub_get=false
test_paths=()

usage() {
  cat <<'EOF'
Usage: scripts/quality_gate.sh [options]

Options:
  --analyze-only         Run analyzer only.
  --test-only            Run tests only.
  --skip-pub-get         Reuse an already restored pub cache/dependency set.
  --test-path <path>     Limit test execution to one path. Repeat as needed.
  -h, --help             Show this help.

Without --test-path, test mode runs the complete Flutter test suite.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --analyze-only)
      if [[ "$mode" != "all" ]]; then
        printf 'Only one quality-gate mode may be selected.\n' >&2
        exit 2
      fi
      mode="analyze"
      shift
      ;;
    --test-only)
      if [[ "$mode" != "all" ]]; then
        printf 'Only one quality-gate mode may be selected.\n' >&2
        exit 2
      fi
      mode="test"
      shift
      ;;
    --skip-pub-get)
      skip_pub_get=true
      shift
      ;;
    --test-path)
      if [[ $# -lt 2 || -z "$2" ]]; then
        printf '%s requires a non-empty path.\n' "$1" >&2
        exit 2
      fi
      test_paths+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown quality-gate option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$mode" == "analyze" && ${#test_paths[@]} -gt 0 ]]; then
  printf '%s\n' '--test-path cannot be used with --analyze-only.' >&2
  exit 2
fi

run_step() {
  local name="$1"
  shift
  printf '\n==> %s\n' "$name"
  "$@"
}

print_provenance() {
  local branch=""
  local sha=""
  branch="${CM_BRANCH:-${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}}"
  if [[ -z "$branch" ]]; then
    branch="$(git branch --show-current 2>/dev/null || true)"
  fi
  sha="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"

  printf 'Quality gate provenance:\n'
  printf '  branch: %s\n' "${branch:-detached-or-unknown}"
  printf '  commit: %s\n' "$sha"
  printf '  mode: %s\n' "$mode"
  if [[ ${#test_paths[@]} -gt 0 ]]; then
    printf '  targeted tests:\n'
    printf '    - %s\n' "${test_paths[@]}"
  else
    printf '  targeted tests: none (full suite when tests run)\n'
  fi
}

print_provenance

if [[ "$skip_pub_get" != true ]]; then
  run_step "flutter pub get" flutter pub get
fi

# Analyze the application and its test surface. packages/desktop_multi_window is a
# vendored dependency; its example/ is a separate demo app and is intentionally
# outside this repository quality gate.
if [[ "$mode" == "all" || "$mode" == "analyze" ]]; then
  run_step "flutter analyze lib test" flutter analyze --no-pub lib test
fi

if [[ "$mode" == "all" || "$mode" == "test" ]]; then
  if [[ ${#test_paths[@]} -gt 0 ]]; then
    run_step "targeted flutter test" \
      flutter test --no-pub --reporter expanded "${test_paths[@]}"
  else
    run_step "flutter test" flutter test --no-pub --reporter expanded
  fi
fi

printf '\nRepository quality gate (%s) passed.\n' "$mode"
