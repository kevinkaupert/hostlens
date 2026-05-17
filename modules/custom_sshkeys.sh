#!/bin/bash
# =============================================================================
# custom_sshkeys.sh — Contents of all authorized_keys files
#
# Why: New or unknown SSH keys are an indicator of compromise.
#      Git diff immediately shows when a new key has been added.
# =============================================================================

collect_custom_sshkeys() {
    local entries=""

    # Iterate over all users with a home directory
    while IFS=: read -r uname _ uid _ _ home _; do
        local keyfile="$home/.ssh/authorized_keys"
        [ -f "$keyfile" ] || continue

        while IFS= read -r line; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^# ]] && continue

            # Split key type, key material, and comment
            local keytype keydata comment
            keytype=$(echo "$line" | awk '{print $1}')
            keydata=$(echo "$line" | awk '{print $2}')
            comment=$(echo "$line" | awk '{print $3}')

            # Compute fingerprint (safer than storing the full key)
            local fingerprint=""
            if cmd_exists ssh-keygen; then
                fingerprint=$(echo "$line" | ssh-keygen -lf /dev/stdin 2>/dev/null \
                    | awk '{print $2}' || echo "")
            fi

            # First/last part of key for diff readability
            local key_preview="${keydata:0:20}...${keydata: -10}"

            local e
            e="{\"user\":\"$(json_escape "$uname")\","
            e+="\"file\":\"$(json_escape "$keyfile")\","
            e+="\"type\":\"$(json_escape "$keytype")\","
            e+="\"comment\":\"$(json_escape "$comment")\","
            e+="\"fingerprint\":\"$(json_escape "$fingerprint")\","
            e+="\"key_preview\":\"$(json_escape "$key_preview")\"}"
            entries=$(append_entry "$entries" "$e")
        done < "$keyfile"
    done < <(getent passwd 2>/dev/null | awk -F: '$3 >= 1000 || $1 == "root"' | sort -t: -k1)

    # Also check /etc/ssh/authorized_keys/* if it exists
    if [ -d "/etc/ssh/authorized_keys" ]; then
        for keyfile in /etc/ssh/authorized_keys/*; do
            [ -f "$keyfile" ] || continue
            local uname
            uname=$(basename "$keyfile")
            while IFS= read -r line; do
                [[ -z "$line" || "$line" =~ ^# ]] && continue
                local keytype keydata comment fingerprint
                keytype=$(echo "$line" | awk '{print $1}')
                keydata=$(echo "$line" | awk '{print $2}')
                comment=$(echo "$line" | awk '{print $3}')
                fingerprint=$(echo "$line" | ssh-keygen -lf /dev/stdin 2>/dev/null \
                    | awk '{print $2}' || echo "")
                local key_preview="${keydata:0:20}...${keydata: -10}"
                local e
                e="{\"user\":\"$(json_escape "$uname")\","
                e+="\"file\":\"$(json_escape "$keyfile")\","
                e+="\"type\":\"$(json_escape "$keytype")\","
                e+="\"comment\":\"$(json_escape "$comment")\","
                e+="\"fingerprint\":\"$(json_escape "$fingerprint")\","
                e+="\"key_preview\":\"$(json_escape "$key_preview")\"}"
                entries=$(append_entry "$entries" "$e")
            done < "$keyfile"
        done
    fi

    wrap_array "$entries"
}
