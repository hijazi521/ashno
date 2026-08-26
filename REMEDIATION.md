# Audit Remediation Record

## Scope

This branch applies the remediation work from the Ashno audit at commit `0968e8c11613798244db3a14c8704bed3a4d5842`. The working tree is intended to remain usable on standard Termux installations while failing closed around updates, archives, sensitive files, and destructive configuration changes.

## Fixed areas

| Original area | Remediation |
|---|---|
| Mismatched one-line installer | Added a repository-owned `install.sh` targeting the canonical `hakinexus/ashno` remote and removed the legacy installer reference from project documentation. |
| Unverified self-update | Added canonical-remote validation, branch checks, ancestry checks, fast-forward-only pulls, local-ahead handling, retained update logs, and post-pull revision verification. |
| Import-time package side effects | `--help` and `--version` now load no package manager and perform no network or filesystem setup. |
| Profile parser and path escape | Added inline-comment parsing, malformed-token filtering, strict profile names, realpath containment checks, and deterministic cumulative-level resolution. |
| Package correctness and idempotence | Corrected unsupported default PKG names, replaced invalid registry entries, added version-aware presence checks, and disabled NPM lifecycle scripts by default. |
| Configuration data loss | Configuration writers back up before replacement, use atomic writes, and refuse to delete Neovim state when the backup fails. |
| Remote configuration dependencies | Replaced the remote Oh-My-Zsh installer shell execution with pinned Git checkouts and pinned the generated Neovim bootstrap/plugins to reviewed commits. |
| Predictable font temporary file | Uses private `mktemp` files and a pinned SHA-256 digest before extraction. |
| SSH key rotation | Handles stale private/public pairs, backs up both existing files, generates into a temporary path, and moves the new pair into place only after success. |
| Backup confidentiality | Defaults to private `~/.ashno-backup`, uses mode 600, preserves package versions where available, and makes SSH-key inclusion explicit. |
| Restore archive safety | Validates archive size, member count, expanded size, manifest schema, path allowlists, duplicates, file types, and extraction status. Restore writes only known paths and handles directories without nesting. |
| Noninteractive restore safety | Requires `--yes`; package installation requires `--restore-packages`; SSH restoration requires `--restore-ssh`. |
| CLI status correctness | Command actions return their actual failure status instead of unconditional zero. |
| Diagnostics and hangs | Centralized bounded command execution, private retained logs, and consistent failure reporting. |
| Quality controls | Added regression tests, CI, ShellCheck coverage, a security policy, a single version file, and updated documentation. |

## Verification

The release-candidate gate passed `git diff --check`, Bash syntax checks for `ashno`, `install.sh`, all source modules, and tests, ShellCheck with no diagnostics, all 9 regression tests, side-effect-free help/version smoke tests, missing-restore nonzero-status checks, and a current official Termux-index comparison with zero absent default PKG names.

The tests use temporary directories and isolated Git fixtures. They do not install packages, modify the real home directory, rotate real SSH keys, execute remote installers, or push changes to GitHub.

## Operational limitations

The installer still runs with the current Termux user’s privileges, and package managers and pinned Git dependencies remain external software. Users should review profile and dependency changes before applying them. The updater uses canonical HTTPS remote validation and fast-forward-only history; cryptographic commit verification can be enabled by setting a trusted signing key in the runtime environment, but no signing key is embedded in the repository because the project’s current main history is unsigned.
