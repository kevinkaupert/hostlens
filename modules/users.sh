#!/bin/bash
# =============================================================================
# users.sh — Users, groups, SSH keys
# =============================================================================

collect_users() {
    local user_entries sudo_raw docker_raw

    user_entries=""
    while IFS=: read -r uname _ uid _ _ home shell; do
        # Skip non-login shells
        [[ "$shell" =~ (nologin|false|sync|halt|shutdown) ]] && continue

        local sudo_member docker_member key_count
        sudo_member="false"
        docker_member="false"
        key_count=0

        getent group sudo  2>/dev/null | grep -qw "$uname" && sudo_member="true"
        getent group wheel 2>/dev/null | grep -qw "$uname" && sudo_member="true"
        getent group docker 2>/dev/null | grep -qw "$uname" && docker_member="true"

        # Count SSH authorized_keys
        for keyfile in "$home/.ssh/authorized_keys" "/etc/ssh/authorized_keys/$uname"; do
            if [ -f "$keyfile" ]; then
                key_count=$(grep -cE "^(ssh-|ecdsa-|sk-)" "$keyfile" 2>/dev/null) || key_count=0
            fi
        done

        local e
        e="{\"name\":\"$(json_escape "$uname")\",\"uid\":$uid,\"home\":\"$(json_escape "$home")\",\"shell\":\"$(json_escape "$shell")\",\"sudo\":$sudo_member,\"docker\":$docker_member,\"ssh_keys\":$key_count}"
        user_entries=$(append_entry "$user_entries" "$e")
    done < <(getent passwd 2>/dev/null | awk -F: '($3 >= 1000 || $1 == "root")' | sort -t: -k1)

    # Group members
    sudo_raw=$(getent group sudo  2>/dev/null | cut -d: -f4 \
            || getent group wheel 2>/dev/null | cut -d: -f4 || echo "")
    docker_raw=$(getent group docker 2>/dev/null | cut -d: -f4 || echo "")

    cat << EOF
{
    "users": $(wrap_array "$user_entries"),
    "sudo_members": $(lines_to_json_array "$(echo "$sudo_raw" | tr ',' '\n' | sort)"),
    "docker_members": $(lines_to_json_array "$(echo "$docker_raw" | tr ',' '\n' | sort)")
  }
EOF
}
