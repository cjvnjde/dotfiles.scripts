#!/bin/bash

DIR=${1:-.}

while IFS= read -r f; do
  if file --mime-type "$f" | grep -q 'text/'; then
    echo "Copying $f"
    
    # Get file extension for code block
    FILENAME=$(basename "$f")
    FILE_EXT="${FILENAME##*.}"
    
    # Determine code block language
    if [[ "$FILE_EXT" != "$FILENAME" ]] && [[ -n "$FILE_EXT" ]]; then
        # File has extension
        CODE_LANG="$FILE_EXT"
    else
        # No extension, check shebang or content
        FIRST_LINE=$(head -n1 "$f" 2>/dev/null)
        if [[ "$FIRST_LINE" =~ ^#!.*bash ]] || [[ "$FIRST_LINE" =~ ^#!.*sh ]]; then
            CODE_LANG="bash"
        elif [[ "$FIRST_LINE" =~ ^#!.*python ]]; then
            CODE_LANG="python"
        else
            CODE_LANG=""
        fi
    fi
    
    # Add YAML Front Matter
    OUTPUT="${OUTPUT}---\n"
    OUTPUT="${OUTPUT}file_path: \"$f\"\n"
    OUTPUT="${OUTPUT}---\n\n"
    
    # Add file content in code block
    OUTPUT="$OUTPUT\`\`\`${CODE_LANG}\n"
    OUTPUT="$OUTPUT$(cat "$f")\n"
    OUTPUT="$OUTPUT\`\`\`\n\n"
  fi
done < <(find "$DIR" -type f)

OS=$(uname)

OS=$(uname)

if [ "$OS" = "Darwin" ]; then
  printf "%b" "$OUTPUT" | pbcopy 
elif [ "$OS" = "Linux" ]; then
  if command -v wl-copy >/dev/null 2>&1; then
    printf "%b" "$OUTPUT" | wl-copy
  else
    echo "wl-copy not found."
    exit 1
  fi
else
  echo "Unsupported OS: $OS"
  exit 1
fi

echo "Copied to clipboard."
