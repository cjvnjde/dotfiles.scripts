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

enable() {
  unlink_path "$MODULE_DIR" "$DEST_DIR"
  ensure_directory "$DEST_DIR"

  link_path "$MODULE_DIR/backup_gpg.sh" "$DEST_DIR/backup_gpg.sh"
  link_path "$MODULE_DIR/restore_gpg.sh" "$DEST_DIR/restore_gpg.sh"
  link_path "$MODULE_DIR/save_installed_packages.sh" "$DEST_DIR/save_installed_packages.sh"
  link_path "$MODULE_DIR/lfub" "$DEST_DIR/lfub"
  link_path "$MODULE_DIR/tmux-sessionizer" "$DEST_DIR/tmux-sessionizer"
  link_path "$MODULE_DIR/vidthumb" "$DEST_DIR/vidthumb"
  link_path "$MODULE_DIR/clipboard-code/clipboard-code.sh" "$DEST_DIR/clipboard-code"
  link_path "$MODULE_DIR/clipboard-code/clipboard-code.sh" "$DEST_DIR/ccode"
}

disable() {
  unlink_path "$MODULE_DIR" "$DEST_DIR"
  unlink_path "$MODULE_DIR/backup_gpg.sh" "$DEST_DIR/backup_gpg.sh"
  unlink_path "$MODULE_DIR/restore_gpg.sh" "$DEST_DIR/restore_gpg.sh"
  unlink_path "$MODULE_DIR/save_installed_packages.sh" "$DEST_DIR/save_installed_packages.sh"
  unlink_path "$MODULE_DIR/lfub" "$DEST_DIR/lfub"
  unlink_path "$MODULE_DIR/tmux-sessionizer" "$DEST_DIR/tmux-sessionizer"
  unlink_path "$MODULE_DIR/vidthumb" "$DEST_DIR/vidthumb"
  unlink_path "$MODULE_DIR/clipboard-code/clipboard-code.sh" "$DEST_DIR/clipboard-code"
  unlink_path "$MODULE_DIR/clipboard-code/clipboard-code.sh" "$DEST_DIR/ccode"
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
