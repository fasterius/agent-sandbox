# Coding agent sandbox

A Docker Compose setup for running a coding agent against an arbitrary local
project directory, isolated from the rest of the host and with outbound
network access restricted to an allow-list. Two agents are supported:
[Claude Code](https://github.com/anthropics/claude-code), and
[OpenCode](https://opencode.ai) with a local model served by Ollama on the
host (see [OpenCode with a local model](#opencode-with-a-local-model)).

- The agent container has **no direct route to the internet**: the only
  things it can reach are the `proxy` container and, for OpenCode, a forwarder
  to Ollama on the host.
- The `proxy` (tinyproxy) container is the sole egress path, and only forwards
  requests to hosts matching the agent's allow-list
  ([`proxy/filter-claude`](./proxy/filter-claude) for Claude Code,
  [`proxy/filter-opencode`](./proxy/filter-opencode) for OpenCode): package
  and workflow registries such as Conda, Pixi, Nextflow and Bioconductor, plus
  the Anthropic API for Claude Code.
- All containers run with all Linux capabilities dropped (`cap_drop: ALL`)
  and `no-new-privileges`, and the agent containers have memory/CPU/PID
  limits.
- Either agent can instead be run with unrestricted egress, keeping the rest
  of the hardening (see [Egress modes](#egress-modes)).

## Requirements

- Docker and Docker Compose
- For OpenCode: [Ollama](https://ollama.com) running on the host

## Usage

Run an agent with [`run-agent.sh`](./run-agent.sh), giving the agent
(`claude` or `opencode`) and the egress mode (`filtered` or `open`):

```bash
cd /path/to/your/project
/path/to/this/repo/run-agent.sh claude filtered [optional args]
```

The script can be run from any directory: it uses `$PWD` as the project to
mount. Any extra arguments are forwarded to the agent's CLI, _e.g._:

```bash
run-agent.sh claude filtered -p "summarise this repository"
```

The agent's image is built from the included [`Dockerfile`](./Dockerfile) the
first time it is run. To build the images manually (the environment variables
are not used during build but are required, so initialise them to the current
directory):

```bash
PROJECT_DIR=. CLAUDE_HOME=. docker compose -f compose/claude.yml build
PROJECT_DIR=. OPENCODE_HOME=. docker compose -f compose/opencode.yml build
```

The agents share the hardening ([`compose/common.yml`](./compose/common.yml)),
the base image layers and the blocked-directories check, but are otherwise
separate: each has its own image (built from its own target of the
`Dockerfile`), compose file (`compose/<agent>.yml`), allow-list, compose
project and networks.

## What gets mounted

- Your project directory (`$PWD` when you invoke the script) is mounted at
  `/home/dev/workspace` inside the container — this is what the agent can read
  and edit.
- A home directory on the host, outside this repository, is mounted as the
  container's `$HOME` (`/home/dev`). This is where the agent persists its
  config, credentials and session history _between runs of the sandbox_. Each
  agent and egress mode has its own, `~/.<agent>-sandbox-home-egress-<mode>`
  (_e.g._ `~/.claude-sandbox-home-egress-filtered`), so each can have its own
  config and credentials. It contains real secrets once you've logged in —
  treat it like any other credentials directory.

## Egress modes

### Filtered

In the `filtered` mode all egress goes through the proxy, which only allows
hosts on the agent's allow-list. To extend it, add an anchored regular
expression line to `proxy/filter-claude` or `proxy/filter-opencode` (_e.g._
`^some\.host\.com$`), and restart the proxy with the
[`restart-proxy.sh`](./restart-proxy.sh) script, naming the agent whose
allow-list changed:

```bash
/path/to/this/repo/restart-proxy.sh claude
```

### Open

The `open` mode runs the agent with no egress limits:

```bash
cd /path/to/your/project
/path/to/this/repo/run-agent.sh claude open [optional args]
```

This layers `compose/<agent>-egress-open.yml` on top of `compose/<agent>.yml`,
skipping the proxy. The other hardening (dropped capabilities,
`no-new-privileges`, memory/CPU/PID limits) still applies; only the network
restriction is lifted. For OpenCode, this mode also re-enables model catalogue
fetching and language server downloads, which are disabled in the `filtered`
mode since the allow-list blocks them; Ollama is still reached through the
forwarder.

## Agents

### Claude Code

The first time you run Claude Code in a given mode you'll have to authenticate
outside of the sandbox, but subsequent sessions will use the credentials that
have now been stored in that mode's home directory. Each mode's home directory
can also hold its own `CLAUDE.md` instructions.

### OpenCode with a local model

OpenCode runs against a model served by Ollama, which runs natively on the
host rather than in a container and is reached through the forwarder.

On first run in a given mode,
[`opencode/opencode-default.json`](./opencode/opencode-default.json) is copied
to `.config/opencode/opencode.json` in that mode's home directory; edit that
copy to add or change models. Model names must match those listed by `ollama
list` on the host.

A TUI config, [`opencode/tui-default.json`](./opencode/tui-default.json), is
copied to `.config/opencode/tui.json` alongside it; this enables attention
desktop notifications when the terminal is blurred, with the attention sound
disabled.

OpenCode needs a context window of at least 64k tokens, which is larger than
Ollama's default.

## Blocked directories

The run script refuses to run in any directory listed in
[`blocked-dirs`](./blocked-dirs), such as your home directory, credential
directories like `~/.ssh` and system directories; add and remove entries as you
see fit. A plain entry blocks only that exact directory, while an entry ending
in `/**` also blocks everything below it. Symlinks are resolved before matching
and matching is case-insensitive.

## Resource limits

The agent containers are limited to 4 GB of memory, 2 CPUs and 512 processes,
which can be overridden:

```bash
SANDBOX_MEMORY=16g SANDBOX_CPUS=6 SANDBOX_PIDS=4096 \
    /path/to/this/repo/run-agent.sh claude filtered
```
