# hostlens

Bash tool that snapshots VM state as JSON and commits it to Git. Run `git diff` to see what changed structurally between runs.

![License](https://img.shields.io/badge/license-MIT-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)

## Why

Traditional monitoring tools track metrics. They don't tell you that someone added a user last Tuesday, or why port 8080 appeared, or which sudo rule wasn't there last week.

hostlens takes a JSON snapshot of a server's current state on a schedule and commits it. Git handles the diffing and history.

```diff
# three weeks later:
+  {"name":"newuser","uid":1002,"sudo":false,"ssh_keys":1},

+  {"port":8080,"bind":"0.0.0.0","process":"python3"},

-  {"name":"nginx","status":"running"},
+  {"name":"nginx","status":"exited"},
```

Benefits of using Git as the storage layer:

- Every structural change is committed with a timestamp
- `git diff` shows exactly what changed between any two points in time
- Push webhooks integrate with Gitea, GitHub, or any notification system
- No extra infrastructure beyond Bash, Git, and a cronjob

## What Gets Captured

| Module | What it tracks |
|---|---|
| `system` | OS, kernel, virtualization type |
| `hardware` | vCPUs, RAM, disk usage per partition |
| `network` | IPs, interfaces, MAC addresses, gateway, DNS |
| `users` | Login users, UID, sudo/docker group membership, SSH key count |
| `ports_tcp` | Listening TCP ports with process names |
| `ports_udp` | Listening UDP ports (VPN, DNS, NTP...) |
| `services` | Running systemd services |
| `timers` | Systemd timers |
| `cronjobs` | System and user crontabs |
| `docker` | Containers (running and stopped), compose projects, networks, volumes |
| `firewall` | UFW status, iptables rule count, fail2ban jails |
| `updates` | Pending package upgrades |
| `packages` | Installed packages with versions |
| `ssh_keys` | Authorized key fingerprints per user |
| `ssh_logins` | Recent successful SSH logins from non-trusted sources |
| `sudoers` | All sudo rules, NOPASSWD entries flagged |
| `suid_binaries` | SUID/SGID binaries with SHA256, unknown ones flagged |
| `kernel_modules` | Loaded kernel modules, unknown ones flagged |
| `file_integrity` | SHA256 checksums of critical system files |
| `certificates` | TLS certificate expiry dates |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  VM / Server                                        │
│                                                     │
│  snapshot.sh                                        │
│  ├── modules/system.sh                              │
│  ├── modules/users.sh                               │
│  ├── modules/docker.sh                              │
│  ├── modules/custom_sshkeys.sh                      │
│  ├── modules/ssh_logins/ssh_logins.sh               │
│  └── ...                                            │
│       │                                             │
│       ▼                                             │
│  snapshot.json  ──→  git commit  ──→  git push      │
└──────────────────────────────┬──────────────────────┘
                               │
                               ▼
                    ┌──────────────────┐
                    │  Gitea / GitHub  │
                    │                  │
                    │  git diff        │
                    │  commit history  │
                    │  webhooks ──────────→ Ntfy / Telegram
                    └──────────────────┘
```

## Quick Start

### 1. Clone

```bash
git clone https://github.com/kevinkaupert/hostlens.git
cd hostlens
chmod +x collect-and-push.sh
```

### 2. Run

```bash
# Snapshot, render Markdown, commit and push — all in one step
sudo ./collect-and-push.sh

# On first run with no repo configured, you will be prompted for a remote URL:
#   [hostlens] Remote URL (SSH or HTTP, leave empty to skip): ssh://git@gitea.example.com:222/you/vm-snapshots.git
#
# If the remote already has commits (e.g. from other hosts), you will be asked
# whether to reset to the remote state, force-push, or skip.
```

Pass the remote URL directly to skip the prompt:

```bash
sudo ./collect-and-push.sh --remote ssh://git@gitea.example.com:222/you/vm-snapshots.git
```

### 3. Automate with cron

```bash
# runs every 6 hours, logs to /var/log/hostlens.log
0 */6 * * * root /opt/hostlens/collect-and-push.sh >> /var/log/hostlens.log 2>&1
```

## Adding a Custom Module

1. Copy the template:
```bash
cp modules/custom_TEMPLATE.sh modules/custom_mymodule.sh
```

2. Implement the `collect_custom_mymodule()` function:
```bash
collect_custom_mymodule() {
    local entries=""
    # ... collect data ...
    wrap_array "$entries"
}
```

3. Add to `snapshot.sh`:
```bash
source "$MODULES_DIR/custom_mymodule.sh"

# in the JSON block:
"mymodule": $(collect_custom_mymodule),
```

## SSH Login Monitoring

The `ssh_logins` module tracks recent successful SSH logins and filters out logins from trusted sources (your management network, VPN gateway, etc.). Only unexpected logins appear in the snapshot and trigger a `[WARN]` in the Git commit message.

### Configuration

Edit `modules/ssh_logins/trusted_sources.conf`:

```
# One entry per line. Comments and blank lines are ignored.

# Exact IP
10.0.0.1

# CIDR range
192.168.1.0/24
10.8.0.0/16
```

The lookback window defaults to 30 days and can be overridden:

```bash
SSH_LOGINS_LOOKBACK="7 days ago" sudo -E ./collect-and-push.sh
```

### Commit message output

New logins from unknown sources appear as warnings in the commit message:

```
[WARN] ssh-login: deploy@203.0.113.42 (publickey)
```

Logins that disappear from the log window are recorded as removals:

```
- ssh-login: deploy@203.0.113.42 (publickey)
```

### File structure

```
modules/ssh_logins/
├── ssh_logins.sh          # module logic
└── trusted_sources.conf   # trusted IPs / CIDR ranges
```

## Module Design

Modules follow a few rules to keep Git diffs readable:

- JSON arrays have one item per line so each change shows up as a single diff line
- Output is sorted alphabetically or numerically to avoid noise from reordering
- Volatile values like uptime stay out of tracked fields
- Field names are stable across versions

## Requirements

- Bash 4.0+
- Standard Linux tools: `ip`, `ss`, `systemctl`, `find`, `stat`, `sha256sum`
- `openssl` (for certificate monitoring)
- `docker` (for Docker module, optional)
- `git`

Tested on Ubuntu 22.04, Ubuntu 24.04, Debian 12.

## Integration

### Ntfy

```bash
if ! git diff --cached --quiet; then
  CHANGES=$(git diff --cached --stat | tail -1)
  curl -s -d "$(hostname): $CHANGES" https://ntfy.example.com/vm-alerts
fi
```

### Gitea / GitHub Webhooks

Configure a webhook to point at your notification endpoint. Every push sends a notification with the diff summary.

## Security Notes

- Run with `sudo` for complete coverage (SUID scan, `/etc/shadow`)
- Snapshot JSON can contain sensitive data. Keep the repository private.
- SSH key fingerprints are stored, not full key material.
- Consider encrypting snapshots if stored on untrusted infrastructure.

## Markdown Rendering

`render.sh` converts a snapshot to a Markdown document, useful for wikis or internal documentation.

Requires `jq`:
```bash
apt install jq
```

### Usage

```bash
# Output defaults to <snapshot-name>.md
./render.sh snapshot.json

# Specify output file
./render.sh snapshot.json server-docs.md

# Suppress collected_at timestamps (useful for diffing renders across time)
./render.sh --no-timestamps snapshot.json

# Full snapshot then render
sudo ./snapshot.sh snapshot.json && ./render.sh snapshot.json docs/$(hostname).md
```

`--no-timestamps` removes the `collected_at` field from the header and footer. Useful when the rendered Markdown is itself stored in Git and you don't want every run to produce a diff.

### What gets rendered

| Section | Content |
|---|---|
| System | OS, kernel, arch, virtualization |
| Hardware | vCPUs, CPU model, RAM, disk usage per partition |
| Network | Primary IP, gateway, DNS, all interfaces with MAC |
| Access | SSH port, password auth, pubkey auth, root login |
| Users | UID, shell, sudo/docker group, SSH key count |
| SSH Keys | Authorized key fingerprints per user |
| SSH Logins | Recent successful logins from non-trusted sources |
| TCP/UDP Ports | Listening ports with process names |
| Services | Running systemd services |
| Systemd Timers | Active timers with next run time |
| Docker | Engine version, containers, networks, volumes, compose files |
| Firewall | UFW status, iptables rule count, fail2ban jails |
| Sudoers | All sudo rules, NOPASSWD and full-root entries flagged |
| SUID Binaries | Unknown SUID/SGID binaries flagged |
| File Integrity | SHA256 checksums of critical system files |
| Certificates | TLS cert expiry with warnings for entries expiring within 30 days |
| Cron Jobs | System and user crontabs |
| Updates | Pending package count, last apt update |

### Example output

```markdown
# Host Documentation: `myserver.example.com`

> Auto-generated on 2025-04-28T10:00:00Z by hostlens

## Hardware
| Component | Value |
|---|---|
| CPU | 2 vCPU (Intel Core i7) |
| RAM | 4.0 GB |

## Users
| User | UID | Shell | Sudo | Docker | SSH Keys |
|---|---|---|---|---|---|
| deploy | 1001 | /bin/bash | no | yes | 1 |
| admin | 1000 | /bin/bash | yes | yes | 2 |
```

## Full Workflow

`collect-and-push.sh` runs all three steps in order: snapshot, render, commit and push.

### CLI flags

```bash
sudo ./collect-and-push.sh [OPTIONS]

  -r, --remote <url>     Remote URL to configure on first run
  -d, --repo-dir <path>  Override the Git repo directory
```

### Environment variables

All paths and options can also be set via environment variables:

| Variable | Default | Description |
|---|---|---|
| `GIT_REMOTE_URL` | — | Remote URL (alternative to `--remote`) |
| `REPO_DIR` | `<script-dir>/repo` | Git repo where snapshots are committed |
| `SNAPSHOT_FILE` | `/tmp/<hostname>.snapshot.json` | Temporary snapshot path |
| `RENDER_MARKDOWN` | `true` | Set to `false` to skip Markdown rendering |
| `NTFY_URL` | (disabled) | Ntfy endpoint for push notifications |
| `TELEGRAM_TOKEN` | (disabled) | Telegram bot token |
| `TELEGRAM_CHAT_ID` | (disabled) | Telegram chat ID |

```bash
# Specify remote via flag
sudo ./collect-and-push.sh --remote ssh://git@gitea.example.com:222/you/vm-snapshots.git

# Specify remote via environment variable
GIT_REMOTE_URL=ssh://git@gitea.example.com:222/you/vm-snapshots.git sudo -E ./collect-and-push.sh

# Store snapshots in a custom directory
sudo ./collect-and-push.sh --repo-dir /opt/vm-snapshots

# With Ntfy notification
NTFY_URL=https://ntfy.example.com/vm-alerts sudo -E ./collect-and-push.sh

# Skip Markdown rendering
RENDER_MARKDOWN=false sudo -E ./collect-and-push.sh

# As cronjob (every 6 hours)
0 */6 * * * root /opt/hostlens/collect-and-push.sh >> /var/log/hostlens.log 2>&1
```

### First-run behavior

On the first run, if no Git repo exists yet, `collect-and-push.sh` creates one automatically. If no remote URL is provided and the script is running interactively (not in cron), it prompts:

```
[hostlens] Remote URL (SSH or HTTP, leave empty to skip): ssh://git@...

  The remote already has commits (e.g. from other hosts).
  What would you like to do?
  1) Reset to remote state — recommended, keeps other hosts' data
  2) Force-push local state — overwrites remote history
  3) Skip push — local commits only for now
  Choice [1]:
```

In non-interactive mode (cron), option 1 is chosen automatically.

### Push behavior

Before every push, hostlens fetches and rebases onto the remote branch. If the rebase fails due to divergent history (e.g. the repo was re-initialized), it resets to the remote state and re-applies the current snapshot cleanly — no manual intervention needed.

`render.sh` also accepts an optional output path as second argument:

```bash
# Default: saves next to the script
./render.sh snapshot.json

# Custom output path
./render.sh snapshot.json /path/to/output.md
```

## License

MIT — see [LICENSE](LICENSE)

## Contributing

PRs welcome. When adding a module, follow the design rules above and include a comment explaining what the data is useful for.
