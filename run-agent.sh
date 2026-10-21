#!/usr/bin/env bash
set -euo pipefail

# Run an agent in the sandbox with the current directory as the project.
# In the `filtered` mode all egress goes through the proxy and its allow-list
# (`proxy/filter-<agent>`); the `open` mode layers
# `compose/<agent>-egress-open.yml` on top of `compose/<agent>.yml` to drop
# the proxy and allow any egress.

usage() {
    echo "Usage: $(basename "$0") <claude|opencode> <filtered|open>" \
        "[agent args]" >&2
    exit 1
}

[[ $# -ge 2 ]] || usage
AGENT="$1"
MODE="$2"
shift 2

case "$AGENT" in claude | opencode) ;; *) usage ;; esac
case "$MODE" in filtered | open) ;; *) usage ;; esac

# Refuse to run in any directory listed in `blocked-dirs`
SANDBOX_DIR="$(dirname "$0")"
source "$SANDBOX_DIR/lib/check-dir.sh"

# Use the current directory as the project
export PROJECT_DIR="$PWD"

# Each agent and mode gets its own compose project, so that they get separate
# networks/containers instead of clashing over shared ones, and its own
# external home directory, so that each can have its own config and
# credentials
export COMPOSE_PROJECT_NAME="$AGENT-sandbox-egress-$MODE"
export COMPOSE_FILE="$SANDBOX_DIR/compose/$AGENT.yml"
if [[ "$MODE" == "open" ]]; then
    COMPOSE_FILE="$COMPOSE_FILE:$SANDBOX_DIR/compose/$AGENT-egress-open.yml"
fi
AGENT_HOME="$HOME/.$AGENT-sandbox-home-egress-$MODE"
mkdir -p "$AGENT_HOME"

# Copy a default config file into the agent's home directory on first run;
# edit the copy to change it
seed_config() {
    local source="$1" target="$AGENT_HOME/$2"
    if [[ ! -f "$target" ]]; then
        mkdir -p "$(dirname "$target")"
        cp "$SANDBOX_DIR/$source" "$target"
    fi
}

# Agent-specific settings: the home directory variable used by the compose
# file, config files to seed and supporting services besides the proxy
SERVICES=""
case "$AGENT" in
    claude)
        export CLAUDE_HOME="$AGENT_HOME"
        ;;
    opencode)
        export OPENCODE_HOME="$AGENT_HOME"
        seed_config opencode/opencode-default.json \
            .config/opencode/opencode.json
        seed_config opencode/tui-default.json .config/opencode/tui.json
        SERVICES="ollama"
        ;;
esac

# Make sure the supporting services are running; `--no-deps` skips the proxy
# when running the agent in the open mode, which does not use it
RUN_ARGS=(--rm)
if [[ "$MODE" == "filtered" ]]; then
    SERVICES="proxy $SERVICES"
else
    RUN_ARGS+=(--no-deps)
fi
if [[ -n "${SERVICES// /}" ]]; then
    docker compose up -d $SERVICES
fi

# Run the agent interactively, forwarding any extra args
exec docker compose run "${RUN_ARGS[@]}" "$AGENT" "$AGENT" "$@"
