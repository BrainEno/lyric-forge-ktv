#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-BrainEno/book-management-system}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/actions-runner-bookstore-wsl}"
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter-sdk}"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.41.9}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-bookstore-wsl}"
PREFERRED_PROXY_PORT="${PREFERRED_PROXY_PORT:-10808}"
WSL_NETWORK_MODE_HINT="${WSL_NETWORK_MODE_HINT:-auto}"
DETECTED_PROXY=""

log() {
  printf '\n==> %s\n' "$1"
}

fail() {
  printf '\nERROR: %s\n' "$1" >&2
  exit 1
}

is_wsl() {
  grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null ||
    grep -qi microsoft /proc/version 2>/dev/null
}

require_supported_linux() {
  is_wsl || fail "This installer is intended for WSL2 Ubuntu/Debian."
  [[ "$(id -u)" -ne 0 ]] || fail "Run this script as your normal WSL user, not as root. It will use sudo when required."

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian) ;;
      *) fail "Unsupported WSL distribution: ${PRETTY_NAME:-${ID:-unknown}}. Use Ubuntu or Debian." ;;
    esac
  else
    fail "/etc/os-release is unavailable; cannot identify the WSL distribution."
  fi
}

candidate_windows_hosts() {
  {
    printf '%s\n' "127.0.0.1"
    ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
    awk '/^nameserver[[:space:]]+/ {print $2; exit}' /etc/resolv.conf 2>/dev/null
  } | awk 'NF && !seen[$0]++'
}

tcp_port_open() {
  local host="$1"
  local port="$2"
  timeout 1 bash -c ":</dev/tcp/${host}/${port}" >/dev/null 2>&1
}

proxy_from_environment() {
  local candidate="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}}"
  [[ -n "$candidate" ]] || return 1

  DETECTED_PROXY="$candidate"
  log "Detected proxy variables supplied by WSL/Windows auto-proxy"
  return 0
}

seed_proxy_from_windows() {
  local ports=("$PREFERRED_PROXY_PORT" 10808 10809 7890 7897 1080)
  local host port key
  declare -A seen=()

  while IFS= read -r host; do
    for port in "${ports[@]}"; do
      key="${host}:${port}"
      [[ -n "${seen[$key]:-}" ]] && continue
      seen[$key]=1
      if tcp_port_open "$host" "$port"; then
        DETECTED_PROXY="http://${host}:${port}"
        export HTTP_PROXY="$DETECTED_PROXY"
        export HTTPS_PROXY="$DETECTED_PROXY"
        export http_proxy="$DETECTED_PROXY"
        export https_proxy="$DETECTED_PROXY"
        export NO_PROXY="localhost,127.0.0.1"
        export no_proxy="$NO_PROXY"
        log "Detected a reachable Windows-side proxy at $DETECTED_PROXY"
        return 0
      fi
    done
  done < <(candidate_windows_hosts)

  return 1
}

verify_github_network() {
  if curl --noproxy '*' --fail --silent --show-error --head --max-time 8 https://github.com/ >/dev/null 2>&1; then
    DETECTED_PROXY=""
    unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy || true
    log "GitHub is reachable directly; no proxy is required"
    return
  fi

  if [[ -n "$DETECTED_PROXY" ]]; then
    printf 'Checking inherited/detected proxy %s ...\n' "$DETECTED_PROXY"
    if curl --fail --silent --show-error --head --max-time 6 --proxy "$DETECTED_PROXY" https://github.com/ >/dev/null 2>&1; then
      export HTTP_PROXY="$DETECTED_PROXY"
      export HTTPS_PROXY="$DETECTED_PROXY"
      export http_proxy="$DETECTED_PROXY"
      export https_proxy="$DETECTED_PROXY"
      export NO_PROXY="localhost,127.0.0.1"
      export no_proxy="$NO_PROXY"
      log "Using GitHub proxy $DETECTED_PROXY"
      return
    fi
  fi

  local ports=("$PREFERRED_PROXY_PORT" 10808 10809 7890 7897 1080)
  local host port candidate key
  declare -A seen=()

  while IFS= read -r host; do
    for port in "${ports[@]}"; do
      key="${host}:${port}"
      [[ -n "${seen[$key]:-}" ]] && continue
      seen[$key]=1
      candidate="http://${host}:${port}"
      printf 'Checking WSL proxy route %s ...\n' "$candidate"
      if curl --fail --silent --show-error --head --max-time 6 --proxy "$candidate" https://github.com/ >/dev/null 2>&1; then
        DETECTED_PROXY="$candidate"
        export HTTP_PROXY="$candidate"
        export HTTPS_PROXY="$candidate"
        export http_proxy="$candidate"
        export https_proxy="$candidate"
        export NO_PROXY="localhost,127.0.0.1"
        export no_proxy="$NO_PROXY"
        log "Using GitHub proxy $candidate"
        return
      fi
    done
  done < <(candidate_windows_hosts)

  if [[ "$WSL_NETWORK_MODE_HINT" == "nat" ]]; then
    fail "GitHub is unreachable from WSL2 NAT mode. The installer already tried localhost, the WSL default gateway, the resolver address, and common proxy ports. If the Windows proxy only listens on 127.0.0.1, enable 'Allow LAN' (or equivalent) so the Windows host IP can reach it, then rerun this installer. Preferred proxy port: $PREFERRED_PROXY_PORT."
  fi

  fail "GitHub is unreachable from WSL2. Mirrored networking/autoProxy was requested, but no working direct or proxied route was found. Confirm the Windows proxy is running on port $PREFERRED_PROXY_PORT, then rerun the PowerShell installer."
}

install_base_packages() {
  log "Installing Ubuntu/Debian CI prerequisites"
  if ! sudo -E apt-get update; then
    fail "apt-get update failed. If WSL cannot reach the Windows proxy on port $PREFERRED_PROXY_PORT, rerun the Windows PowerShell installer so it can configure mirrored networking; on older Windows builds, enable LAN access in the proxy app."
  fi

  sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    git \
    gnupg \
    iproute2 \
    jq \
    unzip \
    zip \
    xz-utils \
    build-essential \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libglu1-mesa \
    sqlite3 \
    libsqlite3-dev
}

install_github_cli() {
  if command -v gh >/dev/null 2>&1; then
    return
  fi

  log "Installing GitHub CLI"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
    sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$(dpkg --print-architecture)" |
    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo -E apt-get update
  sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y gh
}

install_browser_bridge() {
  local bridge="$HOME/.local/bin/wsl-browser"
  mkdir -p "$HOME/.local/bin"
  cat >"$bridge" <<'EOF'
#!/usr/bin/env bash
url="${1:-https://github.com/login/device}"
if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command "Start-Process '$url'" >/dev/null 2>&1 || true
elif command -v cmd.exe >/dev/null 2>&1; then
  cmd.exe /c start "" "$url" >/dev/null 2>&1 || true
fi
EOF
  chmod +x "$bridge"
  export PATH="$HOME/.local/bin:$PATH"
  export BROWSER="$bridge"
}

authenticate_github() {
  if gh auth status --hostname github.com >/dev/null 2>&1; then
    log "GitHub CLI is already authenticated"
  else
    log "GitHub authentication required; opening the Windows browser once"
    gh auth login --hostname github.com --git-protocol https --web
  fi

  gh auth setup-git
}

persist_shell_path() {
  local marker_begin="# >>> bookstore CI managed path >>>"
  local marker_end="# <<< bookstore CI managed path <<<"
  local line="export PATH=\"$HOME/.local/bin:$FLUTTER_DIR/bin:\$PATH\""
  local file tmp

  for file in "$HOME/.bashrc" "$HOME/.profile"; do
    touch "$file"
    tmp="$(mktemp)"
    awk -v begin="$marker_begin" -v end="$marker_end" '
      $0 == begin {skip=1; next}
      $0 == end {skip=0; next}
      !skip {print}
    ' "$file" >"$tmp"
    {
      cat "$tmp"
      printf '\n%s\n%s\n%s\n' "$marker_begin" "$line" "$marker_end"
    } >"$file"
    rm -f "$tmp"
  done
}

install_flutter() {
  log "Installing Flutter $FLUTTER_VERSION"

  if [[ ! -d "$FLUTTER_DIR/.git" ]]; then
    rm -rf "$FLUTTER_DIR"
    git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  else
    git -C "$FLUTTER_DIR" fetch --depth 1 origin "refs/tags/$FLUTTER_VERSION:refs/tags/$FLUTTER_VERSION"
    git -C "$FLUTTER_DIR" checkout --force "$FLUTTER_VERSION"
  fi

  export PATH="$HOME/.local/bin:$FLUTTER_DIR/bin:$PATH"
  persist_shell_path

  flutter config --no-analytics
  flutter precache --linux

  local version_output
  version_output="$(flutter --version)"
  printf '%s\n' "$version_output"
  grep -Fq "Flutter $FLUTTER_VERSION" <<<"$version_output" ||
    fail "Flutter installed, but version $FLUTTER_VERSION was not detected."
}

persist_runner_environment() {
  mkdir -p "$INSTALL_DIR"
  local env_file="$INSTALL_DIR/.env"
  local tmp_file="$INSTALL_DIR/.env.tmp"

  touch "$env_file"
  grep -Ev '^(PATH|HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy|NO_PROXY|no_proxy)=' "$env_file" >"$tmp_file" || true

  {
    printf 'PATH=%s\n' "$HOME/.local/bin:$FLUTTER_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    if [[ -n "$DETECTED_PROXY" ]]; then
      printf 'HTTP_PROXY=%s\n' "$DETECTED_PROXY"
      printf 'HTTPS_PROXY=%s\n' "$DETECTED_PROXY"
      printf 'http_proxy=%s\n' "$DETECTED_PROXY"
      printf 'https_proxy=%s\n' "$DETECTED_PROXY"
    fi
    printf 'NO_PROXY=localhost,127.0.0.1\n'
    printf 'no_proxy=localhost,127.0.0.1\n'
  } >>"$tmp_file"

  mv "$tmp_file" "$env_file"
}

ensure_systemd() {
  if [[ "$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')" != "systemd" ]]; then
    fail "systemd is not active in this WSL distribution. From Windows PowerShell run scripts/install_self_hosted_runner_wsl2.ps1; it enables systemd and restarts WSL automatically."
  fi
}

install_or_refresh_runner() {
  persist_runner_environment

  if [[ -f "$INSTALL_DIR/.runner" ]]; then
    log "Runner is already configured; refreshing its environment and service"
    (
      cd "$INSTALL_DIR"
      sudo ./svc.sh stop || true
      sudo ./svc.sh start
      sudo ./svc.sh status || true
    )
    return
  fi

  if [[ -d "$INSTALL_DIR" ]]; then
    local unexpected
    unexpected="$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name '.env' -print -quit 2>/dev/null || true)"
    [[ -z "$unexpected" ]] ||
      fail "$INSTALL_DIR exists and is not empty, but no configured runner was found. Inspect or remove that directory before retrying."
  fi

  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"

  local runner_arch
  case "$(uname -m)" in
    x86_64) runner_arch="x64" ;;
    aarch64|arm64) runner_arch="arm64" ;;
    *) fail "Unsupported Linux architecture: $(uname -m)" ;;
  esac

  log "Resolving latest GitHub Actions runner release"
  local tag version asset download_url
  tag="$(gh api repos/actions/runner/releases/latest --jq '.tag_name')"
  version="${tag#v}"
  asset="actions-runner-linux-${runner_arch}-${version}.tar.gz"
  download_url="https://github.com/actions/runner/releases/download/${tag}/${asset}"

  log "Downloading $asset"
  curl --fail --location --retry 3 --output "$asset" "$download_url"
  tar xzf "$asset"
  rm -f "$asset"

  if [[ -x "$INSTALL_DIR/bin/installdependencies.sh" ]]; then
    log "Installing GitHub Actions runner native dependencies"
    sudo "$INSTALL_DIR/bin/installdependencies.sh"
  fi

  log "Requesting a short-lived repository registration token"
  local token
  token="$(gh api --method POST "repos/$REPO/actions/runners/registration-token" --jq '.token')"
  [[ -n "$token" ]] ||
    fail "Could not obtain a runner registration token. The signed-in GitHub account must have Admin access to $REPO."

  log "Configuring WSL2 runner"
  ./config.sh \
    --unattended \
    --replace \
    --url "https://github.com/$REPO" \
    --token "$token" \
    --name "$RUNNER_NAME" \
    --labels "bookstore,flutter,bookstore-wsl" \
    --work "_work"

  persist_runner_environment

  log "Installing and starting systemd runner service"
  sudo ./svc.sh install "$USER"
  sudo ./svc.sh start
  sudo ./svc.sh status || true
}

warm_repository_dependencies() {
  local script_dir repo_root
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd "$script_dir/.." && pwd)"

  if [[ -f "$repo_root/pubspec.yaml" ]]; then
    log "Warming Flutter dependencies for the repository"
    (
      cd "$repo_root"
      flutter pub get
    )
  fi
}

printf '\nBook Management System - WSL2 GitHub self-hosted runner installer\n'
printf 'Repository: %s\n' "$REPO"
printf 'Install dir: %s\n' "$INSTALL_DIR"
printf 'Flutter: %s -> %s\n' "$FLUTTER_VERSION" "$FLUTTER_DIR"
printf 'Runner name: %s\n' "$RUNNER_NAME"
printf 'Preferred proxy port: %s\n' "$PREFERRED_PROXY_PORT"
printf 'Windows networking hint: %s\n' "$WSL_NETWORK_MODE_HINT"

require_supported_linux

# First respect WSL's autoProxy environment (used by mirrored networking). If
# nothing was inherited, probe localhost and the Windows host/gateway addresses
# so older NAT-based WSL installations still have a best-effort fallback.
proxy_from_environment || seed_proxy_from_windows || true

install_base_packages
verify_github_network
install_github_cli
install_browser_bridge
authenticate_github
install_flutter
ensure_systemd
install_or_refresh_runner
warm_repository_dependencies

printf '\nWSL2 self-hosted runner installed successfully.\n'
printf 'Expected custom labels: bookstore, flutter, bookstore-wsl\n'
printf 'Runner page: https://github.com/%s/settings/actions/runners\n' "$REPO"
printf 'Flutter version: %s\n' "$FLUTTER_VERSION"
printf 'The systemd service starts whenever this WSL distribution boots.\n'
