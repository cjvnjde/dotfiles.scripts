# Scripts

Run `bash scripts/setup.sh enable` from the dotfiles root to link commands into
`~/.local/scripts`. The shared zsh configuration also defines `ports` directly
from the checkout; open a new shell after updating it.

## ports

Requires Bash, `lsof`, and `fzf` on macOS or Linux. Install the dependencies with
`brew install lsof fzf`, `sudo pacman -S lsof fzf`, or
`sudo apt install lsof fzf`, as appropriate. Herdr is optional.

```sh
ports                  # Browse TCP listeners
ports 3000             # Start with a fuzzy query (port, PID, command, or address)
ports --list           # Print listeners without opening fzf
ports --list | fzf --header-lines=1
```

Press Enter to inspect a process and choose `k` to send SIGTERM, `j` to focus its
Herdr workspace, `r` to refresh, or `q` to quit. The picker also accepts Ctrl-K to
stop, Ctrl-J to jump, Ctrl-R to refresh, and Esc to quit.

Herdr navigation reads `HERDR_WORKSPACE_ID` and `HERDR_SOCKET_PATH` from the
selected process's environment and uses its socket when available. Linux uses
`/proc`; macOS uses `ps`. Missing or unreadable context disables navigation for
that process. Herdr reports stale workspace or unavailable session errors.

Only TCP listeners visible to your user are shown. Stopping a process affects
all ports it owns; it sends SIGTERM without sudo or an automatic forced kill.
