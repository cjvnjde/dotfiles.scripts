#!/usr/bin/env bash
set -uo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: update-arch.sh [options]

Update as much user/system software as possible on this Arch machine.

Currently covers:
  - pacman packages
  - yay / AUR packages
  - flatpak packages (user + system)
  - mise itself + mise-managed tools
  - rustup toolchains
  - cargo-installed binaries
  - uv tools
  - npm global packages
  - pnpm global packages
  - bun global packages
  - pip user packages
  - go-installed binaries
  - tldr cache

Options:
  -y, --yes   Answer yes/non-interactive where supported
  -h, --help  Show this help text

Run this as your normal user. The script uses sudo when needed.
EOF
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()  { printf '%b[INFO]%b  %s\n' "$BLUE" "$RESET" "$*"; }
log_ok()    { printf '%b[OK]%b    %s\n' "$GREEN" "$RESET" "$*"; }
log_skip()  { printf '%b[SKIP]%b  %s\n' "$YELLOW" "$RESET" "$*"; }
log_warn()  { printf '%b[WARN]%b  %s\n' "$YELLOW" "$RESET" "$*"; }
log_err()   { printf '%b[ERR]%b   %s\n' "$RED" "$RESET" "$*"; }
heading()   { printf '\n%b%s%b\n' "$CYAN$BOLD" "$1" "$RESET"; }

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

print_command() {
  printf '$ '
  printf '%q ' "$@"
  printf '\n'
}

record_success() {
  SUCCEEDED+=("$1")
  log_ok "$1"
}

record_skip() {
  local label="$1"
  local reason="${2:-}"
  SKIPPED+=("$label")
  if [[ -n "$reason" ]]; then
    log_skip "$label - $reason"
  else
    log_skip "$label"
  fi
}

record_failure() {
  local label="$1"
  local reason="${2:-}"
  FAILED+=("$label")
  if [[ -n "$reason" ]]; then
    log_err "$label - $reason"
  else
    log_err "$label"
  fi
}

run_step() {
  local label="$1"
  shift

  heading "$label"
  print_command "$@"

  if "$@"; then
    record_success "$label"
    return 0
  fi

  local exit_code=$?
  record_failure "$label" "exit $exit_code"
  return "$exit_code"
}

append_unique() {
  local -n target="$1"
  local value="$2"
  local item

  for item in "${target[@]}"; do
    [[ "$item" == "$value" ]] && return 0
  done

  target+=("$value")
}

find_python_cmd() {
  if has_cmd python3; then
    printf 'python3\n'
  elif has_cmd python; then
    printf 'python\n'
  else
    printf '\n'
  fi
}

is_mise_managed() {
  has_cmd mise && mise which "$1" >/dev/null 2>&1
}

build_tool_cmd() {
  local -n target="$1"
  local tool="$2"
  shift 2

  if is_mise_managed "$tool"; then
    target=(mise exec -- "$tool" "$@")
  else
    target=("$tool" "$@")
  fi
}

start_sudo_keepalive() {
  if [[ "$SUDO_AVAILABLE" -ne 1 || -n "$SUDO_KEEPALIVE_PID" ]]; then
    return 0
  fi

  (
    while true; do
      sleep 60
      sudo -n true >/dev/null 2>&1 || exit 0
    done
  ) &

  SUDO_KEEPALIVE_PID=$!
}

cleanup() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
    kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

prepare_sudo() {
  if ! has_cmd sudo; then
    log_warn "sudo not found; privileged updates will be skipped."
    return 0
  fi

  if ! has_cmd pacman && ! has_cmd flatpak; then
    return 0
  fi

  heading "sudo authentication"
  if sudo -v; then
    SUDO_AVAILABLE=1
    start_sudo_keepalive
    log_ok "sudo session ready"
  else
    log_warn "sudo authentication failed; pacman and system flatpak updates will fail."
  fi
}

discover_npm_globals() {
  NPM_GLOBAL_PACKAGES=()
  NPM_GLOBALS_OK=1
  NPM_GLOBALS_REASON=""

  if ! has_cmd npm; then
    return 0
  fi

  local prefix
  prefix="$(npm prefix -g 2>/dev/null || true)"
  if [[ -z "$prefix" ]]; then
    NPM_GLOBALS_OK=0
    NPM_GLOBALS_REASON="could not determine npm global prefix"
    return 0
  fi

  if [[ "$prefix" != "$HOME"* && ! -w "$prefix" ]]; then
    NPM_GLOBALS_OK=0
    NPM_GLOBALS_REASON="npm global prefix looks system-managed: $prefix"
  fi

  local line pkg lower
  while IFS= read -r line; do
    [[ "$line" == *"/node_modules/"* ]] || continue
    pkg="${line##*/node_modules/}"
    lower="${pkg,,}"
    case "$lower" in
      npm|corepack) continue ;;
    esac
    append_unique NPM_GLOBAL_PACKAGES "$pkg"
  done < <(npm ls -g --depth=0 --parseable 2>/dev/null || true)
}

discover_pip_user_packages() {
  PIP_USER_PACKAGES=()

  if ! has_cmd pip; then
    return 0
  fi

  local line pkg lower
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    pkg="${line%%=*}"
    lower="${pkg,,}"
    case "$lower" in
      pip|setuptools|wheel) continue ;;
    esac
    append_unique PIP_USER_PACKAGES "$pkg"
  done < <(pip list --user --format=freeze 2>/dev/null || true)
}

discover_go_modules() {
  GO_MODULES=()

  if ! has_cmd go; then
    return 0
  fi

  local -a dirs=()
  local gobin gopath dir bin module

  gobin="$(go env GOBIN 2>/dev/null || true)"
  gopath="$(go env GOPATH 2>/dev/null || true)"

  if [[ -n "$gobin" ]]; then
    dirs+=("$gobin")
  fi
  if [[ -n "$gopath" ]]; then
    dirs+=("$gopath/bin")
  fi

  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue

    while IFS= read -r -d '' bin; do
      module="$(go version -m "$bin" 2>/dev/null | awk '$1 == "path" { print $2; exit }')"
      [[ -n "$module" ]] || continue
      [[ "$module" == cmd/* ]] && continue
      append_unique GO_MODULES "$module"
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null)
  done
}

discover_cargo_installs() {
  CARGO_RECORDS=()

  if ! has_cmd cargo; then
    return 0
  fi

  if cargo install --list 2>/dev/null | grep -q '^uv v'; then
    UV_MANAGED_BY_CARGO=1
  fi

  local crates_file="${CARGO_HOME:-$HOME/.cargo}/.crates2.json"
  [[ -f "$crates_file" ]] || return 0

  if [[ -z "$PYTHON_CMD" ]]; then
    log_warn "Skipping cargo metadata discovery: python not found"
    return 0
  fi

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    CARGO_RECORDS+=("$line")
  done < <("$PYTHON_CMD" - "$crates_file" <<'PY'
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)

for key, meta in data.get('installs', {}).items():
    name = key.split(' ', 1)[0]
    source = ''
    if '(' in key and key.endswith(')'):
        source = key.rsplit('(', 1)[1][:-1]
    features = ','.join(meta.get('features', []))
    print('\t'.join([
        name,
        source,
        '1' if meta.get('all_features') else '0',
        '1' if meta.get('no_default_features') else '0',
        meta.get('profile') or 'release',
        meta.get('target') or '',
        features,
    ]))
PY
)
}

discovery_summary() {
  heading "discovery"
  discover_npm_globals
  discover_pip_user_packages
  discover_go_modules
  discover_cargo_installs

  log_info "npm globals to refresh: ${#NPM_GLOBAL_PACKAGES[@]}"
  if [[ "$NPM_GLOBALS_OK" -ne 1 ]]; then
    log_warn "$NPM_GLOBALS_REASON"
  fi
  log_info "pip user packages: ${#PIP_USER_PACKAGES[@]}"
  log_info "go-installed binaries: ${#GO_MODULES[@]}"
  log_info "cargo-installed binaries: ${#CARGO_RECORDS[@]}"
}

update_pacman() {
  local label="pacman packages"
  if ! has_cmd pacman; then
    record_skip "$label" "pacman not found"
    return 0
  fi
  if [[ "$SUDO_AVAILABLE" -ne 1 ]]; then
    record_failure "$label" "sudo unavailable"
    return 0
  fi

  local -a cmd=(sudo pacman -Syu)
  if [[ "$AUTO_YES" -eq 1 ]]; then
    cmd+=(--noconfirm)
  fi

  run_step "$label" "${cmd[@]}"
}

update_yay() {
  local label="yay / AUR packages"
  if ! has_cmd yay; then
    record_skip "$label" "yay not found"
    return 0
  fi

  local -a cmd=(yay -Sua --devel)
  if [[ "$AUTO_YES" -eq 1 ]]; then
    cmd+=(--noconfirm --answerclean None --answerdiff None --answeredit None --answerupgrade All)
  fi

  run_step "$label" "${cmd[@]}"
}

update_flatpak_user() {
  local label="flatpak packages (user)"
  if ! has_cmd flatpak; then
    record_skip "$label" "flatpak not found"
    return 0
  fi

  local -a cmd=(flatpak update --user)
  if [[ "$AUTO_YES" -eq 1 ]]; then
    cmd+=(-y)
  fi

  run_step "$label" "${cmd[@]}"
}

update_flatpak_system() {
  local label="flatpak packages (system)"
  if ! has_cmd flatpak; then
    record_skip "$label" "flatpak not found"
    return 0
  fi
  if [[ "$SUDO_AVAILABLE" -ne 1 ]]; then
    record_failure "$label" "sudo unavailable"
    return 0
  fi

  local -a cmd=(sudo flatpak update --system)
  if [[ "$AUTO_YES" -eq 1 ]]; then
    cmd+=(-y)
  fi

  run_step "$label" "${cmd[@]}"
}

update_mise_self() {
  local label="mise self-update"
  if ! has_cmd mise; then
    record_skip "$label" "mise not found"
    return 0
  fi

  local mise_path
  mise_path="$(command -v mise)"
  if [[ "$mise_path" != "$HOME"* ]]; then
    record_skip "$label" "mise does not look user-managed: $mise_path"
    return 0
  fi

  local -a cmd=(mise self-update)
  if [[ "$AUTO_YES" -eq 1 ]]; then
    cmd+=(--yes)
  fi

  if run_step "$label" "${cmd[@]}"; then
    hash -r 2>/dev/null || true
  fi
}

update_mise_tools() {
  local label="mise-managed tools"
  if ! has_cmd mise; then
    record_skip "$label" "mise not found"
    return 0
  fi

  local -a cmd=(mise upgrade)
  if [[ "$AUTO_YES" -eq 1 ]]; then
    cmd+=(-y)
  fi

  if run_step "$label" "${cmd[@]}"; then
    hash -r 2>/dev/null || true
  fi
}

update_rustup() {
  local label="rustup toolchains"
  if ! has_cmd rustup; then
    record_skip "$label" "rustup not found"
    return 0
  fi

  run_step "$label" rustup update
}

update_cargo_installs() {
  local label="cargo-installed binaries"
  if ! has_cmd cargo; then
    record_skip "$label" "cargo not found"
    return 0
  fi
  if [[ "${#CARGO_RECORDS[@]}" -eq 0 ]]; then
    record_skip "$label" "no cargo-installed binaries found"
    return 0
  fi

  heading "$label"

  local attempted=0
  local failed=0
  local record name source all_features no_default_features profile target features
  local -a cmd=()

  for record in "${CARGO_RECORDS[@]}"; do
    IFS=$'\t' read -r name source all_features no_default_features profile target features <<< "$record"

    case "$source" in
      ''|registry+*) ;;
      *)
        log_skip "$name (unsupported source: $source)"
        continue
        ;;
    esac

    cmd=(cargo install "$name")
    if [[ -n "$features" ]]; then
      cmd+=(--features "$features")
    fi
    if [[ "$all_features" == '1' ]]; then
      cmd+=(--all-features)
    fi
    if [[ "$no_default_features" == '1' ]]; then
      cmd+=(--no-default-features)
    fi
    if [[ -n "$profile" && "$profile" != 'release' ]]; then
      cmd+=(--profile "$profile")
    fi
    if [[ -n "$target" ]]; then
      cmd+=(--target "$target")
    fi

    attempted=$((attempted + 1))
    print_command "${cmd[@]}"
    if "${cmd[@]}"; then
      log_ok "$name"
    else
      failed=1
      log_err "$name failed"
    fi
  done

  if [[ "$attempted" -eq 0 ]]; then
    record_skip "$label" "nothing updateable found"
  elif [[ "$failed" -eq 1 ]]; then
    record_failure "$label"
  else
    record_success "$label"
  fi
}

update_uv_binary() {
  local label="uv executable"
  if ! has_cmd uv; then
    record_skip "$label" "uv not found"
    return 0
  fi
  if [[ "$UV_MANAGED_BY_CARGO" -eq 1 ]]; then
    record_skip "$label" "managed by cargo-installed binaries"
    return 0
  fi

  local uv_path
  uv_path="$(command -v uv)"
  if [[ "$uv_path" != "$HOME"* ]]; then
    record_skip "$label" "uv does not look user-managed: $uv_path"
    return 0
  fi

  run_step "$label" uv self update
}

update_uv_tools() {
  local label="uv tools"
  if ! has_cmd uv; then
    record_skip "$label" "uv not found"
    return 0
  fi
  if ! uv tool list 2>/dev/null | grep -q .; then
    record_skip "$label" "no uv tools installed"
    return 0
  fi

  run_step "$label" uv tool upgrade --all
}

update_npm_globals() {
  local label="npm global packages"
  if ! has_cmd npm; then
    record_skip "$label" "npm not found"
    return 0
  fi
  if [[ "$NPM_GLOBALS_OK" -ne 1 ]]; then
    record_skip "$label" "$NPM_GLOBALS_REASON"
    return 0
  fi
  if [[ "${#NPM_GLOBAL_PACKAGES[@]}" -eq 0 ]]; then
    record_skip "$label" "no non-core npm globals found"
    return 0
  fi

  local -a packages=()
  local pkg
  for pkg in "${NPM_GLOBAL_PACKAGES[@]}"; do
    packages+=("${pkg}@latest")
  done

  local -a cmd=()
  build_tool_cmd cmd npm install -g "${packages[@]}"
  run_step "$label" "${cmd[@]}"
}

update_pnpm_globals() {
  local label="pnpm global packages"
  if ! has_cmd pnpm; then
    record_skip "$label" "pnpm not found"
    return 0
  fi

  local -a cmd=()
  build_tool_cmd cmd pnpm update -g --latest
  run_step "$label" "${cmd[@]}"
}

update_bun_globals() {
  local label="bun global packages"
  if ! has_cmd bun; then
    record_skip "$label" "bun not found"
    return 0
  fi

  local -a cmd=()
  build_tool_cmd cmd bun update -g --latest
  run_step "$label" "${cmd[@]}"
}

update_pip_user_packages() {
  local label="pip user packages"
  if ! has_cmd pip; then
    record_skip "$label" "pip not found"
    return 0
  fi
  if [[ "${#PIP_USER_PACKAGES[@]}" -eq 0 ]]; then
    record_skip "$label" "no user-installed pip packages found"
    return 0
  fi

  local -a cmd=()
  build_tool_cmd cmd pip install --user --upgrade "${PIP_USER_PACKAGES[@]}"
  run_step "$label" "${cmd[@]}"
}

update_go_modules() {
  local label="go-installed binaries"
  if ! has_cmd go; then
    record_skip "$label" "go not found"
    return 0
  fi
  if [[ "${#GO_MODULES[@]}" -eq 0 ]]; then
    record_skip "$label" "no third-party go binaries found"
    return 0
  fi

  heading "$label"

  local attempted=0
  local failed=0
  local module
  local -a cmd=()

  for module in "${GO_MODULES[@]}"; do
    attempted=$((attempted + 1))
    build_tool_cmd cmd go install "${module}@latest"
    print_command "${cmd[@]}"

    if "${cmd[@]}"; then
      log_ok "$module"
    else
      failed=1
      log_err "$module failed"
    fi
  done

  if [[ "$attempted" -eq 0 ]]; then
    record_skip "$label" "nothing updateable found"
  elif [[ "$failed" -eq 1 ]]; then
    record_failure "$label"
  else
    record_success "$label"
  fi
}

update_tldr_cache() {
  local label="tldr cache"
  if ! has_cmd tldr; then
    record_skip "$label" "tldr not found"
    return 0
  fi

  run_step "$label" tldr --update
}

print_summary() {
  heading "summary"
  printf 'Succeeded: %s\n' "${#SUCCEEDED[@]}"
  for item in "${SUCCEEDED[@]}"; do
    printf '  - %s\n' "$item"
  done

  printf '\nSkipped: %s\n' "${#SKIPPED[@]}"
  for item in "${SKIPPED[@]}"; do
    printf '  - %s\n' "$item"
  done

  printf '\nFailed: %s\n' "${#FAILED[@]}"
  for item in "${FAILED[@]}"; do
    printf '  - %s\n' "$item"
  done
}

AUTO_YES=0
SUDO_AVAILABLE=0
SUDO_KEEPALIVE_PID=""
PYTHON_CMD="$(find_python_cmd)"
UV_MANAGED_BY_CARGO=0
NPM_GLOBALS_OK=1
NPM_GLOBALS_REASON=""

declare -a SUCCEEDED=()
declare -a FAILED=()
declare -a SKIPPED=()

declare -a NPM_GLOBAL_PACKAGES=()
declare -a PIP_USER_PACKAGES=()
declare -a GO_MODULES=()
declare -a CARGO_RECORDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      AUTO_YES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_err "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ "$EUID" -eq 0 ]]; then
  log_err "Run this as your normal user, not as root."
  exit 1
fi

heading "update-arch"
log_info "Starting full-system update"
if [[ "$AUTO_YES" -eq 1 ]]; then
  log_info "Auto-yes mode enabled"
fi

discovery_summary
prepare_sudo

update_pacman
update_yay
update_flatpak_user
update_flatpak_system
update_mise_self
update_mise_tools
update_rustup
update_cargo_installs
update_uv_binary
update_uv_tools
update_npm_globals
update_pnpm_globals
update_bun_globals
update_pip_user_packages
update_go_modules
update_tldr_cache

print_summary

if [[ "${#FAILED[@]}" -gt 0 ]]; then
  exit 1
fi

exit 0
