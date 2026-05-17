#!/bin/bash
# =============================================================================
# updates.sh — Package update status
# =============================================================================

collect_updates() {
    local upgradable=0 last_update=""

    if cmd_exists apt; then
        upgradable=$(apt list --upgradable 2>/dev/null | grep -c "/" 2>/dev/null) || upgradable=0
        last_update=$(stat -c %y /var/cache/apt/pkgcache.bin 2>/dev/null \
            | cut -d'.' -f1 || echo "")
    elif cmd_exists yum || cmd_exists dnf; then
        local mgr="dnf"
        cmd_exists dnf || mgr="yum"
        upgradable=$($mgr check-update --quiet 2>/dev/null | grep -c "^[a-zA-Z]" 2>/dev/null) || upgradable=0
    fi

    cat << EOF
{
    "packages_upgradable": $upgradable,
    "last_update": "$(json_escape "$last_update")"
  }
EOF
}
