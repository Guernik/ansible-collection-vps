# guernik.vps

Ansible roles to set up and harden an Ubuntu or Debian VPS: SSH, users and keys,
firewall, auditd, fail2ban, unattended upgrades, optional mail notifications,
Docker and shell setup.

Built to be reused across unrelated projects, so the roles hold no
deployment-specific values. Every address, hostname and credential is a variable
with a neutral default; the real values live in the repository that consumes this
collection.

## Install

```sh
ansible-galaxy collection install guernik.vps
```

Or pin it from git in `collections/requirements.yml`:

```yaml
collections:
  - name: https://github.com/Guernik/ansible-collection-vps.git
    type: git
    version: v1.0.0
```

## Quickstart

Two variables are required: the users to create, and which of them Ansible should
switch to after bootstrapping.

```yaml
# group_vars/all.yml
vps_admin_user: admin
vps_users:
  admin:
    sudoer: true
    shell: fish
```

```yaml
# site.yml
- import_playbook: guernik.vps.harden
```

```sh
ansible-playbook -i inventory.yml site.yml
```

That gives a host with key-only SSH, a locked-down firewall, auditd, fail2ban and
unattended security upgrades, and no mail configured. Nothing else is assumed.

## How the bootstrap works

`guernik.vps.harden` runs in two stages, because it changes the account it
connects as:

1. **As root** (the only account a fresh image has): check the OS is supported,
   create the admin user and install its key, install packages, set the
   hostname, then harden sshd. sshd is hardened *last* in this stage, so the
   admin user is already able to log in before root password login disappears.
2. **As the admin user**, over sudo: everything else.

Between them the connection is reset, so the second stage genuinely reconnects as
the new user rather than reusing the root session. If the admin user was not
created correctly, the run fails there instead of leaving a host nobody can reach.

The playbook asserts up front that `vps_admin_user` names a `vps_users` entry with
`sudoer: true`. Without that, hardening would finish and lock you out.

On success it writes `/etc/vps-setup-done`. Later playbooks can require that
marker so an application is never deployed onto a host that was never hardened:

```yaml
- name: Require the host to be hardened
  ansible.builtin.stat:
    path: /etc/vps-setup-done
  register: marker
  failed_when: not marker.stat.exists
```

## Roles

| Role | Purpose | Default state |
| --- | --- | --- |
| `preflight` | refuse to run on an untested OS | on |
| `secure_sshd` | sshd hardening drop-in, validated with `sshd -t` before install | on |
| `hostname` | hostname, `/etc/hosts` mapping, machine name in `/etc/environment` | on |
| `users` | users, groups, SSH keys, sudo, docker group | on |
| `apt_packages` | a base set of CLI tooling | on |
| `auditd` | auditd and an audit ruleset | on |
| `firewall` | UFW; optional Cloudflare-only origin ports | on |
| `unattended_upgrades` | unattended security upgrades | on |
| `shell` | fish shell and helper functions | on |
| `postfix` | send-only SMTP relay client | **off** |
| `fail2ban` | UFW ban action; optional email alerts | on, alerts **off** |
| `logwatch` | daily emailed log digest | **off** |
| `login_alert` | email alert on SSH login, via PAM | **off** |
| `docker` | Docker Engine from Docker's APT repository | not in `harden.yml` |
| `server_status` | read-only host report | not in `harden.yml` |
| `cloudflared` | remotely-managed Cloudflare Tunnel connector | not in `harden.yml` |

`docker` is deliberately not part of `harden.yml`: a Kubernetes node already ships
containerd, and adding Docker there just adds an iptables and cgroup conflict
surface. Include it from your own playbook when you want it.

## Users and SSH keys

`vps_users` is a dict of username to options:

```yaml
vps_users:
  admin:
    sudoer: true        # passwordless sudo
    shell: fish         # installed on demand; bash, sh, zsh also understood
  deploy:
    docker: true        # added to the docker group
    authorized_keys:
      - "ssh-ed25519 AAAA... deploy@ci"
```

By default the `users` role **generates an ed25519 keypair per user on the control
machine**, under `~/.ssh/<inventory_hostname>/`, and installs the public half.
Existing keys are reused, so re-running does not rotate them. To rotate
deliberately:

```sh
ansible-playbook site.yml --tags users -e vps_rotate_ssh_keys=true
```

The previous directory is moved to `~/.ssh/<host>.old` first.

In CI, where a private key must not be written to the runner, turn generation off
and supply public keys instead:

```yaml
vps_generate_ssh_keys: false
vps_users:
  deploy:
    authorized_keys: ["{{ lookup('env', 'DEPLOY_PUBKEY') }}"]
```

Managed accounts have their password locked, and `authorized_keys` is exclusive by
default, so removing a key from `vps_users` actually revokes it.

## Mail notifications

Four roles can send mail: `fail2ban` (ban alerts), `logwatch` (daily digest),
`login_alert` (SSH logins) and `unattended_upgrades` (upgrade reports). All are
off by default, because a host with no relay configured cannot send anything and
silently broken alerting is worse than none.

Set the address once and enable what you want:

```yaml
vps_notify_email: ops@example.com
vps_notify_sender: alerts@example.com

vps_postfix_enabled: true
vps_postfix_relay_host: "[smtp.example.com]:587"
vps_postfix_sasl_user: relay@example.com
vps_postfix_sasl_pass: "{{ lookup('env', 'SMTP_PASSWORD') }}"

vps_fail2ban_mail_enabled: true
vps_logwatch_enabled: true
vps_login_alert_enabled: true
vps_unattended_mail_enabled: true
```

`vps_notify_email` feeds each role's own address variable
(`vps_fail2ban_destemail`, `vps_logwatch_email_to`, `vps_login_alert_email`,
`vps_unattended_mail`), so one setting covers all of them while any single one
can still be overridden. Enabling a role without an address is a hard error, not a
silent skip.

With mail off, fail2ban still bans - it just uses the plain UFW action.

## Secrets

This collection reads no secret store of its own. Secret-bearing variables
default to empty and are asserted non-empty only when the feature using them is
enabled, so how they are supplied is entirely the caller's choice:

```yaml
# environment variable (works with any wrapper: direnv, op run, infisical run, CI)
vps_postfix_sasl_pass: "{{ lookup('env', 'SMTP_PASSWORD') }}"

# ansible-vault
vps_postfix_sasl_pass: "{{ vaulted_smtp_password }}"

# a secret manager's own lookup plugin
vps_postfix_sasl_pass: "{{ lookup('community.hashi_vault.vault_kv2_get', 'smtp').secret.password }}"
```

`vps_postfix_sasl_pass` and `vps_cloudflared_tunnel_token` are the only secrets in
the collection. Both are written with `no_log`, at mode `0600`, and never appear
on a command line.

## Firewall

Denies inbound by default and allows only what is listed. SSH is the one
exception: the rule follows `vps_ssh_port`, which `secure_sshd` and `fail2ban`
read too, so moving the port moves all three together.

```yaml
vps_firewall_allowed_ports: [80, 443]

# reachable only from the private network, never the internet
vps_firewall_cluster_subnet: "10.0.0.0/24"
vps_firewall_cluster_ports: [4647, 4648]
```

Closing public SSH requires having another way in first - a rebuild reopens it:

```sh
ansible-playbook site.yml --tags firewall -e vps_firewall_ssh_enabled=false
```

### Cloudflare-only origin ports

Off unless `vps_firewall_cloudflare_ports` is set. When it is, those ports are
allowed **only** from Cloudflare's published ranges, so the origin cannot be
reached directly by IP and every request has to pass through Cloudflare:

```yaml
vps_firewall_cloudflare_ports: [8443]
```

Ranges are fetched at play time so the allowlist tracks Cloudflare adding
prefixes, falling back to a bundled list if the fetch fails.

## Variables

Each role documents its variables in `roles/<role>/defaults/main.yml`, with the
reasoning for the default. Everything is prefixed `vps_`. The ones worth knowing:

| Variable | Default | Notes |
| --- | --- | --- |
| `vps_users` | `{}` | Required. Empty is a hard error. |
| `vps_admin_user` | - | Required by `harden.yml`. Must be a sudoer in `vps_users`. |
| `vps_ssh_port` | `22` | Read by `secure_sshd`, `firewall` and `fail2ban`. |
| `vps_hostname` | `inventory_hostname` | |
| `vps_notify_email` | `""` | Feeds every mail-capable role. |
| `vps_notify_sender` | `""` | Envelope sender for alerts. |
| `vps_generate_ssh_keys` | `true` | Off in CI; supply `authorized_keys` instead. |
| `vps_rotate_ssh_keys` | `false` | Set true to rotate deliberately. |
| `vps_preflight_strict` | `true` | Set false to run on an untested release. |
| `vps_apt_packages` | see defaults | Replace wholesale, or add via `vps_apt_extra_packages`. |
| `vps_firewall_allowed_ports` | `[]` | |
| `vps_unattended_automatic_reboot` | `true` | Reboots at `vps_unattended_reboot_time` when an upgrade needs it. |

## Status report

```sh
ANSIBLE_STDOUT_CALLBACK=yaml ansible-playbook guernik.vps.status
```

Read-only: uptime, OS and kernel, memory, disk and inode usage, listening ports,
addresses, firewall state, failed units and service status.

## Supported platforms

Targets **Ubuntu 24.04 (noble)** and **Debian 12 (bookworm)**. Those are the
only releases listed, and the only ones support is claimed for.

Nothing in these roles branches on the distribution release, so Ubuntu 22.04 and
Debian 13 will very likely work - they are simply unverified. The `preflight`
role stops the run on anything unlisted, naming the release it found:

```sh
# opt into an untested release
ansible-playbook site.yml -e vps_preflight_strict=false
```

**Ubuntu 20.04 and older will not work.** The sshd config uses
`KbdInteractiveAuthentication`, which OpenSSH only understands from 8.7; 20.04
ships 8.2, which still calls it `ChallengeResponseAuthentication` and rejects
the drop-in. Overriding `vps_preflight_strict` does not change that.

Non-Debian families (RHEL, Alpine, Arch) are rejected unconditionally: every
role uses apt and Debian paths, so there is no partial-support path.

## Requirements

- ansible-core 2.16 or newer
- Ubuntu 24.04 or Debian 12 (see above)
- Root SSH access for the first run

Collection dependencies (`community.general`, `community.docker`,
`ansible.posix`) install automatically with the collection.

## License

MIT
