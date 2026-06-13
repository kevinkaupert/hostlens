#!/bin/bash
# =============================================================================
# custom_timers.sh — Monitor systemd timers
#
# Why: Many modern tools use systemd timers instead of crontabs.
#      Unknown timers can indicate unwanted scheduled actions.
# =============================================================================

collect_custom_timers() {
    local entries=""

    # systemd not available
    cmd_exists systemctl || { wrap_array ""; return; }

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local timer_name next last unit
        timer_name=$(echo "$line" | awk '{print $1}')
        next=$(echo "$line"      | awk '{print $2, $3}')
        last=$(echo "$line"      | awk '{print $4, $5}')
        unit=$(echo "$line"      | awk '{print $6}')

        # Find timer file for more details
        local timer_file
        timer_file=$(systemctl show "$timer_name" 2>/dev/null \
            | grep "^FragmentPath=" | cut -d'=' -f2 || echo "")

        # Description from unit file
        local description
        description=$(systemctl show "$timer_name" --property=Description 2>/dev/null \
            | cut -d'=' -f2 || echo "")

        local e
        e="{\"name\":\"$(json_escape "$timer_name")\","
        e+="\"unit\":\"$(json_escape "$unit")\","
        e+="\"description\":\"$(json_escape "$description")\","
        e+="\"next_run\":\"$(json_escape "$next")\","
        e+="\"last_run\":\"$(json_escape "$last")\","
        e+="\"file\":\"$(json_escape "$timer_file")\"}"
        entries=$(append_entry "$entries" "$e")
    done < <(systemctl list-timers --all --no-pager --no-legend 2>/dev/null \
        | grep -v "^$" | sort -k1)

    wrap_array "$entries"
}
