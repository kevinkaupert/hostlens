#!/bin/bash
# =============================================================================
# ports.sh — Listening TCP ports
# =============================================================================

collect_ports() {
    local entries=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local addr proc port bind process
        addr=$(echo "$line" | awk '{print $4}')
        proc=$(echo "$line" | awk '{print $6}')
        port=$(echo "$addr" | grep -oP ':\K[0-9]+$' || echo "")
        [[ -z "$port" ]] && continue
        bind=$(echo "$addr" | sed "s/:${port}$//")
        process=$(echo "$proc" | grep -oP '"[^"]*"' | head -1 | tr -d '"' || echo "")

        local e
        e="{\"port\":$port,\"bind\":\"$(json_escape "$bind")\",\"process\":\"$(json_escape "$process")\"}"
        entries=$(append_entry "$entries" "$e")
    done < <(ss -tlnp 2>/dev/null | grep LISTEN | sort -t: -k2 -n)

    wrap_array "$entries"
}
