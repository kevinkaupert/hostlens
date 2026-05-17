#!/bin/bash
# =============================================================================
# custom_EXAMPLE.sh — Example of a custom module
#
# How to add a new module:
#   1. Copy this file: cp custom_EXAMPLE.sh custom_mymodule.sh
#   2. Rename the function: collect_custom_mymodule()
#   3. Implement your logic
#   4. In snapshot.sh:
#      - source "$MODULES_DIR/custom_mymodule.sh"
#      - "mymodule": $(collect_custom_mymodule),  ← add to JSON block
#
# Ideas for more modules:
#   custom_packages.sh    — installed packages (apt list --installed)
#   custom_sshkeys.sh     — all authorized_keys contents
#   custom_files.sh       — checksums of critical configs (/etc/passwd, etc.)
#   custom_mounts.sh      — mounted NFS/CIFS shares
#   custom_kernel_mods.sh — loaded kernel modules
#   custom_env.sh         — set environment variables
# =============================================================================

collect_custom_example() {
    # Example: monitor installed packages starting with "nginx"
    local entries=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name version
        name=$(echo "$line" | awk '{print $1}' | cut -d'/' -f1)
        version=$(echo "$line" | awk '{print $2}')
        local e
        e="{\"package\":\"$(json_escape "$name")\",\"version\":\"$(json_escape "$version")\"}"
        entries=$(append_entry "$entries" "$e")
    done < <(dpkg -l 2>/dev/null | grep "^ii.*nginx" | awk '{print $2, $3}' | sort || true)

    wrap_array "$entries"
}
