#!/bin/bash
# =============================================================================
# render.sh — Converts snapshot.json to diff-friendly Markdown
#
# Format: one value per line, no tables — so git diff highlights exactly
# the affected line for small changes (e.g. new SSH key, container status
# change) instead of an entire table row.
#
# Usage:
#   ./render.sh [--no-timestamps] <snapshot.json> [output.md]
#
# Requires: jq
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Argument Parsing ──────────────────────────────────────────────────────────
NO_TIMESTAMPS=false
_args=()
for _arg in "$@"; do
    case "$_arg" in
        --no-timestamps) NO_TIMESTAMPS=true ;;
        *) _args+=("$_arg") ;;
    esac
done

SNAPSHOT="${_args[0]:-snapshot.json}"
OUTPUT="${_args[1]:-$SCRIPT_DIR/$(basename "$SNAPSHOT" .json).md}"

[ -f "$SNAPSHOT" ] || { echo "ERROR: Snapshot not found: $SNAPSHOT"; exit 1; }
command -v jq &>/dev/null || { echo "ERROR: jq is not installed"; exit 1; }

OUTPUT_DIR="$(dirname "$OUTPUT")"
[ "$OUTPUT_DIR" != "." ] && mkdir -p "$OUTPUT_DIR"
TMPFILE=$(mktemp)

jget() { jq -r "${1} // \"\"" "$SNAPSHOT" 2>/dev/null; }
jlen() { jq "${1} | length" "$SNAPSHOT" 2>/dev/null || echo 0; }

yn() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        yes|true)             echo "yes" ;;
        no|false)             echo "no" ;;
        prohibit-password)    echo "key-auth only" ;;
        *)                    echo "$1" ;;
    esac
}

{

# ── Meta ──────────────────────────────────────────────────────────────────────
cat << EOF
# $(jget '.meta.hostname')

EOF
[ "$NO_TIMESTAMPS" = false ] && echo "- collected_at: $(jget '.meta.collected_at')"
cat << EOF
- collector_version: $(jget '.meta.collector_version')
- running_as: $(jget '.meta.running_as')

---

## System

- os: $(jget '.system.os')
- kernel: $(jget '.system.kernel')
- arch: $(jget '.system.arch')
- virtualization: $(jget '.system.virtualization')
- uptime_seconds: $(jget '.system.uptime_seconds')

---

## Hardware

- vcpus: $(jget '.hardware.vcpus')
- cpu_model: $(jget '.hardware.cpu_model')
- ram_gb: $(jget '.hardware.ram_gb')

### Disks

EOF

jq -r '.hardware.disks[] |
    "#### \(.device)\n" +
    "- mount: \(.mount)\n" +
    "- size: \(.size)\n" +
    "- used: \(.used)\n" +
    "- avail: \(.avail)\n" +
    "- use_pct: \(.use_pct)\n"' "$SNAPSHOT" 2>/dev/null || echo "- none"

# ── Network ───────────────────────────────────────────────────────────────────
cat << EOF

---

## Network

- primary_ip: $(jget '.network.primary_ip')
- gateway: $(jget '.network.gateway')

### DNS Servers

EOF

jq -r '.network.dns_servers[] | "- \(.)"' "$SNAPSHOT" 2>/dev/null || echo "- none"

cat << EOF

### Interfaces

EOF

jq -r '.network.interfaces[] |
    "#### \(.name)\n" +
    "- address: \(.address)\n" +
    "- mac: \(.mac)\n"' "$SNAPSHOT" 2>/dev/null || echo "- none"

# ── Access ────────────────────────────────────────────────────────────────────
cat << EOF

---

## Access

- ssh_port: $(jget '.access.ssh_port')
- ssh_password_auth: $(yn "$(jget '.access.ssh_password_auth')")
- ssh_pubkey_auth: $(yn "$(jget '.access.ssh_pubkey_auth')")
- ssh_root_login: $(yn "$(jget '.access.ssh_root_login')")

---

## Users

EOF

jq -r '.users.users[] |
    "### \(.name)\n" +
    "- uid: \(.uid)\n" +
    "- shell: \(.shell)\n" +
    "- sudo: \(if .sudo then "yes" else "no" end)\n" +
    "- docker: \(if .docker then "yes" else "no" end)\n" +
    "- ssh_keys: \(.ssh_keys)\n"' "$SNAPSHOT" 2>/dev/null || echo "- none"

# ── SSH Keys ──────────────────────────────────────────────────────────────────
SSH_KEY_COUNT=$(jlen '.ssh_keys')
if [ "${SSH_KEY_COUNT:-0}" -gt 0 ] 2>/dev/null; then
cat << EOF

### SSH Authorized Keys

EOF
jq -r '.ssh_keys[] |
    "#### \(.user) — \(.comment)\n" +
    "- type: \(.type)\n" +
    "- fingerprint: \(.fingerprint)\n"' "$SNAPSHOT" 2>/dev/null
fi

# ── SSH Logins ────────────────────────────────────────────────────────────────
SSH_LOGINS_COUNT=$(jlen '.ssh_logins')
if [ "${SSH_LOGINS_COUNT:-0}" -gt 0 ] 2>/dev/null; then
cat << EOF

### SSH Logins (non-trusted sources)

EOF
jq -r '.ssh_logins[] |
    "- user=\(.user)  source=\(.source)  method=\(.method)"' \
    "$SNAPSHOT" 2>/dev/null
fi

# ── Ports ─────────────────────────────────────────────────────────────────────
cat << EOF

---

## Ports

### TCP

EOF

jq -r '.ports_tcp[] | "- \(.port)/tcp  bind=\(.bind)  process=\(.process)"' \
    "$SNAPSHOT" 2>/dev/null || echo "- none"

UDP_COUNT=$(jlen '.ports_udp')
if [ "${UDP_COUNT:-0}" -gt 0 ] 2>/dev/null; then
cat << EOF

### UDP

EOF
jq -r '.ports_udp[] | "- \(.port)/udp  bind=\(.bind)  process=\(.process)"' \
    "$SNAPSHOT" 2>/dev/null
fi

# ── Services ──────────────────────────────────────────────────────────────────
cat << EOF

---

## Systemd Services

EOF
jq -r '.services[] | "- \(.)"' "$SNAPSHOT" 2>/dev/null || echo "- none"

TIMER_COUNT=$(jlen '.timers')
if [ "${TIMER_COUNT:-0}" -gt 0 ] 2>/dev/null; then
cat << EOF

### Timers

EOF
jq -r '.timers[] |
    "#### \(.name)\n" +
    "- unit: \(.unit)\n" +
    "- next_run: \(.next_run)\n"' "$SNAPSHOT" 2>/dev/null
fi

# ── Docker ────────────────────────────────────────────────────────────────────
DOCKER_INSTALLED=$(jget '.docker.installed')

cat << EOF

---

## Docker

EOF

if [ "$DOCKER_INSTALLED" = "true" ]; then
cat << EOF
- version: $(jget '.docker.version')
- api_version: $(jget '.docker.api_version')
- compose_version: $(jget '.docker.compose_version')

### Compose Files

EOF
jq -r '.docker.compose_files[] | "- \(.)"' "$SNAPSHOT" 2>/dev/null || echo "- none"

cat << EOF

### Containers

EOF
jq -r '.docker.containers[] |
    "#### \(.name)\n" +
    "- image: \(.image)\n" +
    "- status: \(.status)\n" +
    "- compose_project: \(.compose_project)\n" +
    "- managed_by_compose: \(if .managed_by_compose then "yes" else "no" end)\n"' \
    "$SNAPSHOT" 2>/dev/null || echo "- none"

cat << EOF

### Networks

EOF
jq -r '.docker.networks[] | "- \(.name)  driver=\(.driver)  scope=\(.scope)"' \
    "$SNAPSHOT" 2>/dev/null || echo "- none"

cat << EOF

### Volumes

EOF
jq -r '.docker.volumes[] | "- \(.name)  driver=\(.driver)"' \
    "$SNAPSHOT" 2>/dev/null || echo "- none"

else
echo "- installed: no"
fi

# ── Firewall ──────────────────────────────────────────────────────────────────
cat << EOF

---

## Firewall & Security

- ufw_active: $(jget '.firewall.ufw_active')
- ufw_status: $(jget '.firewall.ufw_status')
- iptables_input_rules: $(jget '.firewall.iptables_input_rules')
- fail2ban_active: $(jget '.firewall.fail2ban_active')

### fail2ban Jails

EOF
jq -r '.firewall.fail2ban_jails[]? | "- \(.)"' "$SNAPSHOT" 2>/dev/null || echo "- none"

# ── Sudoers ───────────────────────────────────────────────────────────────────
SUDOERS_COUNT=$(jlen '.sudoers')
if [ "${SUDOERS_COUNT:-0}" -gt 0 ] 2>/dev/null; then
cat << EOF

### Sudo Rules

EOF
jq -r '.sudoers[] |
    "#### \(.file)\n" +
    "- rule: \(.rule)\n" +
    "- nopasswd: \(if .nopasswd then "yes [!]" else "no" end)\n" +
    "- full_root: \(if .full_root then "yes [!]" else "no" end)\n"' \
    "$SNAPSHOT" 2>/dev/null
fi

# ── SUID ──────────────────────────────────────────────────────────────────────
UNKNOWN_SUID=$(jq -r '.suid_binaries[]? | select(.known==false) | .path' "$SNAPSHOT" 2>/dev/null)
if [ -n "$UNKNOWN_SUID" ]; then
cat << EOF

### Unknown SUID Binaries [!]

EOF
jq -r '.suid_binaries[] | select(.known==false) |
    "#### \(.path)\n" +
    "- permissions: \(.permissions)\n" +
    "- owner: \(.owner)\n" +
    "- sha256: \(.sha256[0:16])...\n"' "$SNAPSHOT" 2>/dev/null
fi

# ── File Integrity ────────────────────────────────────────────────────────────
cat << EOF

---

## File Integrity

EOF
jq -r '.file_integrity[] |
    "#### \(.path)\n" +
    "- exists: \(if .exists then "yes" else "no" end)\n" +
    "- permissions: \(.permissions)\n" +
    "- owner: \(.owner)\n" +
    "- sha256: \(.sha256[0:16])...\n"' "$SNAPSHOT" 2>/dev/null || echo "- none"

# ── Certificates ──────────────────────────────────────────────────────────────
CERT_COUNT=$(jlen '.certificates')
if [ "${CERT_COUNT:-0}" -gt 0 ] 2>/dev/null; then
cat << EOF

---

## TLS Certificates

EOF
jq -r '.certificates[] |
    "#### \(.file | split("/") | last)\n" +
    "- subject: \(.subject)\n" +
    "- expiry: \(.expiry)\n" +
    "- days_left: \(.days_left)\n" +
    "- status: \(if .expired then "EXPIRED [!]" elif .expiring_soon then "EXPIRING SOON [!]" else "ok" end)\n"' \
    "$SNAPSHOT" 2>/dev/null
fi

# ── Cron Jobs ─────────────────────────────────────────────────────────────────
CRON_COUNT=$(jlen '.cronjobs')
if [ "${CRON_COUNT:-0}" -gt 0 ] 2>/dev/null; then
cat << EOF

---

## Cron Jobs

EOF
jq -r '.cronjobs[] | "- source=\(.source)  entry=\(.entry)"' \
    "$SNAPSHOT" 2>/dev/null
fi

# ── Updates ───────────────────────────────────────────────────────────────────
UPDATES=$(jget '.updates.packages_upgradable')
if [ -n "$UPDATES" ] && [ "$UPDATES" -gt 0 ] 2>/dev/null; then
    UPDATE_STATUS="[!] $UPDATES packages"
else
    UPDATE_STATUS="up to date"
fi

cat << EOF

---

## Updates

- packages_upgradable: ${UPDATE_STATUS}
- last_update: $(jget '.updates.last_update')

---

EOF
if [ "$NO_TIMESTAMPS" = false ]; then
    echo "*hostlens v$(jget '.meta.collector_version') — $(jget '.meta.collected_at')*"
else
    echo "*hostlens v$(jget '.meta.collector_version')*"
fi

} > "$TMPFILE"

if [ ! -s "$TMPFILE" ]; then
    rm -f "$TMPFILE"
    echo "ERROR: Render produced no output. Is jq installed and the snapshot valid?"
    exit 1
fi

mv "$TMPFILE" "$OUTPUT"
echo "Markdown saved: $OUTPUT"
