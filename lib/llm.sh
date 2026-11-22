#!/usr/bin/env bash

# Connection to the model server of OpenCode; sourced by `agent-sandbox`

# Prints the first IPv4 address of the host name `name`, as seen by the host's
# resolver
resolve_ipv4() {
    local name="$1"
    if [[ "$name" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
        echo "$name"
    elif command -v getent > /dev/null; then
        getent ahostsv4 "$name" | awk 'NR == 1 { print $1 }'
    elif command -v dscacheutil > /dev/null; then
        dscacheutil -q host -a name "$name" |
            awk '/^ip_address:/ { print $2; exit }'
    fi
}

# Prints the `socat` address that the forwarder in front of the model server
# connects to, for a model server at `url` (`http://host[:port]` or
# `https://host[:port]`, without a path). The host name is resolved here, as
# the container's resolver may not know it (_e.g._ names that only the host's
# Tailscale resolves); for `https`, the certificate is checked against the name
llm_upstream() {
    local url="$1" pattern='^(https?)://([^/:]+)(:([0-9]+))?/?$'
    local scheme host port ip
    if [[ ! "$url" =~ $pattern ]]; then
        echo "Error: SANDBOX_LLM_URL must be of the form" \
            "'http(s)://host[:port]' without a path, not '$url'" >&2
        return 1
    fi
    scheme="${BASH_REMATCH[1]}"
    host="${BASH_REMATCH[2]}"
    port="${BASH_REMATCH[4]}"
    if [[ -z "$port" && "$scheme" == https ]]; then
        port=443
    elif [[ -z "$port" ]]; then
        port=80
    fi
    ip="$(resolve_ipv4 "$host")"
    if [[ -z "$ip" ]]; then
        echo "Error: could not resolve '$host' from SANDBOX_LLM_URL" >&2
        return 1
    fi
    if [[ "$scheme" == https ]]; then
        echo "openssl:$ip:$port,snihost=$host,commonname=$host"
    else
        echo "tcp-connect:$ip:$port"
    fi
}
