#!/usr/bin/env bash
set -euo pipefail

PREFIX="${HOME}/.docker/sbx"
URL="https://github.com/docker/sbx-releases/releases/latest/download/DockerSandboxes-linux.tar.gz"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading latest Docker SBX..."
curl -fL "$URL" -o "$tmp/DockerSandboxes-linux.tar.gz"

echo "Extracting..."
tar -xzf "$tmp/DockerSandboxes-linux.tar.gz" -C "$tmp"

installer="$tmp/docker-sbx/install.sh"

if [[ ! -x "$installer" ]]; then
  echo "ERROR: installer not found at: $installer" >&2
  echo "Archive contents:" >&2
  find "$tmp" -maxdepth 3 -type f -print >&2
  exit 1
fi

echo "Installing to $PREFIX..."
sudo PREFIX="$PREFIX" "$installer"

echo
echo "Installed:"
"$PREFIX/bin/sbx" version
