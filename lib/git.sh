#!/usr/bin/env bash

# Protection of a project's git settings; sourced by `agent-sandbox`

# Prints the read-only mounts, one `source:target:ro` per line, of the git
# settings and hooks of the repository at the top of `project` and of its
# submodules, which keep theirs under `.git/modules/`. Git on the host runs
# commands from them (_e.g._ `core.fsmonitor` on every `git status`), while the
# agent can still stage and commit. An empty hooks directory is created if
# missing, so that the agent can't add one
git_mounts() {
    local git_dir="$1/.git" dir file
    [[ -d "$git_dir" ]] || return 0
    while IFS= read -r dir; do
        mkdir -p "$dir/hooks"
        echo "$dir/hooks:$dir/hooks:ro"
        for file in config config.worktree; do
            if [[ -f "$dir/$file" ]]; then
                echo "$dir/$file:$dir/$file:ro"
            fi
        done
    done < <(
        echo "$git_dir"
        find "$git_dir/modules" -name config -type f -exec dirname {} \; \
            2> /dev/null
    )
}
