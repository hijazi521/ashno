# Ashno

**Ashno is a security-conscious toolkit installer and configurator for Termux.** It installs curated packages from profile files, configures common development tools, and provides validated private backups without hiding package-manager or filesystem side effects.

## Status

Ashno is maintained on the `main` branch. The current release version is stored in [`VERSION`](VERSION). The project is designed for modern Termux installations using the standard package repositories; package availability still varies by architecture and enabled repository.

## Safety first

Ashno changes the current Termux user’s packages and configuration files. Review the profile files before installation and run the program from a trusted checkout. The program does not enable Termux external command execution by default, does not execute a downloaded shell script for Oh-My-Zsh, and disables NPM lifecycle scripts unless explicitly requested.

Backups are written to private Termux storage by default. Private SSH keys are excluded from noninteractive backups and require an explicit interactive confirmation. Restore validates the archive layout, rejects symlinks and special files, limits archive resources, and writes only known configuration paths.

> Do not use old installer links that pipe a remote response directly into Bash. Use the repository-owned installer below or clone the repository and inspect it first.

## Installation

Install the repository-owned bootstrap script after reviewing it:

```bash
curl -fsSL https://raw.githubusercontent.com/hakinexus/ashno/main/install.sh -o install.sh
less install.sh
bash install.sh
```

The installer targets `https://github.com/hakinexus/ashno.git`, verifies an existing checkout’s remote, refuses local or divergent history, and uses fast-forward-only updates. For the strongest trust model, download a tagged release and verify its published checksum before running the installer.

For a fully inspectable local installation:

```bash
git clone https://github.com/hakinexus/ashno.git
cd ashno
chmod 755 ashno
./ashno --help
```

## Usage

Running without arguments opens the interactive menu:

```bash
ashno
```

Installation from a profile is explicit:

```bash
ashno --profile 1_essentials --pkg
ashno --profile 2_extended --all
ashno --profile 3_complete --npm --allow-npm-scripts
```

The command-line installer requires `--profile` plus exactly one of `--all`, `--pkg`, `--npm`, or `--pip`. Use `--no-update` when the checkout has already been reviewed and you do not want a pre-install update check.

| Command or option | Purpose |
|---|---|
| `--help`, `-h` | Show help without installing dependencies or contacting the network. |
| `--version` | Print the canonical release version. |
| `--profile NAME` | Select a profile directory under `profiles/`. Path traversal and symlinked profiles are rejected. |
| `--all` | Install PKG, NPM, and PIP entries from the selected cumulative profile. |
| `--pkg`, `--npm`, `--pip` | Install one package type. |
| `--configure`, `-c` | Open the interactive configuration menu. |
| `--backup`, `-b` | Create a private backup archive. |
| `--restore FILE` | Validate and restore an archive. |
| `--update`, `-u` | Check for and apply a verified fast-forward update. |
| `--non-interactive` | Disable prompts and keypress waits. It never includes SSH keys or installs restore packages by itself. |
| `--yes` | Required for destructive noninteractive restore operations. |
| `--restore-packages` | Explicitly permit package installation during a noninteractive restore. |
| `--restore-ssh` | Explicitly permit SSH-file restoration during a noninteractive restore. |
| `--allow-npm-scripts` | Opt in to NPM package lifecycle scripts. They are disabled by default. |
| `--no-update` | Skip the pre-install update check. |

Examples:

```bash
ashno --profile 2_extended --all --no-update
ashno --backup --non-interactive
ashno --restore "$HOME/.ashno-backup/ashno_backup_20260826_120000.tar.gz"
ashno --restore backup.tar.gz --non-interactive --yes --restore-packages --restore-ssh
```

## Profiles

Profiles are cumulative when their names begin with a numeric level. `2_extended` includes entries from `1_essentials`; `3_complete` includes entries from both lower levels. Full-line comments and inline comments after whitespace are supported.

```text
profiles/
  1_essentials/
    pkg.list
    npm.list
    pip.list
  2_extended/
    pkg.list
    npm.list
    pip.list
  3_complete/
    pkg.list
    npm.list
    pip.list
```

A custom profile may be added with a name containing letters, numbers, underscores, and hyphens. Each package manager reads one package token per line. Test a new profile in a disposable environment before using it on a primary device.

## Configuration

The configuration menu can set up ZSH, Starship, Git, Neovim, Termux terminal properties, and an Ed25519 SSH key pair. Existing files are backed up to the private `~/.ashno-backup` directory before replacement. Configuration writes use temporary files and fail closed when the backup or write cannot be completed.

Remote configuration dependencies are fetched from canonical URLs at pinned commits. The Neovim bootstrap pins the lazy.nvim release and verifies the clone and checkout before adding it to the runtime path. Plugin versions should be locked by the user through the generated lazy.nvim lockfile before relying on a long-lived environment.

The Termux configurator does not enable `allow-external-apps`. That property changes the command-execution boundary for third-party integrations and should be enabled manually only when a trusted integration requires it; see the [Termux RUN_COMMAND documentation](https://github.com/termux/termux-app/wiki/RUN_COMMAND-Intent).

## Backups and restore

Backups contain package metadata and selected configuration files. PIP and NPM metadata retain versions where the package manager exposes them. The archive is created with mode `600` in private Termux storage. SSH keys are a separate opt-in and should not be copied to shared Android storage or unencrypted cloud storage.

Restore is deliberately conservative. It accepts only the manifest, profile lists, known dotfiles, and the four supported SSH files. It rejects absolute paths, traversal, duplicate members, symlinks, hard links, device files, oversized archives, and malformed manifests. Package restoration is never implicit in noninteractive mode.

## Architecture

```text
ashno                 Entry point, argument parsing, dispatch, exit codes
src/config.sh         Version, paths, trust settings, limits, runtime state
src/utils.sh          UI helpers, validation, bounded execution, private logs
src/engine.sh         Profile parser, package installation, preflight checks
src/updater.sh        Canonical-remote and fast-forward update validation
src/menus.sh          Interactive menus, help, summaries
src/configure.sh      Safe configuration writers and pinned bootstraps
src/backup.sh         Private backup creation and conservative restore
profiles/             Cumulative PKG, NPM, and PIP package lists
install.sh            Repository-owned installation bootstrap
tests/run_tests.sh    Read-only and temporary-fixture regression tests
```

## Development

Run the local checks before opening a pull request:

```bash
bash -n ashno src/*.sh tests/run_tests.sh
shellcheck -x ashno src/*.sh tests/run_tests.sh
./tests/run_tests.sh
```

The tests use temporary directories and fake inputs; they do not install packages, change the real home directory, rotate real SSH keys, or execute remote installers.

## Security reporting

Please do not publish sensitive details in a public issue. Read [`SECURITY.md`](SECURITY.md) for the supported disclosure route and include the Ashno version, device architecture, Termux repository configuration, reproduction steps, and relevant logs with secrets removed.

## License

Ashno is released under the [MIT License](LICENSE).
