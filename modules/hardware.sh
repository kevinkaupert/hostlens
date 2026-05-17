#!/bin/bash
# =============================================================================
# hardware.sh — CPU, RAM, disks
# =============================================================================

collect_hardware() {
    local cpu_model vcpus ram_gb disk_entries entry

    cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | xargs || echo "")
    vcpus=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo)
    local ram_kb
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    ram_gb=$(LC_ALL=C awk "BEGIN {printf \"%.1f\", $ram_kb/1024/1024}")

    # Disks — sorted by mount point for stable diffs
    disk_entries=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local src size used avail pct mount
        src=$(echo "$line"   | awk '{print $1}')
        size=$(echo "$line"  | awk '{print $2}')
        used=$(echo "$line"  | awk '{print $3}')
        avail=$(echo "$line" | awk '{print $4}')
        pct=$(echo "$line"   | awk '{print $5}')
        mount=$(echo "$line" | awk '{print $6}')
        local e
        e="{\"device\":\"$(json_escape "$src")\",\"mount\":\"$(json_escape "$mount")\",\"size\":\"$size\",\"used\":\"$used\",\"avail\":\"$avail\",\"use_pct\":\"$pct\"}"
        disk_entries=$(append_entry "$disk_entries" "$e")
    done < <(LC_ALL=C df -h --output=source,size,used,avail,pcent,target 2>/dev/null \
        | grep -E "^/dev/" | grep -v "tmpfs" | sort -k6)

    cat << EOF
{
    "vcpus": $vcpus,
    "cpu_model": "$(json_escape "$cpu_model")",
    "ram_gb": $ram_gb,
    "disks": $(wrap_array "$disk_entries")
  }
EOF
}
