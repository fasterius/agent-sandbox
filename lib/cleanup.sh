#!/usr/bin/env bash

# Removal of the sandbox's containers and networks; sourced by `agent-sandbox`

# Prints the names of the sandbox's Compose projects that have containers or
# networks
sandbox_projects() {
    {
        docker ps -a --filter label=com.docker.compose.project \
            --format '{{.Label "com.docker.compose.project"}}'
        docker network ls --filter label=com.docker.compose.project \
            --format '{{.Label "com.docker.compose.project"}}'
    } | grep -E '^(claude|opencode)-sandbox-' | sort -u || true
}

# Succeeds if an agent or `--shell` container of the Compose project is running;
# these are the ones started with `docker compose run`, which Compose labels as
# one-off containers
agent_running() {
    [[ -n "$(docker ps -q --filter "label=com.docker.compose.project=$1" \
        --filter label=com.docker.compose.oneoff=True)" ]]
}

# Removes the containers and networks of the Compose project
remove_project() {
    local ids
    ids="$(docker ps -aq --filter "label=com.docker.compose.project=$1")"
    if [[ -n "$ids" ]]; then
        # shellcheck disable=SC2086
        docker rm -f $ids > /dev/null
    fi
    ids="$(docker network ls -q --filter "label=com.docker.compose.project=$1")"
    if [[ -n "$ids" ]]; then
        # shellcheck disable=SC2086
        docker network rm $ids > /dev/null
    fi
}

# Removes the containers and networks of all the sandbox's Compose projects
# without a running agent, and lists the projects with data in `data_dir` whose
# directory no longer exists
cleanup() {
    local data_dir="$1" project dir path
    for project in $(sandbox_projects); do
        if agent_running "$project"; then
            echo "Keeping $project, which has a running agent"
        else
            echo "Removing $project"
            remove_project "$project"
        fi
    done
    for dir in "$data_dir"/projects/*/; do
        [[ -f "$dir/path" ]] || continue
        path="$(cat "$dir/path")"
        if [[ ! -d "$path" ]]; then
            echo "Project $path no longer exists; delete ${dir%/} to remove" \
                "its sandbox data"
        fi
    done
}
