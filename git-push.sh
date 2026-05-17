#!/bin/bash
# =============================================================================
# git-push.sh — Git integration for hostlens
#
# Takes the current snapshot, commits changes with a descriptive
# commit message, and pushes to the remote repo.
#
# Usage:
#   ./git-push.sh <snapshot.json> <repo-path> [remote-url]
#
# Example cron job:
#   */15 * * * * root /opt/hostlens/collect-and-push.sh
# =============================================================================

set -uo pipefail

SNAPSHOT_FILE="${1:-}"
REPO_DIR="${2:-}"
GIT_REMOTE_URL="${3:-${GIT_REMOTE_URL:-}}"

# =============================================================================
# CONFIGURATION — adjust as needed
# =============================================================================

# Git identity for commits
GIT_USER_NAME="${GIT_USER_NAME:-hostlens}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-drift@$(hostname)}"

# Ntfy notification (leave empty to disable)
NTFY_URL="${NTFY_URL:-}"        # e.g. https://ntfy.example.com/vm-alerts

# Telegram notification (leave both empty to disable)
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# =============================================================================
# HELPERS
# =============================================================================

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
err()  { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; }
die()  { err "$*"; exit 1; }

cmd_exists() { command -v "$1" &>/dev/null; }

# Read value from JSON (with or without jq)
json_get() {
    local file="$1" key="$2"
    if cmd_exists jq; then
        jq -r "$key // empty" "$file" 2>/dev/null || echo ""
    else
        grep -oP "\"${key#.}\":\s*\"\K[^\"]*" "$file" 2>/dev/null | head -1 || echo ""
    fi
}

# Count entries in a JSON array
json_count() {
    local file="$1" key="$2"
    if cmd_exists jq; then
        jq "$key | length" "$file" 2>/dev/null || echo "0"
    else
        grep -c "\"name\":" "$file" 2>/dev/null || echo "0"
    fi
}

# =============================================================================
# ARGUMENT VALIDATION
# =============================================================================

[ -z "$SNAPSHOT_FILE" ] && die "No snapshot file specified. Usage: $0 <snapshot.json> <repo-dir> [remote-url]"
[ -z "$REPO_DIR" ]      && die "No repo directory specified. Usage: $0 <snapshot.json> <repo-dir> [remote-url]"
[ -f "$SNAPSHOT_FILE" ] || die "Snapshot file not found: $SNAPSHOT_FILE"

# Create repo directory if missing
if [ ! -d "$REPO_DIR" ]; then
    log "Creating repo directory: $REPO_DIR"
    mkdir -p "$REPO_DIR" || die "Could not create repo directory: $REPO_DIR"
fi

# Initialize Git repo if missing
if [ ! -d "$REPO_DIR/.git" ]; then
    log "Initializing new Git repo in: $REPO_DIR"
    git -C "$REPO_DIR" init || die "git init failed"
    git -C "$REPO_DIR" config user.name  "$GIT_USER_NAME"
    git -C "$REPO_DIR" config user.email "$GIT_USER_EMAIL"

    # Create .gitignore — keep JSON local
    cat > "$REPO_DIR/.gitignore" <<'EOF'
*.json
*.prev.json
EOF
    git -C "$REPO_DIR" add .gitignore
    git -C "$REPO_DIR" commit -m "chore: init hostlens repo" || true

    # Prompt for remote URL if not provided and running interactively
    if [ -z "$GIT_REMOTE_URL" ] && [ -t 0 ]; then
        echo ""
        read -rp "[hostlens] Remote URL (SSH or HTTP, leave empty to skip): " GIT_REMOTE_URL
    fi

    if [ -n "$GIT_REMOTE_URL" ]; then
        log "Adding remote 'origin': $GIT_REMOTE_URL"
        git -C "$REPO_DIR" remote add origin "$GIT_REMOTE_URL" \
            || die "Could not add remote: $GIT_REMOTE_URL"

        # Check if remote already has content
        if git -C "$REPO_DIR" ls-remote --exit-code origin HEAD &>/dev/null; then
            log "Remote repo already has content."
            if [ -t 0 ]; then
                echo ""
                echo "  The remote already has commits (e.g. from other hosts)."
                echo "  What would you like to do?"
                echo "  1) Reset to remote state — recommended, keeps other hosts' data"
                echo "  2) Force-push local state — overwrites remote history"
                echo "  3) Skip push — local commits only for now"
                read -rp "  Choice [1]: " _choice
                _choice="${_choice:-1}"
            else
                _choice="1"
                log "Non-interactive — resetting to remote state."
            fi

            case "$_choice" in
                2)
                    log "Force-pushing to remote..."
                    BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")
                    git -C "$REPO_DIR" push --force -u origin "$BRANCH" \
                        || log "WARN: Force-push failed."
                    ;;
                3)
                    log "Skipping push — local commits only."
                    GIT_REMOTE_URL=""
                    ;;
                *)
                    log "Resetting local repo to remote state..."
                    git -C "$REPO_DIR" fetch origin
                    BRANCH=$(git -C "$REPO_DIR" remote show origin 2>/dev/null \
                        | awk '/HEAD branch/ {print $NF}' || echo "master")
                    git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
                    ;;
            esac
        else
            log "Remote is empty — will push on first commit."
        fi
    else
        log "NOTE: No remote configured. Commits will be local only."
        log "  Add remote later: git -C $REPO_DIR remote add origin <url>"
        log "  Or on next run:   ./collect-and-push.sh --remote <url>"
    fi
fi

# Add remote if URL was passed but origin is missing
if [ -n "$GIT_REMOTE_URL" ] && ! git -C "$REPO_DIR" remote | grep -q origin; then
    log "Adding remote 'origin': $GIT_REMOTE_URL"
    git -C "$REPO_DIR" remote add origin "$GIT_REMOTE_URL" \
        || die "Could not add remote: $GIT_REMOTE_URL"
fi

# =============================================================================
# COPY SNAPSHOT INTO REPO
# =============================================================================

HOSTNAME=$(hostname -f 2>/dev/null || hostname)
TARGET="$REPO_DIR/${HOSTNAME}.json"
PREV="$REPO_DIR/${HOSTNAME}.prev.json"
MD_FILE="$REPO_DIR/${HOSTNAME}.md"

# Keep JSON locally (not in Git) — used as base for diff analysis
[ -f "$TARGET" ] && cp "$TARGET" "$PREV"
cp "$SNAPSHOT_FILE" "$TARGET"

# =============================================================================
# CHECK GIT STATUS
# =============================================================================

cd "$REPO_DIR"

# Set Git identity
git config user.name  "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

# Only push Markdown — JSON stays local (in .gitignore)
[ -f "$MD_FILE" ] || { log "WARN: $MD_FILE not found — was render.sh run?"; exit 1; }
git add "${HOSTNAME}.md"

# No changes → nothing to do
if git diff --cached --quiet; then
    log "No changes on $HOSTNAME — skipping commit."
    [ -f "$PREV" ] && rm -f "$PREV"
    exit 0
fi

# =============================================================================
# BUILD COMMIT MESSAGE
# =============================================================================

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
CHANGES=""

if [ -f "$PREV" ] && cmd_exists jq; then

    # ── Users ─────────────────────────────────────────────────────────────────
    NEW_USERS=$(jq -r '.users.users[].name' "$TARGET" 2>/dev/null | sort)
    OLD_USERS=$(jq -r '.users.users[].name' "$PREV"   2>/dev/null | sort)

    while IFS= read -r u; do
        [[ -z "$u" ]] && continue
        CHANGES+=$'\n'"+ user: $u"
    done < <(comm -13 <(echo "$OLD_USERS") <(echo "$NEW_USERS"))

    while IFS= read -r u; do
        [[ -z "$u" ]] && continue
        CHANGES+=$'\n'"- user: $u"
    done < <(comm -23 <(echo "$OLD_USERS") <(echo "$NEW_USERS"))

    # ── TCP Ports ─────────────────────────────────────────────────────────────
    NEW_PORTS=$(jq -r '.ports_tcp[] | "\(.port)/\(.process)"' "$TARGET" 2>/dev/null | sort)
    OLD_PORTS=$(jq -r '.ports_tcp[] | "\(.port)/\(.process)"' "$PREV"   2>/dev/null | sort)

    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        CHANGES+=$'\n'"+ port: $p"
    done < <(comm -13 <(echo "$OLD_PORTS") <(echo "$NEW_PORTS"))

    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        CHANGES+=$'\n'"- port: $p"
    done < <(comm -23 <(echo "$OLD_PORTS") <(echo "$NEW_PORTS"))

    # ── Docker Containers ─────────────────────────────────────────────────────
    NEW_CONT=$(jq -r '.docker.containers[] | "\(.name) [\(.status)]"' "$TARGET" 2>/dev/null | sort)
    OLD_CONT=$(jq -r '.docker.containers[] | "\(.name) [\(.status)]"' "$PREV"   2>/dev/null | sort)

    while IFS= read -r c; do
        [[ -z "$c" ]] && continue
        CHANGES+=$'\n'"+ container: $c"
    done < <(comm -13 <(echo "$OLD_CONT") <(echo "$NEW_CONT"))

    while IFS= read -r c; do
        [[ -z "$c" ]] && continue
        CHANGES+=$'\n'"- container: $c"
    done < <(comm -23 <(echo "$OLD_CONT") <(echo "$NEW_CONT"))

    # ── Services ──────────────────────────────────────────────────────────────
    NEW_SVC=$(jq -r '.services[]' "$TARGET" 2>/dev/null | sort)
    OLD_SVC=$(jq -r '.services[]' "$PREV"   2>/dev/null | sort)

    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        CHANGES+=$'\n'"+ service: $s"
    done < <(comm -13 <(echo "$OLD_SVC") <(echo "$NEW_SVC"))

    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        CHANGES+=$'\n'"- service: $s"
    done < <(comm -23 <(echo "$OLD_SVC") <(echo "$NEW_SVC"))

    # ── SSH Keys ──────────────────────────────────────────────────────────────
    NEW_KEYS=$(jq -r '.ssh_keys[] | "\(.user): \(.fingerprint)"' "$TARGET" 2>/dev/null | sort)
    OLD_KEYS=$(jq -r '.ssh_keys[] | "\(.user): \(.fingerprint)"' "$PREV"   2>/dev/null | sort)

    while IFS= read -r k; do
        [[ -z "$k" ]] && continue
        CHANGES+=$'\n'"+ ssh-key: $k"
    done < <(comm -13 <(echo "$OLD_KEYS") <(echo "$NEW_KEYS"))

    while IFS= read -r k; do
        [[ -z "$k" ]] && continue
        CHANGES+=$'\n'"- ssh-key: $k"
    done < <(comm -23 <(echo "$OLD_KEYS") <(echo "$NEW_KEYS"))

    # ── SSH Logins (non-trusted) ──────────────────────────────────────────────
    NEW_LOGINS=$(jq -r '.ssh_logins[] | "\(.user)@\(.source) (\(.method))"' "$TARGET" 2>/dev/null | sort)
    OLD_LOGINS=$(jq -r '.ssh_logins[] | "\(.user)@\(.source) (\(.method))"' "$PREV"   2>/dev/null | sort)

    while IFS= read -r l; do
        [[ -z "$l" ]] && continue
        CHANGES+=$'\n'"[WARN] ssh-login: $l"
    done < <(comm -13 <(echo "$OLD_LOGINS") <(echo "$NEW_LOGINS"))

    while IFS= read -r l; do
        [[ -z "$l" ]] && continue
        CHANGES+=$'\n'"- ssh-login: $l"
    done < <(comm -23 <(echo "$OLD_LOGINS") <(echo "$NEW_LOGINS"))

    # ── SUID Binaries (unknown) ───────────────────────────────────────────────
    NEW_SUID=$(jq -r '.suid_binaries[] | select(.known==false) | .path' "$TARGET" 2>/dev/null | sort)
    OLD_SUID=$(jq -r '.suid_binaries[] | select(.known==false) | .path' "$PREV"   2>/dev/null | sort)

    while IFS= read -r b; do
        [[ -z "$b" ]] && continue
        CHANGES+=$'\n'"[WARN] suid (unknown): $b"
    done < <(comm -13 <(echo "$OLD_SUID") <(echo "$NEW_SUID"))

    # ── Sudo Rules ────────────────────────────────────────────────────────────
    NEW_SUDO=$(jq -r '.sudoers[] | "\(.file): \(.rule)"' "$TARGET" 2>/dev/null | sort)
    OLD_SUDO=$(jq -r '.sudoers[] | "\(.file): \(.rule)"' "$PREV"   2>/dev/null | sort)

    while IFS= read -r r; do
        [[ -z "$r" ]] && continue
        CHANGES+=$'\n'"+ sudoers: $r"
    done < <(comm -13 <(echo "$OLD_SUDO") <(echo "$NEW_SUDO"))

    while IFS= read -r r; do
        [[ -z "$r" ]] && continue
        CHANGES+=$'\n'"- sudoers: $r"
    done < <(comm -23 <(echo "$OLD_SUDO") <(echo "$NEW_SUDO"))

    # ── File Integrity ────────────────────────────────────────────────────────
    NEW_FILES=$(jq -r '.file_integrity[] | "\(.path) \(.sha256)"' "$TARGET" 2>/dev/null | sort)
    OLD_FILES=$(jq -r '.file_integrity[] | "\(.path) \(.sha256)"' "$PREV"   2>/dev/null | sort)

    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        FILEPATH=$(echo "$f" | awk '{print $1}')
        CHANGES+=$'\n'"[WARN] file changed: $FILEPATH"
    done < <(comm -13 <(echo "$OLD_FILES") <(echo "$NEW_FILES") | grep -v "^$")

    # ── Expiring Certificates ─────────────────────────────────────────────────
    EXPIRING=$(jq -r '.certificates[] | select(.days_left < 30) | "\(.days_left)d: \(.subject)"' \
        "$TARGET" 2>/dev/null | sort || echo "")
    if [[ -n "$EXPIRING" ]]; then
        while IFS= read -r cert; do
            [[ -z "$cert" ]] && continue
            CHANGES+=$'\n'"[WARN] cert expiring: $cert"
        done <<< "$EXPIRING"
    fi
fi

# Build commit message
if [[ -n "$CHANGES" ]]; then
    SUMMARY=$(echo "$CHANGES" | grep -c "^[+\-\[]" || echo "?")
    COMMIT_MSG="snapshot(${HOSTNAME}): ${SUMMARY} change(s) — ${TIMESTAMP}"$'\n\n'"${CHANGES}"
else
    # Changes exist but not categorized (e.g. first commit or no jq)
    COMMIT_MSG="snapshot(${HOSTNAME}): updated — ${TIMESTAMP}"
fi

# =============================================================================
# COMMIT
# =============================================================================

log "Committing changes on $HOSTNAME..."
git commit -m "$COMMIT_MSG"
log "Commit successful."

# =============================================================================
# PUSH
# =============================================================================

if git remote | grep -q origin; then
    log "Pushing to origin..."
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")

    if git fetch origin "$BRANCH" 2>&1; then
        if ! git rebase "origin/$BRANCH" 2>&1; then
            git rebase --abort 2>/dev/null || true
            log "Rebase conflict — resetting to remote and re-applying snapshot..."
            git reset --hard "origin/$BRANCH"
            git add "${HOSTNAME}.md"
            if git diff --cached --quiet; then
                log "No changes after reset — skipping commit."
                [ -f "$PREV" ] && rm -f "$PREV"
                exit 0
            fi
            git commit -m "$COMMIT_MSG"
        fi
    fi

    if git push -u origin HEAD 2>&1; then
        log "Push successful."
    else
        err "Push failed — changes saved locally."
        exit 2
    fi
else
    log "No remote 'origin' configured — local commit only."
fi

# =============================================================================
# NOTIFICATIONS
# =============================================================================

if [[ -n "$CHANGES" ]]; then

    NOTIF_TITLE="[DRIFT] $HOSTNAME"
    NOTIF_BODY="$CHANGES"$'\n\n'"$TIMESTAMP"

    # ── Ntfy ──────────────────────────────────────────────────────────────────
    if [[ -n "$NTFY_URL" ]]; then
        curl -s \
            -H "Title: $NOTIF_TITLE" \
            -H "Priority: high" \
            -H "Tags: warning,server" \
            -d "$NOTIF_BODY" \
            "$NTFY_URL" > /dev/null && log "Ntfy notification sent."
    fi

    # ── Telegram ──────────────────────────────────────────────────────────────
    if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        TELEGRAM_MSG="*[DRIFT] ${HOSTNAME}*"$'\n'"${CHANGES}"$'\n\n'"_${TIMESTAMP}_"
        curl -s \
            -X POST \
            "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "parse_mode=Markdown" \
            -d "text=${TELEGRAM_MSG}" > /dev/null && log "Telegram notification sent."
    fi
fi

# Cleanup
[ -f "$PREV" ] && rm -f "$PREV"

log "Completed successfully."
