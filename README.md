# Scripts

Run `bash scripts/setup.sh enable` from the dotfiles root to link every top-level
`.sh` file except `setup.sh` and `setup-*.sh` into `~/.local/scripts`, removing the
`.sh` extension from command names. New scripts are picked up automatically on
the next run. Run `bash scripts/setup.sh disable` to remove those managed links.

## GPG backups

`backup-gpg.sh` exports a selected public/secret key pair and the keyring's global
owner trust, or imports them into the current keyring. It respects `GNUPGHOME`.
Requires Bash, GnuPG, tar, and (by default) `age`.

```sh
bash scripts/backup-gpg.sh backup KEY_ID /absolute/path/gpg-backup.tar.gz.age
bash scripts/backup-gpg.sh restore /absolute/path/gpg-backup.tar.gz.age

# Explicitly disable age encryption for both operations:
bash scripts/backup-gpg.sh --no-age backup KEY_ID /absolute/path/gpg-backup.tar.gz
bash scripts/backup-gpg.sh --no-age restore /absolute/path/gpg-backup.tar.gz
```

Age prompts for a passphrase when creating and restoring encrypted archives.
Output files are private (mode `600`) and existing files are never overwritten.
The output directory must already exist. Without `--no-age`, missing `age` is
an error, not a fallback to plaintext. Plain archives contain secret key material;
protect them yourself. Restore imports keys and owner trust into the active
keyring; use a separate `GNUPGHOME` to inspect a backup in isolation.

## Credential backups

`backup-creds backup <output-file>` archives `~/.ssh` and `~/.gnupg`,
encrypted with an `age` passphrase. Use `backup-creds restore <backup-file>`
to restore it; restoration overwrites matching files. Requires `age`. Without
installation, invoke `bash scripts/backup-creds.sh` with the same arguments.

## Package lists

```sh
save-installed-packages                         # ~/.local/state/system/, beside SYSTEM.md
save-installed-packages /absolute/path/packages # An explicit destination
```

Without installation, use `bash /path/to/dotfiles/scripts/save-installed-packages.sh`.
The default is `$HOME/.local/state/system`, beside this machine's `SYSTEM.md`,
not inside the repository. It does not depend on the checkout or working directory.
An explicit relative directory is resolved against the caller's working directory.
Missing directories are created, and the resolved absolute destination is printed.
Requires pacman and mise.

The script saves:

- `official-packages.txt`: explicitly installed official packages (`pacman -Qqen`).
- `aur-packages.txt`: explicitly installed foreign packages (`pacman -Qqem`);
  these include manually installed packages, not only AUR packages.
- `mise-packages.json`: all installed mise tool versions (`mise ls --installed --json`),
  including inactive versions and backend-managed tools such as npm packages.

All three queries must succeed before existing snapshots are replaced. Inventories
are machine-local records, not shared dotfiles.

## AUR AI review

`aur-ai-review.sh` is a report-only paru `FileManager`. Requires Bash, `less`,
an interactive terminal, `pi` with authenticated access to `openai/gpt-6.1-terra`,
and the user-installed `pi-web-access` package. It selects high thinking and explicitly loads the web
extension from `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/npm/node_modules/pi-web-access/dist/index.js`.
It does not build or install packages.

First run `bash scripts/setup.sh enable`. Then create `~/.config/paru/paru.conf`
(merge with an existing user config instead of overwriting it). Keep the linked
script path absolute; paru does not expand shell variables in `FileManagerFlags`:

```ini
Include = /etc/paru.conf

[bin]
FileManager = /usr/bin/bash
FileManagerFlags = /home/cjvnjde/.local/scripts/aur-ai-review
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
bash ~/.local/scripts/aur-ai-review ~/.cache/paru/clone/zen-browser-bin
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
