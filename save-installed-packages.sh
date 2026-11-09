#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: save-installed-packages.sh [directory]\n'
    printf 'Default: ~/.local/state/system, beside SYSTEM.md. Requires pacman and mise.\n'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
[[ $# -le 1 ]] || { usage >&2; exit 1; }

directory="${1:-"$HOME/.local/state/system"}"
mkdir -p -- "$directory"
directory="$(cd -P -- "$directory" && pwd)"

tmp="$(mktemp -d "$directory/.package-lists.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
pacman -Qqen > "$tmp/official-packages.txt"
pacman -Qqem > "$tmp/aur-packages.txt"
mise ls --installed --json > "$tmp/mise-packages.json"
mv -- "$tmp/official-packages.txt" "$directory/official-packages.txt"
mv -- "$tmp/aur-packages.txt" "$directory/aur-packages.txt"
mv -- "$tmp/mise-packages.json" "$directory/mise-packages.json"
printf 'Package lists saved to: %s\n' "$directory"
