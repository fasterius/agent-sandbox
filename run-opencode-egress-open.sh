#!/usr/bin/env bash
set -euo pipefail

# Same as `run-opencode-egress-filtered.sh`, but with unrestricted egress:
# layers `compose-opencode-egress-open.yml` on top of `compose-opencode.yml` to
# drop the proxy and open up `opencode-net`, instead of going through the
# tinyproxy allow-list

# Refuse to run in any directory listed in `blocked-dirs`
SANDBOX_DIR="$(dirname "$0")"
source "$SANDBOX_DIR/check-dir.sh"

# Use a separate external home directory from
# `run-opencode-egress-filtered.sh`, so this mode can have its own config
export OPENCODE_HOME="$HOME/.opencode-sandbox-home-egress-open"
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

# Set COMPOSE_FILE and COMPOSE_PROJECT_NAME, used by `docker compose`; the
# project name must differ from the egress-filtered mode's so they get
# separate networks/containers instead of clashing over shared ones
export COMPOSE_FILE="$SANDBOX_DIR/compose-opencode.yml:$SANDBOX_DIR/compose-opencode-egress-open.yml"
export COMPOSE_PROJECT_NAME="opencode-sandbox-egress-open"

# Make sure the Ollama forwarder is running
docker compose up -d ollama

# Run OpenCode interactively, forwarding any extra args; `--no-deps` skips the
# proxy, which is not used in this mode
docker compose run --rm --no-deps opencode opencode "$@"
