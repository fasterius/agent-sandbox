#!/usr/bin/env bash

# The agent's personal instructions; sourced by `agent-sandbox`, which sets
# `SANDBOX_DIR`

# Prints the personal instruction files that exist, followed by a description of
# the sandbox for the architecture and egress mode
generate_instructions() {
    local arch="$1" egress="$2" platform other_arch source
    shift 2
    case "$arch" in
        arm64) platform="linux-aarch64" other_arch="amd64" ;;
        amd64) platform="linux-64" other_arch="arm64" ;;
    esac
    for source in "$@"; do
        if [[ -f "$source" ]]; then
            cat "$source"
            echo
        fi
    done
    sed -e "s/@ARCH@/$arch/" -e "s/@PLATFORM@/$platform/" \
        -e "s/@OTHER_ARCH@/$other_arch/" "$SANDBOX_DIR/instructions/sandbox.md"
    if [[ "$egress" != "open" ]]; then
        echo
        cat "$SANDBOX_DIR/instructions/egress-$egress.md"
    fi
}
