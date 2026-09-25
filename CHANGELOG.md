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

### Testing

- Molecule scenarios: `logic` (host-free), `default` (Ubuntu 24.04), `bookworm`
  (Debian 12) and `dryrun` (check-mode-only roles), run in CI on every push.
- 14 of 16 roles are exercised. `auditd` and `docker` cannot run in a container;
  `cloudflared` needs a real tunnel, though its empty-token guard is tested.

### Fixed

- `secure_sshd` installs `openssh-server` and creates
  `/etc/ssh/sshd_config.d/`, so it works on a minimal image that ships only the
  client. It also creates `/run/sshd`, without which `sshd -t` validation fails
  on a host where sshd has never started.
- `server_status` uses `failed_when: false` rather than `ignore_errors`, so a
  missing tool is reported as absent instead of printing a failure in a
  read-only report.
- `server_status` sets `pipefail` on the pending-updates count. Without it a
  failing `apt list` still exited 0 through the pipe and the report claimed zero
  pending updates.

### Supported platforms

Ubuntu 24.04 (noble) and Debian 12 (bookworm). Ubuntu 20.04 and older cannot be
supported: the sshd config needs OpenSSH 8.7+ for `KbdInteractiveAuthentication`.
