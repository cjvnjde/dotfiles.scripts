#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
    cat <<'EOF'
Usage:
  backup-gpg.sh [--no-age] backup <GPG_KEY_ID> <output-file>
  backup-gpg.sh [--no-age] restore <backup-file>

Archives are encrypted with an age passphrase by default.
Use --no-age for a plain .tar.gz archive (both backup and restore).
GPG uses the current keyring, or GNUPGHOME when set.
EOF
}

use_age=1
if [[ "${1:-}" == "--no-age" ]]; then
    use_age=0
    shift
fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

case "${1:-}" in
    backup)
        [[ $# -eq 3 ]] || { usage >&2; exit 1; }
        key="$2"
        archive="$3"
        ;;
    restore)
        [[ $# -eq 2 ]] || { usage >&2; exit 1; }
        archive="$2"
        [[ -f "$archive" ]] || {
            printf 'Backup not found: %s\n' "$archive" >&2
            exit 1
        }
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac
action="$1"

if (( use_age )) && ! command -v age >/dev/null 2>&1; then
    printf 'age is required; install it or explicitly use --no-age.\n' >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

case "$action" in
    backup)
        if [[ -e "$archive" || -L "$archive" ]]; then
            printf 'Refusing to overwrite: %s\n' "$archive" >&2
            exit 1
        fi

        gpg --export --export-options backup --output "$tmp/pubkeys.gpg" -- "$key"
        gpg --export-secret-keys --export-options backup --output "$tmp/privkeys.gpg" -- "$key"
        [[ -s "$tmp/pubkeys.gpg" && -s "$tmp/privkeys.gpg" ]] || {
            printf 'No public and secret key pair exported for: %s\n' "$key" >&2
            exit 1
        }
        gpg --export-ownertrust > "$tmp/ownertrust.txt"
        tar -czf "$tmp/gpg.tar.gz" -C "$tmp" ./pubkeys.gpg ./privkeys.gpg ./ownertrust.txt

        output="$tmp/gpg.tar.gz"
        if (( use_age )); then
            age --passphrase --output "$tmp/gpg.tar.gz.age" "$output"
            output="$tmp/gpg.tar.gz.age"
        else
            printf 'Warning: saving secret keys without age encryption.\n' >&2
        fi
        # Refuse existing files and symlinks, even if created during the export.
        (set -o noclobber; cat "$output" > "$archive")
        printf 'Backup created: %s\n' "$archive"
        ;;
    restore)
        input="$archive"
        if (( use_age )); then
            age --decrypt --output "$tmp/gpg.tar.gz" "$archive"
            input="$tmp/gpg.tar.gz"
        fi
        tar -xzf "$input" -C "$tmp" ./pubkeys.gpg ./privkeys.gpg ./ownertrust.txt
        for file in pubkeys.gpg privkeys.gpg ownertrust.txt; do
            [[ -f "$tmp/$file" && ! -L "$tmp/$file" ]] || {
                printf 'Invalid backup member: %s\n' "$file" >&2
                exit 1
            }
        done
        gpg --import "$tmp/pubkeys.gpg"
        gpg --import "$tmp/privkeys.gpg"
        gpg --import-ownertrust "$tmp/ownertrust.txt"
        printf 'GPG keys and owner trust restored.\n'
        ;;
esac
