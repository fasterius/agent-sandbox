#!/usr/bin/env bash

# Sourced by `run-agent.sh`: exits with an error if the current directory
# matches an entry in `blocked-dirs`. Expects `SANDBOX_DIR` to be set.

_check_dir() {
    local blocklist="$SANDBOX_DIR/blocked-dirs"
    local home dir line entry base

    if [[ ! -f "$blocklist" ]]; then
        echo "Error: blocklist '$blocklist' not found" >&2
        return 1
    fi

    # Resolve symlinks so they can't be used to get around the blocklist
    home="$(cd "$HOME" && pwd -P)" || return 1

    # Convert to lowercase for case-insensitive matching
    dir="$(pwd -P | tr '[:upper:]' '[:lower:]')"

    while IFS= read -r line || [[ -n "$line" ]]; do

        # Strip comments and surrounding whitespace
        entry="${line%%#*}"
        entry="$(echo "$entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

        # Skip empty lines
        [[ -z "$entry" ]] && continue

        # Expand a leading `~` and lowercase
        if [[ "$entry" == "~" || "$entry" == "~/"* ]]; then
            entry="$home${entry:1}"
        fi
        entry="$(echo "$entry" | tr '[:upper:]' '[:lower:]')"

        if [[ "$entry" == */\*\* ]]; then
            # Block the directory and everything below it
            base="${entry%/\*\*}"
            if [[ "$dir" == $base || "$dir" == $base/* ]]; then
                echo "Error: refusing to run in '$PWD' (blocked by" \
                    "'$line' in '$blocklist')" >&2
                return 1
            fi
        else
            # Block only this exact directory; a trailing slash is ignored
            # except for `/` itself
            [[ "$entry" != "/" ]] && entry="${entry%/}"
            if [[ "$dir" == $entry ]]; then
                echo "Error: refusing to run in '$PWD' (blocked by" \
                    "'$line' in '$blocklist')" >&2
                return 1
            fi
        fi
    done < "$blocklist"
}

_check_dir || exit 1
unset -f _check_dir
