#!/bin/bash
# =============================================================================
# custom_sudoers.sh — Monitor sudo rules
#
# Why: New sudo rules (especially NOPASSWD) are a classic persistence
#      mechanism after a compromise.
# =============================================================================

collect_custom_sudoers() {
    local entries=""

    # Collect all sudoers files
    local sudoers_files=()
    [ -f "/etc/sudoers" ] && sudoers_files+=("/etc/sudoers")
    if [ -d "/etc/sudoers.d" ]; then
        while IFS= read -r f; do
            sudoers_files+=("$f")
        done < <(find /etc/sudoers.d -type f | sort)
    fi

    for f in "${sudoers_files[@]}"; do
        [ -r "$f" ] || continue
        while IFS= read -r line; do
            # Skip empty lines, comments, and pure includes
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            [[ "$line" =~ ^[[:space:]]*$ ]] && continue

            # Flag NOPASSWD — especially security-relevant
            local nopasswd="false"
            echo "$line" | grep -qi "NOPASSWD" && nopasswd="true"

            # Flag ALL=(ALL) ALL — full root access
            local full_root="false"
            echo "$line" | grep -qP "ALL\s*=\s*\(ALL" && full_root="true"

            local e
            e="{\"file\":\"$(json_escape "$f")\","
            e+="\"rule\":\"$(json_escape "$line")\","
            e+="\"nopasswd\":$nopasswd,"
            e+="\"full_root\":$full_root}"
            entries=$(append_entry "$entries" "$e")
        done < "$f"
    done

    wrap_array "$entries"
}
