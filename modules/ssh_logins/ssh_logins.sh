#!/bin/bash
# =============================================================================
# ssh_logins/ssh_logins.sh — Tracks recent successful SSH logins
#
# Collects unique (user, source_ip, method) tuples from recent SSH logins.
# Logins from trusted sources are excluded (see trusted_sources.conf).
#
# Configuration:
#   trusted_sources.conf     — IPs / CIDR ranges to ignore (same directory)
#   SSH_LOGINS_LOOKBACK      — env var: how far back to search
#                              default: "30 days ago" (journalctl --since)
#
# Data sources (in order of preference):
#   1. journalctl -u sshd / -u ssh
#   2. /var/log/auth.log
#   3. /var/log/secure (RHEL/CentOS)
#
# Register in snapshot.sh:
#   source "$MODULES_DIR/ssh_logins/ssh_logins.sh"
#   "ssh_logins": $(collect_custom_ssh_logins),
# =============================================================================

_SSH_LOGINS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SSH_LOGINS_CONF="$_SSH_LOGINS_DIR/trusted_sources.conf"

SSH_LOGINS_LOOKBACK="${SSH_LOGINS_LOOKBACK:-30 days ago}"

# ── Load trusted sources from config file ─────────────────────────────────────
TRUSTED_SSH_SOURCES=()
if [[ -f "$_SSH_LOGINS_CONF" ]]; then
    while IFS= read -r _line; do
        # Strip inline comments and whitespace
        _line="${_line%%#*}"
        _line="${_line//[[:space:]]/}"
        [[ -z "$_line" ]] && continue
        TRUSTED_SSH_SOURCES+=("$_line")
    done < "$_SSH_LOGINS_CONF"
fi

# =============================================================================

# Convert IPv4 address string to a 32-bit integer
_ssh_ip4_to_int() {
    local ip="$1"
    local a b c d
    IFS='.' read -r a b c d <<< "$ip"
    echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

# Check if IPv4 $1 is within CIDR $2 (e.g. "192.168.1.0/24")
_ssh_ip4_in_cidr() {
    local ip="$1" cidr="$2"
    local net mask_bits ip_int net_int mask

    net="${cidr%/*}"
    mask_bits="${cidr#*/}"

    [[ "$mask_bits" =~ ^[0-9]+$ ]]              || return 1
    [[ "$ip"  =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    [[ "$net" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1

    ip_int=$(_ssh_ip4_to_int "$ip")
    net_int=$(_ssh_ip4_to_int "$net")
    mask=$(( 0xFFFFFFFF << (32 - mask_bits) & 0xFFFFFFFF ))

    [ $(( ip_int & mask )) -eq $(( net_int & mask )) ]
}

# Returns 0 (true) if the given IP matches any entry in TRUSTED_SSH_SOURCES
_ssh_is_trusted() {
    local ip="$1"
    local entry

    for entry in "${TRUSTED_SSH_SOURCES[@]+"${TRUSTED_SSH_SOURCES[@]}"}"; do
        [[ -z "$entry" ]] && continue
        if [[ "$entry" == */* ]]; then
            _ssh_ip4_in_cidr "$ip" "$entry" && return 0
        else
            [[ "$ip" == "$entry" ]] && return 0
        fi
    done
    return 1
}

# Parse syslog-style lines: "Accepted <method> for <user> from <ip> ..."
# Outputs: "<user> <ip> <method>" lines (unique, sorted)
_ssh_parse_syslog() {
    local raw="$1"
    echo "$raw" \
        | grep -oE 'Accepted [^ ]+ for [^ ]+ from [^ ]+' \
        | awk '{print $4, $6, $2}' \
        | sort -u
}

# Parse `last -i` output: lines where field 3 looks like an IPv4 address
# Outputs: "<user> <ip> ssh" lines (unique, sorted)
_ssh_parse_last() {
    last 2>/dev/null \
        | awk '$3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $1, $3, "ssh" }' \
        | sort -u
}

_ssh_collect_entries() {
    local entries=""
    while IFS=' ' read -r user source method; do
        [[ -z "$user" || -z "$source" ]] && continue
        _ssh_is_trusted "$source" && continue
        local e
        e="{\"user\":\"$(json_escape "$user")\","
        e+="\"source\":\"$(json_escape "$source")\","
        e+="\"method\":\"$(json_escape "$method")\"}"
        entries=$(append_entry "$entries" "$e")
    done
    echo "$entries"
}

collect_custom_ssh_logins() {
    local entries=""
    local raw=""

    # ── Try syslog-based sources ──────────────────────────────────────────────
    if command -v journalctl &>/dev/null; then
        raw=$(journalctl -u sshd -u ssh --since "$SSH_LOGINS_LOOKBACK" \
              -o cat --no-pager 2>/dev/null \
              | grep "Accepted " || true)
    fi

    if [[ -z "$raw" ]] && [[ -r /var/log/auth.log ]]; then
        raw=$(grep "Accepted " /var/log/auth.log 2>/dev/null || true)
    fi

    if [[ -z "$raw" ]] && [[ -r /var/log/secure ]]; then
        raw=$(grep "Accepted " /var/log/secure 2>/dev/null || true)
    fi

    # ── Build entries from syslog ─────────────────────────────────────────────
    if [[ -n "$raw" ]]; then
        entries=$(_ssh_parse_syslog "$raw" | _ssh_collect_entries)
        wrap_array "$entries"
        return
    fi

    # ── Fall back to last (wtmp / wtmpdb) ─────────────────────────────────────
    if command -v last &>/dev/null; then
        entries=$(_ssh_parse_last | _ssh_collect_entries)
        wrap_array "$entries"
        return
    fi

    wrap_array ""
}
