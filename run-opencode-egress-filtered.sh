#!/usr/bin/env bash
set -euo pipefail

# Run OpenCode in the sandbox against Ollama running natively on the host,
# with the same egress filtering as `run-claude-egress-filtered.sh`, but with
# its own allow-list (`filter-opencode`), image, networks and home directory

# Refuse to run in any directory listed in `blocked-dirs`
SANDBOX_DIR="$(dirname "$0")"
source "$SANDBOX_DIR/check-dir.sh"

# Use a dedicated external home directory and make sure it exists
export OPENCODE_HOME="$HOME/.opencode-sandbox-home-egress-filtered"
mkdir -p "$OPENCODE_HOME"

# Seed the OpenCode config on first run; edit the copy in `OPENCODE_HOME` to
# change models
OPENCODE_CONFIG="$OPENCODE_HOME/.config/opencode/opencode.json"
if [[ ! -f "$OPENCODE_CONFIG" ]]; then
    mkdir -p "$(dirname "$OPENCODE_CONFIG")"
    cp "$SANDBOX_DIR/opencode-default.json" "$OPENCODE_CONFIG"
fi

# Seed the OpenCode TUI config on first run (notably enables attention
# notifications without sound); edit the copy in `OPENCODE_HOME` to change it
OPENCODE_TUI_CONFIG="$OPENCODE_HOME/.config/opencode/tui.json"
if [[ ! -f "$OPENCODE_TUI_CONFIG" ]]; then
    cp "$SANDBOX_DIR/tui-default.json" "$OPENCODE_TUI_CONFIG"
fi

# Use the current directory as the project
export PROJECT_DIR="$PWD"

# Set COMPOSE_FILE and COMPOSE_PROJECT_NAME, used by `docker compose`
export COMPOSE_FILE="$SANDBOX_DIR/compose-opencode.yml"
export COMPOSE_PROJECT_NAME="opencode-sandbox-egress-filtered"

# Make sure the proxy and the Ollama forwarder are running
docker compose up -d proxy ollama

# Run OpenCode interactively, forwarding any extra args
docker compose run --rm opencode opencode "$@"
