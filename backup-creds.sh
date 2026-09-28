#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage:"
    echo "  $0 backup  <output-file>"
    echo "  $0 restore <backup-file>"
    exit 1
}

[[ $# -eq 2 ]] || usage

action="$1"
archive="$2"

case "$action" in
    backup)
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT

        echo "Creating credential backup..."

        tar \
            --exclude='.gnupg/S.gpg-agent*' \
            --exclude='.gnupg/*.sock' \
            --exclude='.ssh/control-*' \
            -C "$HOME" \
            -czf "$tmp/credentials.tar.gz" \
            .ssh \
            .gnupg

        echo "Encrypting backup..."

        age \
            --passphrase \
            --output "$archive" \
            "$tmp/credentials.tar.gz"

        chmod 600 "$archive"

        echo "Backup created:"
        echo "$archive"
        ;;

    restore)
        [[ -f "$archive" ]] || {
            echo "Backup not found: $archive" >&2
            exit 1
        }

        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT

        echo "Decrypting backup..."

        age \
            --decrypt \
            --output "$tmp/credentials.tar.gz" \
            "$archive"

        echo "Restoring credentials..."

        tar \
            -xzf "$tmp/credentials.tar.gz" \
            -C "$HOME"

        chmod 700 "$HOME/.ssh"
        chmod 700 "$HOME/.gnupg"

        gpgconf --kill gpg-agent 2>/dev/null || true

        echo "Credentials restored."
        ;;

    *)
        usage
        ;;
esac
