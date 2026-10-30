#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
snapshot="$(mktemp -d)"
trap 'rm -rf "$snapshot"' EXIT

for file in pubspec.lock analysis_options.yaml; do
  cp -- "$file" "$snapshot/$file"
done

flutter pub get --enforce-lockfile

modified=0
for file in pubspec.lock analysis_options.yaml; do
  if ! cmp -s -- "$snapshot/$file" "$file"; then
    printf 'Flutter dependency resolution unexpectedly modified %s.\n' "$file" >&2
    git --no-pager diff -- "$file" || true
    modified=1
  fi
done

if [[ "$modified" -ne 0 ]]; then
  printf 'Dependency resolution must not rewrite committed lock or analyzer configuration files.\n' >&2
  exit 1
fi

printf 'Flutter dependency resolution is reproducible; tracked inputs remained unchanged.\n'
