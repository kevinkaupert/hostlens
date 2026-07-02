#!/bin/bash
# =============================================================================
# custom_suid.sh — Monitor SUID/SGID binaries
#
# Why: New SUID binaries are a strong indicator of compromise.
#      Attackers often set SUID on binaries for persistent root access.
#      e.g.: chmod u+s /bin/bash → anyone can become root
# =============================================================================

collect_custom_suid() {
    local entries=""

    # Known legitimate SUID binaries (whitelist — changes here are expected)
    local -A KNOWN_SUID
    KNOWN_SUID=(
        ["/usr/bin/sudo"]="sudo"
        ["/usr/bin/su"]="su"
        ["/usr/bin/passwd"]="passwd"
        ["/usr/bin/chsh"]="chsh"
        ["/usr/bin/chfn"]="chfn"
        ["/usr/bin/newgrp"]="newgrp"
        ["/usr/bin/gpasswd"]="gpasswd"
        ["/usr/bin/mount"]="mount"
        ["/usr/bin/umount"]="umount"
        ["/usr/bin/pkexec"]="pkexec"
        ["/usr/lib/openssh/ssh-keysign"]="ssh-keysign"
        ["/usr/lib/dbus-1.0/dbus-daemon-launch-helper"]="dbus"
        ["/bin/ping"]="ping"
        ["/bin/su"]="su"
        ["/sbin/unix_chkpwd"]="unix_chkpwd"
    )

    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue

        local perms owner group size sha256 known
        perms=$(stat -c '%A' "$filepath" 2>/dev/null || echo "")
        owner=$(stat -c '%U' "$filepath" 2>/dev/null || echo "")
        group=$(stat -c '%G' "$filepath" 2>/dev/null || echo "")
        size=$(stat -c '%s' "$filepath" 2>/dev/null || echo "0")

        # SHA256 for integrity verification
        sha256=$(sha256sum "$filepath" 2>/dev/null | awk '{print $1}' || echo "")

        # Known or unknown?
        known="false"
        [[ -n "${KNOWN_SUID[$filepath]+x}" ]] && known="true"

        # Flag SGID separately
        local is_suid="false" is_sgid="false"
        echo "$perms" | grep -q "s......." && is_suid="true"
        echo "$perms" | grep -q "....s..." && is_sgid="true"

        local e
        e="{\"path\":\"$(json_escape "$filepath")\","
        e+="\"permissions\":\"$(json_escape "$perms")\","
        e+="\"owner\":\"$(json_escape "$owner")\","
        e+="\"group\":\"$(json_escape "$group")\","
        e+="\"size\":$size,"
        e+="\"sha256\":\"$(json_escape "$sha256")\","
        e+="\"suid\":$is_suid,"
        e+="\"sgid\":$is_sgid,"
        e+="\"known\":$known}"
        entries=$(append_entry "$entries" "$e")
    done < <(find / -xdev \( -perm -4000 -o -perm -2000 \) -type f 2>/dev/null | sort)

    wrap_array "$entries"
}
