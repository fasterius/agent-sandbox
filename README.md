# Coding agent sandbox

A Docker Compose setup for running a coding agent against an arbitrary local
project directory, isolated from the rest of the host and optionally with
outbound network access restricted to an allow-list. Two agents are supported:
[Claude Code](https://github.com/anthropics/claude-code), and
[OpenCode](https://opencode.ai) with a local model served by
[llama.cpp](https://github.com/ggml-org/llama.cpp) on the host (see [OpenCode
with a local model](#opencode-with-a-local-model)).

- The agent only sees the project directory and its own home directory; the rest
  of the host file system is not mounted.
- All containers run with all Linux capabilities dropped (`cap_drop: ALL`) and
  `no-new-privileges`, and the agent containers have memory/CPU/PID limits.
- In the `filtered` egress mode the agent container has **no direct route to the
  internet**: the only things it can reach are the `proxy` (tinyproxy)
  container, which only forwards requests to hosts on the agent's allow-list,
  and, for OpenCode, a forwarder to the model server on the host (see [Egress
  modes](#egress-modes)).

## Requirements

- Docker and Docker Compose
- For OpenCode: a model server with an OpenAI-compatible API on port 8080 of the
  host, _e.g._ `llama.cpp`.

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
forwarder to the model server).

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
For OpenCode, the model server is still reached through the forwarder.

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

Personal configuration goes in `~/.config/agent-sandbox/`, outside this
repository and outside any directory the agent can be run in. All files are
optional:

| File                     | Effect                                    |
| ------------------------ | ----------------------------------------- |
| `blocked-dirs`           | Adds to [`blocked-dirs`](./blocked-dirs)  |
| `allow-common`           | Adds to the allow-lists of all agents     |
| `allow-<agent>`          | Adds to the allow-list of that agent only |
| `opencode/opencode.json` | Replaces OpenCode's config                |
| `opencode/tui.json`      | Replaces OpenCode's TUI config            |

## Agents

### Claude Code

The first time you run Claude Code in a given mode you'll have to authenticate
outside of the sandbox, but subsequent sessions will use the credentials that
have now been stored in that mode's home directory. Each mode's home directory
can also hold its own `CLAUDE.md` instructions.

### OpenCode with a local model

OpenCode runs against a model server that runs natively on the host rather than
in a container, and is reached through the forwarder at
`http://llm.internal:8080/v1`. Any server with an OpenAI-compatible API
listening on port 8080 of the host works; the defaults assume `llama.cpp`.

The models are listed in OpenCode's config, starting from
[`opencode/opencode-default.json`](./opencode/opencode-default.json); model
names must match those served by the model server, _i.e._ the section names in
the `llama.cpp` presets file. The config can be given in two ways:

- **Per user:** if `~/.config/agent-sandbox/opencode/opencode.json` exists, it
  is mounted read-only into the container, so that it applies to all egress
  modes and can't be changed by the agent.
- **Per mode:** otherwise, the default is copied to the container's
  `.config/opencode/opencode.json` in that mode's home directory on first run;
  edit that copy to add or change models.

The TUI config, [`opencode/tui-default.json`](./opencode/tui-default.json), is
handled the same way, with `~/.config/agent-sandbox/opencode/tui.json` as the
per-user file.

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
