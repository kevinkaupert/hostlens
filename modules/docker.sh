#!/bin/bash
# =============================================================================
# docker.sh — Containers, networks, volumes, compose files
# =============================================================================

collect_docker() {
    # Docker not installed or not reachable
    if ! cmd_exists docker || ! docker info &>/dev/null 2>&1; then
        cat << EOF
{
    "installed": false,
    "version": "",
    "api_version": "",
    "compose_version": "",
    "compose_files": [],
    "containers": [],
    "networks": [],
    "volumes": []
  }
EOF
        return
    fi

    local docker_ver api_ver compose_ver
    docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "")
    api_ver=$(docker version --format '{{.Server.APIVersion}}' 2>/dev/null || echo "")

    compose_ver=""
    if cmd_exists docker-compose; then
        compose_ver=$(docker-compose version --short 2>/dev/null || echo "")
    elif docker compose version &>/dev/null 2>&1; then
        compose_ver=$(docker compose version 2>/dev/null \
            | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
    fi

    # ── Containers ─────────────────────────────────────────────────────────────
    local cont_entries=""
    while IFS='|' read -r name image status ports; do
        [[ -z "$name" ]] && continue
        local compose_project compose_dir managed
        compose_project=$(docker inspect "$name" 2>/dev/null \
            | grep -oP '"com.docker.compose.project":\s*"\K[^"]+' | head -1 || echo "")
        compose_dir=$(docker inspect "$name" 2>/dev/null \
            | grep -oP '"com.docker.compose.project.working_dir":\s*"\K[^"]+' | head -1 || echo "")
        managed="false"
        [[ -n "$compose_project" ]] && managed="true"

        local e
        e="{\"name\":\"$(json_escape "$name")\",\"image\":\"$(json_escape "$image")\","
        e+="\"status\":\"$(json_escape "$status")\",\"ports\":\"$(json_escape "$ports")\","
        e+="\"compose_project\":\"$(json_escape "$compose_project")\","
        e+="\"compose_dir\":\"$(json_escape "$compose_dir")\","
        e+="\"managed_by_compose\":$managed}"
        cont_entries=$(append_entry "$cont_entries" "$e")
    done < <(docker ps -a --format '{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}' 2>/dev/null | sort)

    # ── Networks ───────────────────────────────────────────────────────────────
    local net_entries=""
    while IFS='|' read -r nname driver scope; do
        [[ -z "$nname" ]] && continue
        local e
        e="{\"name\":\"$(json_escape "$nname")\",\"driver\":\"$(json_escape "$driver")\",\"scope\":\"$(json_escape "$scope")\"}"
        net_entries=$(append_entry "$net_entries" "$e")
    done < <(docker network ls --format '{{.Name}}|{{.Driver}}|{{.Scope}}' 2>/dev/null | sort)

    # ── Volumes ────────────────────────────────────────────────────────────────
    local vol_entries=""
    while IFS='|' read -r vname driver; do
        [[ -z "$vname" ]] && continue
        local e
        e="{\"name\":\"$(json_escape "$vname")\",\"driver\":\"$(json_escape "$driver")\"}"
        vol_entries=$(append_entry "$vol_entries" "$e")
    done < <(docker volume ls --format '{{.Name}}|{{.Driver}}' 2>/dev/null | sort)

    # ── Compose Files ──────────────────────────────────────────────────────────
    local compose_raw
    compose_raw=$(find /opt /srv /home /root /docker /var/lib 2>/dev/null \
        \( -name "docker-compose.yml" \
        -o -name "docker-compose.yaml" \
        -o -name "compose.yml" \
        -o -name "compose.yaml" \) \
        2>/dev/null | sort | head -30)

    cat << EOF
{
    "installed": true,
    "version": "$(json_escape "$docker_ver")",
    "api_version": "$(json_escape "$api_ver")",
    "compose_version": "$(json_escape "$compose_ver")",
    "compose_files": $(lines_to_json_array "$compose_raw"),
    "containers": $(wrap_array "$cont_entries"),
    "networks": $(wrap_array "$net_entries"),
    "volumes": $(wrap_array "$vol_entries")
  }
EOF
}
