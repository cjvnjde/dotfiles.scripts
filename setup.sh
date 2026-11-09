#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

resolve_script_path() {
  local path="$1"

  if command -v realpath >/dev/null 2>&1; then
    realpath "$path" 2>/dev/null && return
  fi

  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$path" 2>/dev/null && return
  fi

  local dir
  dir="$(cd -P "$(dirname "$path")" && pwd)"
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

SCRIPT_PATH="$(resolve_script_path "${BASH_SOURCE[0]}")"
MODULE_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
ROOT_DIR="$(cd "$MODULE_DIR/.." && pwd -P)"
DEST_DIR="$HOME/.local/scripts"

source "$ROOT_DIR/setup/lib.sh"

manage_scripts() {
  local operation="$1" script name
  for script in "$MODULE_DIR"/*.sh; do
    [ -f "$script" ] || continue
    name="${script##*/}"
    case "$name" in
      setup.sh|setup-*.sh) continue ;;
    esac
    "$operation" "$script" "$DEST_DIR/${name%.sh}"
  done
}

enable() {
  unlink_path "$MODULE_DIR" "$DEST_DIR"
  ensure_directory "$DEST_DIR"

  manage_scripts link_path
}

disable() {
  unlink_path "$MODULE_DIR" "$DEST_DIR"
  manage_scripts unlink_path
  rmdir_if_empty "$DEST_DIR"
}

case "${1:-}" in
  enable)
    enable
    ;;
  disable)
    disable
    ;;
  *)
    error "Usage: bash $MODULE_DIR/setup.sh <enable|disable>"
    exit 1
    ;;
esac
