#!/bin/bash

# Parse command line arguments
DIR="."
while [[ $# -gt 0 ]]; do
  case $1 in
    -r|--root)
      DIR="$2"
      shift 2
      ;;
    *)
      DIR="$1"
      shift
      ;;
  esac
done

# Check if we're reading from stdin (pipeline) or finding files
if [ -t 0 ]; then
  # Not a pipeline, find files in directory
  INPUT_SOURCE="find \"$DIR\" -type f"
else
  # Reading from pipeline
  INPUT_SOURCE="cat"
fi

while IFS= read -r f; do
  # Skip empty lines
  [[ -z "$f" ]] && continue
  
  # Check if file exists and is readable
  if [[ ! -f "$f" ]] || [[ ! -r "$f" ]]; then
    echo "Skipping $f (not found or not readable)" >&2
    continue
  fi
  
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
done < <(eval "$INPUT_SOURCE")

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
