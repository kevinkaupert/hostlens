#!/bin/bash
# =============================================================================
# network.sh — IPs, interfaces, gateway, DNS
# =============================================================================

collect_network() {
    local primary_ip gateway dns_raw iface_entries

    primary_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' \
        || hostname -I 2>/dev/null | awk '{print $1}' || echo "")
    gateway=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}' || echo "")
    dns_raw=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | sort)

    # Interfaces sorted by name
    iface_entries=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local iface addr mac
        iface=$(echo "$line" | awk '{print $2}')
        addr=$(echo "$line"  | awk '{print $4}')
        mac=$(ip link show "$iface" 2>/dev/null | awk '/link\/ether/{print $2}' || echo "")
        local e
        e="{\"name\":\"$(json_escape "$iface")\",\"address\":\"$(json_escape "$addr")\",\"mac\":\"$(json_escape "$mac")\"}"
        iface_entries=$(append_entry "$iface_entries" "$e")
    done < <(ip -o addr show 2>/dev/null | grep -v " lo " | sort -k2)

    cat << EOF
{
    "primary_ip": "$(json_escape "$primary_ip")",
    "gateway": "$(json_escape "$gateway")",
    "dns_servers": $(lines_to_json_array "$dns_raw"),
    "interfaces": $(wrap_array "$iface_entries")
  }
EOF
}
