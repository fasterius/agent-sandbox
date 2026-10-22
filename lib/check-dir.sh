#!/usr/bin/env bash

# Sourced by `agent-sandbox`: exits with an error if the current directory
# matches an entry in the default `blocked-dirs` or in the optional per-user
# one. Expects `SANDBOX_DIR` and `CONFIG_DIR` to be set.

_check_dir() {
    local blocklist="$1"
    local home dir line entry base

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

if [[ ! -f "$SANDBOX_DIR/blocked-dirs" ]]; then
    echo "Error: blocklist '$SANDBOX_DIR/blocked-dirs' not found" >&2
    exit 1
fi
_check_dir "$SANDBOX_DIR/blocked-dirs" || exit 1


if [[ -f "$CONFIG_DIR/blocked-dirs" ]]; then
    _check_dir "$CONFIG_DIR/blocked-dirs" || exit 1
fi

unset -f _check_dir
