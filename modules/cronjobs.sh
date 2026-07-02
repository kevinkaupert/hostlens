#!/bin/bash
# =============================================================================
# cronjobs.sh — System and user crontabs
# =============================================================================

collect_cronjobs() {
    local entries=""

    # System crontabs
    for f in /etc/crontab /etc/cron.d/*; do
        [ -f "$f" ] || continue
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            local e
            e="{\"source\":\"$(json_escape "$f")\",\"entry\":\"$(json_escape "$line")\"}"
            entries=$(append_entry "$entries" "$e")
        done < "$f"
    done

    # Root crontab
    if cmd_exists crontab; then
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            local e
            e="{\"source\":\"crontab:root\",\"entry\":\"$(json_escape "$line")\"}"
            entries=$(append_entry "$entries" "$e")
        done < <(crontab -l 2>/dev/null || true)
    fi

    wrap_array "$entries"
}
