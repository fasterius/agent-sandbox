# Coding agent sandbox

A Docker Compose setup for running a coding agent against an arbitrary local
project directory, isolated from the rest of the host and optionally with
outbound network access restricted to an allow-list. Two agents are
supported: [Claude Code](https://github.com/anthropics/claude-code), and
[OpenCode](https://opencode.ai) with a local model served by Ollama on the
host (see [OpenCode with a local model](#opencode-with-a-local-model)).

- The agent only sees the project directory and its own home directory; the rest
  of the host file system is not mounted.
- All containers run with all Linux capabilities dropped (`cap_drop: ALL`) and
  `no-new-privileges`, and the agent containers have memory/CPU/PID limits.
- In the `filtered` egress mode the agent container has **no direct route to the
  internet**: the only things it can reach are the `proxy` (tinyproxy)
  container, which only forwards requests to hosts on the agent's allow-list,
  and, for OpenCode, a forwarder to Ollama on the host (see [Egress
  modes](#egress-modes)).

## Requirements

- Docker and Docker Compose
- For OpenCode: [Ollama](https://ollama.com) running on the host

## Installation

Clone this repository and link the [`agent-sandbox`](./agent-sandbox) script
into a directory on your `PATH`, _e.g._:

```bash
ln -s /path/to/this/repo/agent-sandbox ~/.local/bin/agent-sandbox
```

## Usage

Run an agent (`claude` or `opencode`) from the project directory you want it
to work on:

```bash
cd /path/to/your/project
agent-sandbox [options] <agent> [agent args]
```

The current directory is mounted as the project. Any arguments after the
agent are forwarded to the agent's CLI, _e.g._:

```bash
agent-sandbox claude -p "summarise this repository"
agent-sandbox --filtered --memory 8g claude
```

Options must come before the agent; anything after it is passed on unchanged.
`--filtered` restricts egress to the allow-list (see [Egress
modes](#egress-modes)); the other options can also be set with an environment
variable, which the option overrides when both are given:

| Option            | Environment variable | Default | Description              |
| ----------------- | -------------------- | ------- | ------------------------ |
| `--arch <arch>`   | `SANDBOX_ARCH`       | `arm64` | Image architecture       |
| `--memory <size>` | `SANDBOX_MEMORY`     | `4g`    | Memory limit             |
| `--cpus <n>`      | `SANDBOX_CPUS`       | `2`     | CPU limit                |
| `--pids <n>`      | `SANDBOX_PIDS`       | `512`   | Process and thread limit |

Run `agent-sandbox --help` for a summary.

The agent's image is built from the included [`Dockerfile`](./Dockerfile) the
first time it is run, and is not updated after that. To update the packages and
services, rebuild the image:

```bash
agent-sandbox [--arch arm64] build <agent>
```

This rebuilds the image from scratch with the latest base images, and also pulls
the latest images of the supporting services (the proxy and, for OpenCode, the
forwarder to Ollama).

The agents share the hardening ([`compose/common.yml`](./compose/common.yml)),
the base image layers and the blocked-directories check, but are otherwise
separate: each has its own image (built from its own target of the
`Dockerfile`), compose file (`compose/<agent>.yml`), allow-list, compose project
and networks.

## What gets mounted

- Your project directory (the current directory when you run `agent-sandbox`) is
  mounted at `/home/dev/workspace` inside the container — this is what the agent
  can read and edit.
- A home directory on the host, outside this repository, is mounted as the
  container's `$HOME` (`/home/dev`). This is where the agent persists its
  config, credentials and session history _between runs of the sandbox_. Each
  agent and egress mode has its own,
  `~/.local/share/agent-sandbox/<agent>-<mode>` (_e.g._
  `~/.local/share/agent-sandbox/claude-open`), so each can have its own config
  and credentials. It contains real secrets once you've logged in — treat it
  like any other credentials directory.

## Egress modes

### Open

The default `open` mode runs the agent with no egress limits, by layering
`compose/<agent>-egress-open.yml` on top of `compose/<agent>.yml` and skipping
the proxy. The other hardening (dropped capabilities, `no-new-privileges`,
memory/CPU/PID limits) still applies; only the network restriction is lifted.
For OpenCode, Ollama is still reached through the forwarder.

### Filtered

In the `filtered` mode all egress goes through the proxy, which only allows
hosts on the agent's allow-list:

```bash
agent-sandbox --filtered claude
```

The allow-list is combined from the defaults in this repository and your own
additions (see [Per-user configuration](#per-user-configuration)):
[`proxy/allow-common`](./proxy/allow-common) holds package and workflow
registries such as Conda, Pixi, Nextflow and Bioconductor, used by both agents,
and [`proxy/allow-claude`](./proxy/allow-claude) adds the Anthropic API for
Claude Code. Each line is an anchored regular expression, _e.g._
`^some\.host\.com$`.

Changes to the allow-lists are picked up the next time the agent is started in
this mode, which recreates the proxy if the combined list changed; restart the
agent to apply them to a running session.

For OpenCode, this mode also disables model catalogue fetching and language
server downloads, which the allow-list would block.

## Per-user configuration

Personal additions go in `~/.config/agent-sandbox/`, outside this repository and
outside any directory the agent can be run in. All files are optional and add to
the defaults in the repository:

| File            | Adds to                           |
| --------------- | --------------------------------- |
| `blocked-dirs`  | [`blocked-dirs`](./blocked-dirs)  |
| `allow-common`  | the allow-lists of all agents     |
| `allow-<agent>` | the allow-list of that agent only |

## Agents

### Claude Code

The first time you run Claude Code in a given mode you'll have to authenticate
outside of the sandbox, but subsequent sessions will use the credentials that
have now been stored in that mode's home directory. Each mode's home directory
can also hold its own `CLAUDE.md` instructions.

### OpenCode with a local model

OpenCode runs against a model served by Ollama, which runs natively on the host
rather than in a container and is reached through the forwarder.

On first run in a given mode,
[`opencode/opencode-default.json`](./opencode/opencode-default.json) is copied
to `.config/opencode/opencode.json` in that mode's home directory; edit that
copy to add or change models. Model names must match those listed by `ollama
list` on the host. A TUI config,
[`opencode/tui-default.json`](./opencode/tui-default.json), is copied to
`.config/opencode/tui.json` alongside it.

OpenCode needs a context window of at least 64k tokens, which is larger than the
default of Ollama.

## Blocked directories

The sandbox refuses to run in any directory listed in
[`blocked-dirs`](./blocked-dirs) or in your own
`~/.config/agent-sandbox/blocked-dirs`, such as your home directory, credential
directories like `~/.ssh` and system directories. A plain entry blocks only that
exact directory, while an entry ending in `/**` also blocks everything below it.
Symlinks are resolved before matching and matching is case-insensitive.

## Architecture

The agent image is built and run for `arm64` by default, which runs natively on
Apple Silicon. It can instead be built and run as `amd64`, which runs under
emulation on Apple Silicon.

```bash
agent-sandbox --arch amd64 claude
```

Each architecture has its own image, so switching does not overwrite the
other.
