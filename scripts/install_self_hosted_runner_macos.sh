#!/usr/bin/env bash

set -euo pipefail

REPO="${REPO:-BrainEno/book-management-system}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/actions-runner-bookstore}"
COMPUTER_NAME="$(scutil --get ComputerName 2>/dev/null || hostname)"
RUNNER_NAME="${RUNNER_NAME:-${COMPUTER_NAME// /-}-bookstore-mac}"
PREFERRED_PROXY_PORT="${PREFERRED_PROXY_PORT:-10808}"
DETECTED_PROXY=""

log() {
  printf '\n==> %s\n' "$1"
}

fail() {
  printf '\nERROR: %s\n' "$1" >&2
  exit 1
}

add_common_paths() {
  for dir in /opt/homebrew/bin /opt/homebrew/sbin /usr/local/bin /usr/local/sbin; do
    if [[ -d "$dir" ]] && [[ ":$PATH:" != *":$dir:"* ]]; then
      export PATH="$dir:$PATH"
    fi
  done
}

configure_github_network() {
  if curl --noproxy '*' --fail --silent --show-error --head --max-time 5 https://github.com/ >/dev/null 2>&1; then
    log "GitHub is reachable directly; no proxy is required"
    DETECTED_PROXY=""
    return
  fi

  local ports=("$PREFERRED_PROXY_PORT" 10808 10809 7890 7897 1080)
  local seen=" "
  local port candidate

  for port in "${ports[@]}"; do
    if [[ "$seen" == *" $port "* ]]; then
      continue
    fi
    seen+="$port "
    candidate="http://127.0.0.1:${port}"
    printf 'Checking local proxy %s ...\n' "$candidate"
    if curl --fail --silent --show-error --head --max-time 5 --proxy "$candidate" https://github.com/ >/dev/null 2>&1; then
      DETECTED_PROXY="$candidate"
      export HTTP_PROXY="$candidate"
      export HTTPS_PROXY="$candidate"
      export http_proxy="$candidate"
      export https_proxy="$candidate"
      log "Using local proxy $candidate"
      return
    fi
  done

  fail "GitHub is unreachable directly and no working local HTTP proxy was found. Checked preferred/common ports including $PREFERRED_PROXY_PORT."
}

persist_runner_network_env() {
  mkdir -p "$INSTALL_DIR"
  local env_file="$INSTALL_DIR/.env"
  local tmp_file="$INSTALL_DIR/.env.tmp"

  touch "$env_file"
  grep -Ev '^(HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy)=' "$env_file" > "$tmp_file" || true

  if [[ -n "$DETECTED_PROXY" ]]; then
    {
      printf 'HTTP_PROXY=%s\n' "$DETECTED_PROXY"
      printf 'HTTPS_PROXY=%s\n' "$DETECTED_PROXY"
      printf 'http_proxy=%s\n' "$DETECTED_PROXY"
      printf 'https_proxy=%s\n' "$DETECTED_PROXY"
    } >> "$tmp_file"
  fi

  mv "$tmp_file" "$env_file"
}

printf '\nBook Management System - GitHub self-hosted runner installer\n'
printf 'Repository: %s\n' "$REPO"
printf 'Install dir: %s\n' "$INSTALL_DIR"
printf 'Runner name: %s\n' "$RUNNER_NAME"
printf 'Preferred proxy port: %s\n' "$PREFERRED_PROXY_PORT"

add_common_paths
configure_github_network

if ! xcode-select -p >/dev/null 2>&1; then
  fail "Xcode is not configured. Install the full Xcode app, open it once, then rerun this script."
fi

XCODE_DEVELOPER_DIR="$(xcode-select -p)"
if [[ "$XCODE_DEVELOPER_DIR" == *"CommandLineTools"* ]]; then
  fail "Only Xcode Command Line Tools are selected. iOS IPA builds require the full Xcode app. Install/open Xcode, then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  fail "xcodebuild is unavailable. Install the full Xcode app before configuring the macOS runner."
fi

log "Xcode"
xcodebuild -version

if ! command -v git >/dev/null 2>&1; then
  fail "git is unavailable even though Xcode appears to be installed."
fi

if ! command -v brew >/dev/null 2>&1; then
  fail "Homebrew is required to bootstrap GitHub CLI/CocoaPods automatically. Install Homebrew, then rerun this script."
fi

if ! command -v gh >/dev/null 2>&1; then
  log "Installing GitHub CLI with Homebrew"
  brew install gh
fi

if ! command -v pod >/dev/null 2>&1; then
  log "Installing CocoaPods with Homebrew"
  brew install cocoapods
fi

log "CocoaPods"
pod --version

# Existing runner: refresh its network environment and dependencies without re-registering it.
if [[ -f "$INSTALL_DIR/.runner" ]]; then
  persist_runner_network_env
  printf '\nRunner is already configured in %s. Refreshing service environment.\n' "$INSTALL_DIR"
  if [[ -x "$INSTALL_DIR/svc.sh" ]]; then
    (
      cd "$INSTALL_DIR"
      ./svc.sh stop || true
      ./svc.sh start
      ./svc.sh status || true
    )
  fi
  printf '\nmacOS runner environment refreshed successfully.\n'
  printf 'Expected custom labels: bookstore, flutter, bookstore-macos\n'
  exit 0
fi

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  log "GitHub authentication required; opening one browser login"
  gh auth login --hostname github.com --git-protocol https --web
fi

if [[ -d "$INSTALL_DIR" ]] && [[ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null || true)" ]]; then
  # .env may have been created by the network bootstrap; ignore it when deciding whether the directory is otherwise empty.
  unexpected="$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name '.env' -print -quit 2>/dev/null || true)"
  if [[ -n "$unexpected" ]]; then
    fail "$INSTALL_DIR exists and is not empty, but no configured runner was found. Inspect or remove that directory before retrying."
  fi
fi

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

case "$(uname -m)" in
  arm64) RUNNER_ARCH="arm64" ;;
  x86_64) RUNNER_ARCH="x64" ;;
  *) fail "Unsupported macOS architecture: $(uname -m)" ;;
esac

log "Resolving latest GitHub Actions runner release"
TAG="$(gh api repos/actions/runner/releases/latest --jq '.tag_name')"
VERSION="${TAG#v}"
ASSET="actions-runner-osx-${RUNNER_ARCH}-${VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/actions/runner/releases/download/${TAG}/${ASSET}"

log "Downloading $ASSET"
curl --fail --location --retry 3 --output "$ASSET" "$DOWNLOAD_URL"
tar xzf "$ASSET"
rm -f "$ASSET"

log "Requesting a short-lived repository registration token"
TOKEN="$(gh api --method POST "repos/$REPO/actions/runners/registration-token" --jq '.token')"
[[ -n "$TOKEN" ]] || fail "Could not obtain a runner registration token. The signed-in GitHub account must have Admin access to $REPO."

log "Configuring runner"
./config.sh \
  --unattended \
  --replace \
  --url "https://github.com/$REPO" \
  --token "$TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "bookstore,flutter,bookstore-macos" \
  --work "_work"

persist_runner_network_env

log "Installing and starting launchd service"
./svc.sh install
./svc.sh start

printf '\nmacOS self-hosted runner installed successfully.\n'
./svc.sh status || true
printf '\nExpected custom labels: bookstore, flutter, bookstore-macos\n'
printf 'Runner page: https://github.com/%s/settings/actions/runners\n' "$REPO"
printf 'The launchd service will restart when this macOS user logs in.\n'
printf 'The iOS IPA workflow now targets this runner via the bookstore-macos label.\n'
