#!/bin/bash
# =============================================================================
# collect-and-push.sh — Central wrapper script
#
# Runs all steps in the correct order:
#   1. Create snapshot  (snapshot.sh)
#   2. Render Markdown  (render.sh)
#   3. Git commit+push  (git-push.sh)
#
# Usage:
#   ./collect-and-push.sh [--remote <url>] [--repo-dir <path>]
#
# Configuration via environment variables or directly below.
# =============================================================================

set -uo pipefail

# =============================================================================
# CONFIGURATION — adjust here
# =============================================================================

# Directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Directory of the Git repo where snapshots are stored
REPO_DIR="${REPO_DIR:-$SCRIPT_DIR/repo}"

# Temporary snapshot path
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
SNAPSHOT_FILE="${SNAPSHOT_FILE:-/tmp/${HOSTNAME}.snapshot.json}"

# Markdown is always rendered — it's the only thing committed to Git
RENDER_MARKDOWN="true"

# Remote URL for automatic git init (empty = no remote)
GIT_REMOTE_URL="${GIT_REMOTE_URL:-}"

# Notifications (empty = disabled)
export NTFY_URL="${NTFY_URL:-}"
export TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
export TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# =============================================================================
# CLI ARGUMENTS
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote|-r)
            GIT_REMOTE_URL="${2:-}"
            shift 2
            ;;
        --repo-dir|-d)
            REPO_DIR="${2:-}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--remote <url>] [--repo-dir <path>]" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# MAIN
# =============================================================================

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2; exit 1; }

log "=== hostlens ==="
log "Host: $HOSTNAME"

# ── 0. Ensure repo directory exists ──────────────────────────────────────────
if [ ! -d "$REPO_DIR" ]; then
    log "Repo directory does not exist — creating: $REPO_DIR"
    mkdir -p "$REPO_DIR" || die "Could not create repo directory: $REPO_DIR"
fi

# ── 1. Collect snapshot ──────────────────────────────────────────────────────
log "Collecting snapshot..."
"$SCRIPT_DIR/snapshot.sh" "$SNAPSHOT_FILE" || die "Snapshot collection failed"

# ── 2. Render Markdown (required — tracked in Git, JSON is not) ──────────────
MD_FILE="$REPO_DIR/${HOSTNAME}.md"
log "Rendering Markdown to $MD_FILE..."
if command -v jq &>/dev/null; then
    "$SCRIPT_DIR/render.sh" "$SNAPSHOT_FILE" "$MD_FILE" \
        || die "Markdown rendering failed"
    log "Markdown rendered."
else
    die "jq is not installed — cannot render Markdown"
fi

# ── 3. Commit and push ───────────────────────────────────────────────────────
log "Committing and pushing..."
"$SCRIPT_DIR/git-push.sh" "$SNAPSHOT_FILE" "$REPO_DIR" "$GIT_REMOTE_URL" \
    || die "Git push failed"

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -f "$SNAPSHOT_FILE"

log "=== Run completed ==="
