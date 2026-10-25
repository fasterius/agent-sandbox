#!/usr/bin/env bash

# Checks a directory against a list of blocked directories; sourced by
# `agent-sandbox`

# Succeeds unless `dir` matches an entry in `blocklist`, in which case it prints
# an error. Symlinks are resolved first, so that they can't be used to get
# around the list, and matching is case-insensitive
check_dir() {
    local blocklist="$1" dir home line entry base
    if [[ ! -f "$blocklist" ]]; then
        echo "Error: blocklist '$blocklist' not found" >&2
        return 1
    fi
    dir="$(cd "$2" && pwd -P | tr '[:upper:]' '[:lower:]')" || return 1
    home="$(cd "$HOME" && pwd -P)" || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do

        # Strip comments and surrounding whitespace, and skip empty lines
        entry="${line%%#*}"
        entry="$(echo "$entry" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [[ -z "$entry" ]] && continue

        # Expand a leading `~` and lowercase
        # shellcheck disable=SC2088
        if [[ "$entry" == "~" || "$entry" == "~/"* ]]; then
            entry="$home${entry:1}"
        fi
        entry="$(echo "$entry" | tr '[:upper:]' '[:lower:]')"

        # The entries are matched as patterns, so they are left unquoted
        # shellcheck disable=SC2053
        if [[ "$entry" == */\*\* ]]; then
            # Block the directory and everything below it
            base="${entry%/\*\*}"
            [[ "$dir" == $base || "$dir" == $base/* ]] || continue
        else
            # Block only this exact directory; a trailing slash is ignored
            # except for `/` itself
            [[ "$entry" != "/" ]] && entry="${entry%/}"
            [[ "$dir" == $entry ]] || continue
        fi
        echo "Error: refusing to run in '$2' (blocked by '$line' in" \
            "'$blocklist')" >&2
        return 1
    done < "$blocklist"
}
