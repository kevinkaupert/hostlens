#!/bin/bash
# =============================================================================
# lib.sh — Shared helper functions for all modules
# =============================================================================

# Check if a command is available
cmd_exists() { command -v "$1" &>/dev/null; }

# Escape a string for use in JSON
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Multi-line input → JSON array (one element per line, sorted)
lines_to_json_array() {
    local input="$1"
    local sorted="${2:-true}"   # optional: "false" to disable sorting
    local lines=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        lines+=("$(json_escape "$line")")
    done <<< "$input"

    [ "$sorted" = "true" ] && IFS=$'\n' lines=($(sort <<<"${lines[*]}")); unset IFS

    if [ ${#lines[@]} -eq 0 ]; then
        printf '[]'
        return
    fi

    local out="[\n"
    local first=true
    for item in "${lines[@]}"; do
        if [ "$first" = true ]; then
            out+="      \"$item\""
            first=false
        else
            out+=",\n      \"$item\""
        fi
    done
    out+="\n    ]"
    printf '%b' "$out"
}

# Object array from a pre-built comma-separated entries string
wrap_array() {
    local entries="$1"
    if [[ -z "$entries" ]]; then
        printf '[]'
    else
        printf '[%s]' "$entries"
    fi
}

# Append an entry to an entries string
append_entry() {
    local current="$1"
    local new="$2"
    if [[ -z "$current" ]]; then
        printf '%s' "$new"
    else
        printf '%s,%s' "$current" "$new"
    fi
}
