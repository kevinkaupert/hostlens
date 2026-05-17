#!/bin/bash
# =============================================================================
# custom_TEMPLATE.sh — Template for custom modules
#
# INSTRUCTIONS:
#   1. Copy:   cp custom_TEMPLATE.sh custom_mymodule.sh
#   2. Rename: collect_custom_mymodule()
#   3. Implement logic
#   4. Register in snapshot.sh:
#      - source "$MODULES_DIR/custom_mymodule.sh"
#      - "mymodule": $(collect_custom_mymodule),
#
# DESIGN RULES for clean Git diffs:
#   ✓ Always output arrays sorted
#   ✓ One object per line (use append_entry)
#   ✓ No volatile values (current time, random values)
#   ✓ Always pass strings through json_escape()
#   ✓ Return empty arrays as [], never null
#
# AVAILABLE HELPERS (from lib.sh):
#   cmd_exists <name>              — check if command is available
#   json_escape "<string>"         — escape string for JSON
#   lines_to_json_array "<text>"   — lines → JSON array
#   wrap_array "<entries-string>"  — entries string → JSON array
#   append_entry "<current>" "<new>" — append an entry
# =============================================================================

collect_custom_TEMPLATE() {
    local entries=""

    # Example: collect a simple list
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Extract data from line
        local field1 field2
        field1=$(echo "$line" | awk '{print $1}')
        field2=$(echo "$line" | awk '{print $2}')

        # Build JSON object
        local e
        e="{\"field1\":\"$(json_escape "$field1")\","
        e+="\"field2\":\"$(json_escape "$field2")\"}"

        # Append to result string
        entries=$(append_entry "$entries" "$e")

    done < <(echo "example data" | sort)  # ← replace with your data source

    # Return as JSON array
    wrap_array "$entries"
}

# =============================================================================
# IDEAS FOR CUSTOM MODULES:
#
# custom_mounts.sh        — mounted NFS/CIFS shares
#   find in: /proc/mounts, mount -t nfs,cifs
#
# custom_env.sh           — system-wide environment variables
#   find in: /etc/environment, /etc/profile.d/*.sh
#
# custom_hosts.sh         — /etc/hosts entries (tampering indicator)
#   find in: /etc/hosts
#
# custom_arp.sh           — ARP table (unknown devices on network)
#   find in: arp -n, ip neigh
#
# custom_listening_sockets.sh — Unix domain sockets
#   find in: ss -xlnp
#
# custom_failed_logins.sh — failed SSH login attempts
#   find in: journalctl -u sshd, /var/log/auth.log
# =============================================================================
