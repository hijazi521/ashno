# Security Policy

## Supported versions

Security fixes are applied to the latest `main` release. Users should keep Ashno and the Termux base packages current and should review profile and remote-dependency changes before applying them.

## Reporting a vulnerability

Please do not disclose an unpatched vulnerability in a public issue. Open a private security report through the repository’s GitHub security contact or contact the maintainer privately with the repository owner and revision.

Include the Ashno version, commit, Android and Termux versions, device architecture, enabled Termux repositories, a minimal reproduction, impact assessment, and logs with private keys, tokens, email addresses, and home-directory contents removed. Do not attach backup archives or SSH keys.

The maintainer should acknowledge a report within seven days, keep the reporter informed as remediation progresses, and publish a fix or mitigation with a clear release note when practical.

## Security design boundaries

Ashno runs with the current Termux user’s privileges. It can install packages, write user configuration, and create SSH keys after confirmation. It does not provide privilege escalation and should not be run from an untrusted checkout.

NPM lifecycle scripts are disabled by default. Remote Git dependencies are restricted to canonical URLs and pinned revisions. Backups are private by default, and SSH restoration is allowlisted and opt-in. These controls reduce risk but cannot make arbitrary third-party packages, repositories, or user-supplied archives trustworthy.
