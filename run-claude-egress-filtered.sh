#!/usr/bin/env bash
set -euo pipefail

# Refuse to run in any directory listed in `blocked-dirs`
SANDBOX_DIR="$(dirname "$0")"
source "$SANDBOX_DIR/check-dir.sh"

# Use a dedicated external home directory and make sure it exists
export CLAUDE_HOME="$HOME/.claude-sandbox-home-egress-filtered"
mkdir -p "$CLAUDE_HOME"

# Use the current directory as the project
export PROJECT_DIR="$PWD"

# Set COMPOSE_FILE and COMPOSE_PROJECT_NAME, used by `docker compose`; the
# project name must differ from the egress-open mode's so they get separate
# networks/containers instead of clashing over shared ones
export COMPOSE_FILE="$SANDBOX_DIR/compose.yml"
export COMPOSE_PROJECT_NAME="claude-sandbox-egress-filtered"

# Make sure proxy is running
docker compose up -d proxy

# Run Claude interactively, forwarding any extra args
docker compose run --rm claude claude "$@"
