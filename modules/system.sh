#!/bin/bash
# =============================================================================
# system.sh — OS, kernel, virtualization
# =============================================================================

collect_system() {
    local os kernel arch virt bios_vendor product_name uptime_sec

    os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || uname -s)
    kernel=$(uname -r)
    arch=$(uname -m)
    virt=$(systemd-detect-virt 2>/dev/null || echo "none")
    bios_vendor=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null | tr -d '\n' || echo "")
    product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -d '\n' || echo "")
    # Uptime in seconds (stable — no text that changes every second)
    uptime_sec=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || echo "0")

    cat << EOF
{
    "os": "$(json_escape "$os")",
    "kernel": "$(json_escape "$kernel")",
    "arch": "$(json_escape "$arch")",
    "virtualization": "$(json_escape "$virt")",
    "bios_vendor": "$(json_escape "$bios_vendor")",
    "product_name": "$(json_escape "$product_name")",
    "uptime_seconds": $uptime_sec
  }
EOF
}
