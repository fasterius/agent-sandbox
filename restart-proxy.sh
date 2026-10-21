#!/usr/bin/env bash
set -euo pipefail

# Restart an agent's egress proxy so that edits to its allow-list take effect;
# only the egress-filtered modes use a proxy

usage() {
    echo "Usage: $(basename "$0") <claude|opencode>" >&2
    exit 1
}

[[ $# -eq 1 ]] || usage
case "$1" in claude | opencode) ;; *) usage ;; esac

SANDBOX_DIR="$(dirname "$0")"

# Use the same compose file and project name as `run-agent.sh` does in the
# egress-filtered mode, so that the proxy of that compose project is the one
# restarted
export COMPOSE_FILE="$SANDBOX_DIR/compose-$1.yml"
export COMPOSE_PROJECT_NAME="$1-sandbox-egress-filtered"

# Required by the compose files, but not used by the proxy
export PROJECT_DIR=. CLAUDE_HOME=. OPENCODE_HOME=.

# Recreate rather than restart the container, so that the allow-list is re-read
# even if an editor saved it by replacing the file rather than modifying it
docker compose up -d --force-recreate proxy
