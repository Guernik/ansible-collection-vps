# Changelog

All notable changes to this collection are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - unreleased

First release. Extracted from a private single-host repository and generalized:

### Added

- `preflight` - refuse to run on an OS the collection does not support.
- `secure_sshd` - hardened sshd drop-in, validated with `sshd -t` before install.
- `hostname` - hostname, `/etc/hosts` mapping, machine name in `/etc/environment`.
- `users` - users, groups, SSH keys (generated locally or supplied), sudo, docker group.
- `apt_packages` - a base set of CLI tooling.
- `auditd` - auditd plus an audit ruleset.
- `docker` - Docker Engine from Docker's own APT repository.
- `firewall` - UFW, with optional Cloudflare-only origin ports.
- `postfix` - send-only SMTP relay client.
- `fail2ban` - UFW ban action, with optional email alerts.
- `logwatch` - daily emailed log digest.
- `unattended_upgrades` - unattended security upgrades.
- `login_alert` - email alert on SSH login, via PAM.
- `shell` - fish shell and helper functions.
- `server_status` - read-only host report.
- `cloudflared` - remotely-managed Cloudflare Tunnel connector.
- `playbooks/harden.yml` - base hardening, including the root to admin-user handoff.
- `playbooks/status.yml` - the status report.

### Supported platforms

Ubuntu 24.04 (noble) and Debian 12 (bookworm). Ubuntu 20.04 and older cannot be
supported: the sshd config needs OpenSSH 8.7+ for `KbdInteractiveAuthentication`.
