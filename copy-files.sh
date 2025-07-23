#!/bin/bash

DIR=${1:-.}

while IFS= read -r f; do
  if file --mime-type "$f" | grep -q 'text/'; then
    echo "Copying $f"
    OUTPUT="$OUTPUT=========================="
    OUTPUT="$OUTPUT\nfile path: \"$f\"\n"
    OUTPUT="$OUTPUT==========================\n"
    OUTPUT="$OUTPUT$(cat "$f")\n"
  fi
done < <(find "$DIR" -type f)

OS=$(uname)

OS=$(uname)

if [ "$OS" = "Darwin" ]; then
  printf "$OUTPUT" | pbcopy 
elif [ "$OS" = "Linux" ]; then
  if command -v wl-copy >/dev/null 2>&1; then
    printf "$OUTPUT" | wl-copy
  else
    echo "wl-copy not found."
    exit 1
  fi
else
  echo "Unsupported OS: $OS"
  exit 1
fi

echo "Copied to clipboard."
