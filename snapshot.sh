#!/bin/bash
# =============================================================================
# snapshot.sh — HostLens
#
# Captures the full current state of a VM as structured JSON.
# Optimized for Git diffs: sorted arrays, stable structure, no
# volatile values in tracked fields.
#
# Usage:
#   ./snapshot.sh [output.json]
#   sudo ./snapshot.sh         → for full SUID/shadow capture
#
# Adding a new module:
#   1. Create modules/custom_mymodule.sh
#   2. Implement collect_custom_mymodule()
#   3. Add source + JSON entry below
# =============================================================================

set -uo pipefail

SCRIPT_VERSION="2.0.0"
OUTPUT_FILE="${1:-snapshot.json}"
MODULES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/modules" && pwd)"

# ── Core Modules ──────────────────────────────────────────────────────────────
source "$MODULES_DIR/lib.sh"
source "$MODULES_DIR/system.sh"
source "$MODULES_DIR/hardware.sh"
source "$MODULES_DIR/network.sh"
source "$MODULES_DIR/users.sh"
source "$MODULES_DIR/ports.sh"
source "$MODULES_DIR/services.sh"
source "$MODULES_DIR/docker.sh"
source "$MODULES_DIR/firewall.sh"
source "$MODULES_DIR/cronjobs.sh"
source "$MODULES_DIR/updates.sh"

# ── Extension Modules ─────────────────────────────────────────────────────────
source "$MODULES_DIR/custom_sshkeys.sh"
source "$MODULES_DIR/custom_sudoers.sh"
source "$MODULES_DIR/custom_suid.sh"
source "$MODULES_DIR/custom_packages.sh"
source "$MODULES_DIR/custom_timers.sh"
source "$MODULES_DIR/custom_files.sh"
source "$MODULES_DIR/custom_certificates.sh"
source "$MODULES_DIR/custom_kernel_modules.sh"
source "$MODULES_DIR/custom_udp_ports.sh"
source "$MODULES_DIR/ssh_logins/ssh_logins.sh"

# ── Metadata ──────────────────────────────────────────────────────────────────
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
COLLECTED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
RUNNING_AS=$(whoami)

# ── SSH Configuration ─────────────────────────────────────────────────────────
_ssh_port=$(grep -E "^Port "                  /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "22")
_ssh_pw=$(grep -E "^PasswordAuthentication "  /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "unknown")
_ssh_pk=$(grep -E "^PubkeyAuthentication "    /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "unknown")
_ssh_root=$(grep -E "^PermitRootLogin "       /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo "unknown")

# ── Build JSON ────────────────────────────────────────────────────────────────
cat > "$OUTPUT_FILE" << EOF
{
  "meta": {
    "hostname": "$(json_escape "$HOSTNAME")",
    "collected_at": "$COLLECTED_AT",
    "collector_version": "$SCRIPT_VERSION",
    "running_as": "$(json_escape "$RUNNING_AS")"
  },
  "system": $(collect_system),
  "hardware": $(collect_hardware),
  "network": $(collect_network),
  "access": {
    "ssh_port": "$_ssh_port",
    "ssh_password_auth": "$_ssh_pw",
    "ssh_pubkey_auth": "$_ssh_pk",
    "ssh_root_login": "$_ssh_root"
  },
  "users": $(collect_users),
  "ports_tcp": $(collect_ports),
  "ports_udp": $(collect_custom_udp_ports),
  "services": $(collect_services),
  "timers": $(collect_custom_timers),
  "cronjobs": $(collect_cronjobs),
  "docker": $(collect_docker),
  "firewall": $(collect_firewall),
  "updates": $(collect_updates),
  "packages": $(collect_custom_packages),
  "ssh_keys": $(collect_custom_sshkeys),
  "sudoers": $(collect_custom_sudoers),
  "suid_binaries": $(collect_custom_suid),
  "kernel_modules": $(collect_custom_kernel_modules),
  "file_integrity": $(collect_custom_files),
  "certificates": $(collect_custom_certificates),
  "ssh_logins": $(collect_custom_ssh_logins)
}
EOF

echo "Snapshot saved: $OUTPUT_FILE"
echo "  Hostname:  $HOSTNAME"
echo "  Timestamp: $COLLECTED_AT"
echo "  Running as: $RUNNING_AS"
