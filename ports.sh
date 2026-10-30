#!/usr/bin/env bash
# TCP listener picker; compatible with macOS's Bash 3.2 and Linux.
set -uo pipefail

usage() {
  cat <<'EOF'
Usage: ports [QUERY]
       ports --list

Browse TCP listening ports with fzf (optionally start with QUERY).
  Enter    Inspect process, then [k] stop, [j] jump, [r] refresh, [q] quit
  Ctrl-K   Send SIGTERM to the selected process
  Ctrl-J   Focus the selected process's Herdr workspace
  Ctrl-R   Refresh listeners
  Esc      Quit

--list prints the table without fzf, e.g. ports --list | fzf --header-lines=1.
Requires lsof and fzf; Herdr is optional. Only visible processes are listed.
Stopping a process affects all its ports. No sudo or forced kill is used.
EOF
}

listeners() {
  local output status
  # Field output avoids truncated command names and whitespace-dependent columns.
  output=$(lsof -nP -iTCP -sTCP:LISTEN -Fpcn)
  status=$?
  # lsof returns 1 when there are no matching sockets.
  (( status <= 1 )) || return "$status"
  printf '%s\n' "$output" | awk '
    /^p/ { pid = substr($0, 2) }
    /^c/ { command = substr($0, 2) }
    /^n/ {
      address = substr($0, 2)
      port = address
      sub(/^.*:/, "", port)
      if (pid ~ /^[0-9]+$/ && port ~ /^[0-9]+$/)
        printf "%-7s %-8s %-24s %s\n", port, pid, command, address
    }
  ' | LC_ALL=C sort -u -k1,1n -k2,2n
}

herdr_context() {
  local pid=$1 entry
  workspace='' socket=''
  if [[ -r /proc/$pid/environ ]]; then
    # Linux exposes NUL-delimited entries, preserving spaces in socket paths.
    while IFS= read -r -d '' entry; do
      case "$entry" in
        HERDR_WORKSPACE_ID=*) workspace=${entry#*=} ;;
        HERDR_SOCKET_PATH=*) socket=${entry#*=} ;;
      esac
    done < "/proc/$pid/environ" 2>/dev/null
  else
    # BSD/macOS ps flattens the environment. Extract only the two needed keys;
    # never display the whole command environment (which can contain secrets).
    while IFS= read -r entry; do
      case "$entry" in
        HERDR_WORKSPACE_ID=*) workspace=${entry#*=} ;;
        HERDR_SOCKET_PATH=*) socket=${entry#*=} ;;
      esac
    done < <(ps eww -o command= -p "$pid" 2>/dev/null | awk '
      {
        for (i = 1; i <= 2; i++) {
          key = (i == 1 ? "HERDR_WORKSPACE_ID" : "HERDR_SOCKET_PATH")
          if (match($0, "(^|[[:space:]])" key "=")) {
            value = substr($0, RSTART + RLENGTH)
            sub(/[[:space:]][A-Za-z_][A-Za-z0-9_]*=.*/, "", value)
            sub(/[[:space:]]+$/, "", value)
            print key "=" value
          }
        }
      }
    ')
  fi
}

main() {
  local query='' table selection key line pid action workspace socket current status
  case "${1:-}" in
    -h|--help) usage; return 0 ;;
    --list) ;;
    -*) printf 'ports: unknown option: %s\n' "$1" >&2; return 2 ;;
    *) query=${1:-} ;;
  esac
  if (( $# > 1 )); then usage >&2; return 2; fi
  if ! command -v lsof >/dev/null 2>&1; then
    printf 'ports: install lsof first (brew install lsof / your Linux package manager).\n' >&2
    return 1
  fi
  if [[ ${1:-} == --list ]]; then
    printf '%-7s %-8s %-24s %s\n' PORT PID COMMAND ADDRESS
    listeners
    return $?
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    printf 'ports: install fzf first (brew install fzf / your Linux package manager).\n' >&2
    return 1
  fi

  while :; do
    table=$(listeners) || return $?
    if [[ -z $table ]]; then
      printf 'No visible TCP listeners.\n'
      return 0
    fi
    selection=$(printf '%-7s %-8s %-24s %s\n%s\n' PORT PID COMMAND ADDRESS "$table" |
      fzf --no-multi --header-lines=1 --prompt='port> ' --query="$query" \
        --header='Enter: inspect | Ctrl-K: stop (TERM) | Ctrl-J: Herdr | Ctrl-R: refresh | Esc: quit' \
        --expect=ctrl-k,ctrl-j,ctrl-r) || {
      status=$?
      if (( status == 1 || status == 130 )); then return 0; fi
      return "$status"
    }
    key=${selection%%$'\n'*}
    [[ $key == ctrl-r ]] && continue
    line=${selection#*$'\n'}
    [[ -n $line && $selection == *$'\n'* ]] || return 0
    pid=$(awk '{print $2}' <<< "$line")
    if [[ ! $pid =~ ^[0-9]+$ ]] || (( pid <= 1 )); then
      printf 'ports: invalid process selection.\n' >&2
      return 1
    fi
    herdr_context "$pid"
    printf '%s\n' "$line"
    ps -p "$pid" -o command= 2>/dev/null || :
    printf 'Herdr workspace: %s\n' "${workspace:-not detected}"
    case "$key" in
      ctrl-k) action=k ;;
      ctrl-j) action=j ;;
      *)
        printf '[k] stop (TERM)  [j] jump to Herdr  [r] refresh  [q] quit: '
        IFS= read -r -n 1 action || return 0
        printf '\n'
        ;;
    esac
    case "$action" in
      k|K)
        # The process may have exited while the picker/menu was open.
        current=$(listeners) || return $?
        if ! printf '%s\n' "$current" | grep -Fx -- "$line" >/dev/null; then
          printf 'ports: selected listener no longer exists; refresh and try again.\n' >&2
          return 1
        fi
        if kill -TERM "$pid"; then
          printf 'Sent SIGTERM to PID %s.\n' "$pid"
          return 0
        fi
        return 1
        ;;
      j|J)
        if [[ -z $workspace ]]; then
          printf 'ports: no Herdr workspace detected for PID %s.\n' "$pid" >&2
          return 1
        fi
        if ! command -v herdr >/dev/null 2>&1; then
          printf 'ports: herdr is not installed or is not on PATH.\n' >&2
          return 1
        fi
        if [[ -n $socket ]]; then
          HERDR_SOCKET_PATH="$socket" herdr workspace focus "$workspace"
        else
          herdr workspace focus "$workspace"
        fi
        return $?
        ;;
      r|R) ;;
      *) return 0 ;;
    esac
  done
}

main "$@"
