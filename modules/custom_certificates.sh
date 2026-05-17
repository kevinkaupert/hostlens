#!/bin/bash
# =============================================================================
# custom_certificates.sh — Monitor TLS certificates
#
# Why: Expired certificates cause outages.
#      Unknown certificates can indicate MITM attacks.
#      Monitors: system certs, Let's Encrypt, Docker volumes, /etc/ssl
# =============================================================================

# Days before expiry to flag as "expiring soon"
WARN_DAYS=30

collect_custom_certificates() {
    local entries=""

    # Find all .pem/.crt files in known paths
    local cert_paths=(
        "/etc/ssl/certs"
        "/etc/letsencrypt/live"
        "/etc/traefik"
        "/opt"
        "/srv"
        "/root"
        "/home"
    )

    while IFS= read -r certfile; do
        [[ -z "$certfile" ]] && continue

        # Only real certificates (not private keys etc.)
        grep -q "BEGIN CERTIFICATE" "$certfile" 2>/dev/null || continue

        local subject issuer expiry_date expiry_unix days_left expired soon

        subject=$(openssl x509 -in "$certfile" -noout -subject 2>/dev/null \
            | sed 's/subject=//' | xargs || echo "")
        issuer=$(openssl x509 -in "$certfile" -noout -issuer 2>/dev/null \
            | sed 's/issuer=//' | xargs || echo "")
        expiry_date=$(openssl x509 -in "$certfile" -noout -enddate 2>/dev/null \
            | cut -d'=' -f2 || echo "")

        # Unix timestamp of expiry date
        expiry_unix=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
        local now_unix
        now_unix=$(date +%s)
        days_left=$(( (expiry_unix - now_unix) / 86400 ))

        expired="false"
        soon="false"
        [ "$days_left" -lt 0 ] && expired="true"
        [ "$days_left" -lt "$WARN_DAYS" ] && [ "$expired" = "false" ] && soon="true"

        # Extract SANs (Subject Alternative Names)
        local sans
        sans=$(openssl x509 -in "$certfile" -noout -text 2>/dev/null \
            | grep -A1 "Subject Alternative Name" | tail -1 \
            | sed 's/DNS://g; s/IP Address://g' | xargs || echo "")

        local e
        e="{\"file\":\"$(json_escape "$certfile")\","
        e+="\"subject\":\"$(json_escape "$subject")\","
        e+="\"issuer\":\"$(json_escape "$issuer")\","
        e+="\"expiry\":\"$(json_escape "$expiry_date")\","
        e+="\"days_left\":$days_left,"
        e+="\"expired\":$expired,"
        e+="\"expiring_soon\":$soon,"
        e+="\"sans\":\"$(json_escape "$sans")\"}"
        entries=$(append_entry "$entries" "$e")

    done < <(find "${cert_paths[@]}" -maxdepth 5 \
        \( -name "*.pem" -o -name "*.crt" -o -name "fullchain.pem" \) \
        -type f 2>/dev/null | sort)

    wrap_array "$entries"
}
