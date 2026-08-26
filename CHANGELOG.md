# Changelog

## 1.10.1 — Security and reliability hardening

This release makes the command-line interface side-effect-free for help and version queries, validates profile names, fixes inline profile comments, preserves command failures, and adds bounded private logs. Package installation now uses argument arrays and disables NPM lifecycle scripts by default.

Self-updates verify the canonical remote, reject local-ahead and divergent history, require fast-forward-only pulls, and verify the resulting revision before restart. Configuration writes are atomic and backup-before-delete, remote configuration repositories use pinned commits, and font downloads use private temporary files with a pinned checksum.

Backups now default to private Termux storage, use mode 600, preserve available package versions, and protect custom names from collisions. Restore validates manifests and archive paths, rejects links and special files, enforces resource limits, replaces directories correctly, and requires explicit scope flags for noninteractive package or SSH restoration. Unsupported default package names were removed from the standard profiles.

The repository now includes regression tests, ShellCheck/CI configuration, a security policy, and documentation that matches the implementation.
