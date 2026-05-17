#!/bin/bash
# =============================================================================
# firewall.sh — UFW, iptables, fail2ban
# =============================================================================

collect_firewall() {
    local ufw_active="false" ufw_status="" iptables_rules=0
    local fail2ban_active="false" fail2ban_jails_raw=""

    if cmd_exists ufw; then
        local raw
        raw=$(ufw status 2>/dev/null | head -1 || echo "")
        ufw_status="$(json_escape "$raw")"
        echo "$raw" | grep -qi "active" && ufw_active="true"
    fi

    if cmd_exists iptables; then
        iptables_rules=$(iptables -L INPUT --line-numbers 2>/dev/null \
            | grep -c "^[0-9]" 2>/dev/null) || iptables_rules=0
    fi

    if cmd_exists fail2ban-client; then
        fail2ban_active="true"
        fail2ban_jails_raw=$(fail2ban-client status 2>/dev/null \
            | grep "Jail list" | cut -d: -f2 \
            | tr ',' '\n' | xargs -n1 2>/dev/null | sort || echo "")
    fi

    cat << EOF
{
    "ufw_active": $ufw_active,
    "ufw_status": "$ufw_status",
    "iptables_input_rules": $iptables_rules,
    "fail2ban_active": $fail2ban_active,
    "fail2ban_jails": $(lines_to_json_array "$fail2ban_jails_raw")
  }
EOF
}
