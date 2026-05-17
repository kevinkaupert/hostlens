#!/bin/bash
# =============================================================================
# custom_packages.sh — Installed packages with versions
#
# Why: Detects manually installed software that isn't documented.
#      Git diff immediately shows newly installed or removed packages.
#      Supports apt (Debian/Ubuntu) and rpm (RHEL/CentOS/Fedora).
# =============================================================================

collect_custom_packages() {
    local entries=""

    if cmd_exists dpkg; then
        # Debian/Ubuntu — installed packages only, sorted by name
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local name version arch
            name=$(echo "$line"    | awk '{print $1}' | cut -d':' -f1)
            version=$(echo "$line" | awk '{print $2}')
            arch=$(echo "$line"    | awk '{print $3}')

            local e
            e="{\"name\":\"$(json_escape "$name")\","
            e+="\"version\":\"$(json_escape "$version")\","
            e+="\"arch\":\"$(json_escape "$arch")\","
            e+="\"manager\":\"dpkg\"}"
            entries=$(append_entry "$entries" "$e")
        done < <(dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' 2>/dev/null \
            | sort -k1)

    elif cmd_exists rpm; then
        # RHEL/CentOS/Fedora
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local name version
            name=$(echo "$line"    | awk '{print $1}')
            version=$(echo "$line" | awk '{print $2}')

            local e
            e="{\"name\":\"$(json_escape "$name")\","
            e+="\"version\":\"$(json_escape "$version")\","
            e+="\"arch\":\"\","
            e+="\"manager\":\"rpm\"}"
            entries=$(append_entry "$entries" "$e")
        done < <(rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}\n' 2>/dev/null | sort -k1)
    fi

    wrap_array "$entries"
}
