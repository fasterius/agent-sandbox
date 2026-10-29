#!/usr/bin/env bash

# Per-project data; sourced by `agent-sandbox`

# Prints an ID for the project directory: its name, lowercased and limited to
# the characters Compose allows in project names, followed by a checksum of its
# full path, so that projects with the same name get different IDs
project_id() {
    local name checksum
    name="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
    name="$(printf '%s' "$name" | tr -c 'a-z0-9_-' '-')"
    checksum="$(printf '%s' "$1" | cksum | cut -d ' ' -f 1)"
    echo "$name-$checksum"
}
