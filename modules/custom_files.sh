#!/bin/bash
# =============================================================================
# custom_files.sh — Monitor critical files (integrity check)
#
# Why: Modified system files like /etc/passwd, /etc/hosts, or
#      /etc/crontab are strong indicators of compromise.
#      SHA256 checksums in Git immediately show when something changed.
# =============================================================================

# Files to monitor
WATCHED_FILES=(
    "/etc/passwd"
    "/etc/shadow"
    "/etc/group"
    "/etc/sudoers"
    "/etc/hosts"
    "/etc/hostname"
    "/etc/resolv.conf"
    "/etc/crontab"
    "/etc/ssh/sshd_config"
    "/etc/ssh/ssh_config"
    "/etc/environment"
    "/etc/profile"
    "/etc/bashrc"
    "/etc/bash.bashrc"
    "/root/.bashrc"
    "/root/.bash_profile"
    "/root/.profile"
    "/etc/ld.so.preload"        # Classic rootkit indicator
    "/etc/pam.d/sshd"
    "/etc/pam.d/sudo"
    "/boot/grub/grub.cfg"
)

collect_custom_files() {
    local entries=""

    for filepath in "${WATCHED_FILES[@]}"; do
        [ -e "$filepath" ] || continue

        local exists="true"
        local sha256 size perms owner modified
        sha256=$(sha256sum "$filepath" 2>/dev/null | awk '{print $1}' || echo "")
        size=$(stat -c '%s' "$filepath" 2>/dev/null || echo "0")
        perms=$(stat -c '%A' "$filepath" 2>/dev/null || echo "")
        owner=$(stat -c '%U:%G' "$filepath" 2>/dev/null || echo "")
        # Modification time as Unix timestamp (stable for diffs)
        modified=$(stat -c '%Y' "$filepath" 2>/dev/null || echo "0")

        local e
        e="{\"path\":\"$(json_escape "$filepath")\","
        e+="\"exists\":$exists,"
        e+="\"sha256\":\"$(json_escape "$sha256")\","
        e+="\"size\":$size,"
        e+="\"permissions\":\"$(json_escape "$perms")\","
        e+="\"owner\":\"$(json_escape "$owner")\","
        e+="\"modified_unix\":$modified}"
        entries=$(append_entry "$entries" "$e")
    done

    # Also track missing files (in case they disappear)
    for filepath in "${WATCHED_FILES[@]}"; do
        [ -e "$filepath" ] && continue
        local e
        e="{\"path\":\"$(json_escape "$filepath")\","
        e+="\"exists\":false,"
        e+="\"sha256\":\"\","
        e+="\"size\":0,"
        e+="\"permissions\":\"\","
        e+="\"owner\":\"\","
        e+="\"modified_unix\":0}"
        entries=$(append_entry "$entries" "$e")
    done

    wrap_array "$entries"
}
