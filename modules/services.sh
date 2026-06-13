#!/bin/bash
# =============================================================================
# services.sh — Running systemd services
# Filters out system noise, shows only relevant user-facing services
# =============================================================================

# Services always filtered out (system noise)
SERVICES_FILTER="^(sys-|user@|getty@|dbus|NetworkManager|polkit|rsyslog|cron|atd|"
SERVICES_FILTER+="accounts-daemon|avahi|bluetooth|colord|cups|ModemManager|"
SERVICES_FILTER+="systemd-|snapd|ufw|unattended-upgrades|apt-daily|"
SERVICES_FILTER+="e2scrub|fstrim|man-db|motd)"

collect_services() {
    local raw
    raw=$(systemctl list-units --type=service --state=running \
        --no-pager --no-legend 2>/dev/null \
        | awk '{print $1}' \
        | grep -vE "$SERVICES_FILTER" \
        | sort || echo "")

    lines_to_json_array "$raw"
}
