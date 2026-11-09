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

## AUR AI review

`aur-ai-review.sh` is a report-only paru `FileManager`. Requires Bash, `less`,
an interactive terminal, `pi` with authenticated access to `openai/gpt-6.1-terra`,
and the user-installed `pi-web-access` package. It selects high thinking and explicitly loads the web
extension from `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/npm/node_modules/pi-web-access/dist/index.js`.
It does not build or install packages.

To enable, create `~/.config/paru/paru.conf` (merge with an existing user config
instead of overwriting it). Keep the script path absolute; paru does not expand
shell variables in `FileManagerFlags`:

```ini
Include = /etc/paru.conf

[bin]
FileManager = /usr/bin/bash
FileManagerFlags = /home/cjvnjde/dotfiles/scripts/aur-ai-review.sh
```

Use `paru` normally. The review step first opens the original PKGBUILDs,
`.SRCINFO` files and available diffs in `less`, with line numbers. Use `:n`
for the next file, `:p` for the previous file, `/` to search, and `q` to finish
manual inspection and start the AI report.

The AI then reads the current packaging, related files and available diffs,
including packages supplied as AUR dependencies. It checks public upstream links
using the web tools and prints findings with citations and coverage limits.
Paru's `Accept changes?` prompt remains your
decision; the AI never answers it. Avoid `--noconfirm` and `--skipreview`, which
bypass paru's interactive review. An unsuccessful pi process aborts the review
instead of being treated as approval.

For standalone manual inspection followed by the AI report, run in a terminal:

```sh
bash ~/dotfiles/scripts/aur-ai-review.sh ~/.cache/paru/clone/zen-browser-bin
```

Only read/search/list and web tools are enabled. Shell, edit/write, MCP,
automatic extensions, skills, prompt templates and context-file loading are
disabled. The prompt treats package files and fetched pages as untrusted data.
This is not an OS sandbox: read tools can technically access files outside the
review directory. Package text is sent to the model provider, and web checks
contact external providers. Pi sessions are not saved; the web extension may
still cache content or clone upstream repositories.

The report is not a safety guarantee or an audit of downloaded binaries. To
disable, remove the `FileManager` and `FileManagerFlags` settings; if this was
your only user configuration, removing that file restores `/etc/paru.conf`.
