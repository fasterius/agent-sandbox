# Coding agent sandbox

_An attempt at a setup for running coding agents where you don't want them to
have access to your entire computer, without having to trust the harness
itself._

These are the problems that this sandbox attempts to solve:

- Agents should not have the capability to access files outside of the directory
  where they were started.
- Agents should not be able to run in sensitive directories, such as your home
  directory, `~/.ssh` or system directories.
- Agents should not be able to change their own instructions.
- Agents should not be able to push code to Git with your credentials.
- Agents should not share information across projects.
- Network egress should be able to be limited or restricted.

Briefly, this sandbox is built using Docker, which isolates the agents from the
rest of the host. Two agents are supported: [Claude
Code](https://github.com/anthropics/claude-code), and
[OpenCode](https://opencode.ai) with a local model served by
[llama.cpp](https://github.com/ggml-org/llama.cpp) on the host.

These are not the only potential issues with agents, and the sandbox only covers
some of them. In particular:

- In the default mode, agents can reach anything on the internet, your local
  network and services on your computer.
- Claude Code _always_ sends data to Anthropic, even in the `closed` mode.
- Agents can change files in your project that you then run outside the sandbox;
  carefully review all changes before you run anything.
- The sandbox is a container, so a kernel vulnerability could let an agent
  escape it.

## Requirements

- Docker Engine 23 and Docker Compose 2.33 or later.
- For OpenCode: a model server with an OpenAI-compatible API on port 8080 of the
  host, _e.g._ `llama.cpp` (see [OpenCode with a local
  model](#opencode-with-a-local-model)).

## Installation

Clone this repository and link the [`agent-sandbox`](./agent-sandbox) script
into a directory on your `PATH`, _e.g._:

```bash
ln -s /path/to/this/repo/agent-sandbox ~/.local/bin/agent-sandbox
```

Claude Code also needs a long-lived login token, which you create once with
`claude setup-token`; you can use the sandbox to create a token using the
`--shell` mode:

```bash
agent-sandbox --shell claude claude setup-token
```

Follow the link to log in, then save the token it prints in
`~/.local/share/agent-sandbox/claude-oauth-token` and make it readable only by
you (`chmod 600`). See [Claude Code](#claude-code) for what the token gives
access to.

## Usage

Run an agent (`claude` or `opencode`) from the project directory you want it to
work on:

```bash
cd /path/to/your/project
agent-sandbox [sandbox options] <agent> [agent options]
```

Options must come before the agent; anything after it is passed on to the agent
itself. The first time you run an agent it will begin with building the Docker
image, so it will take longer that first time. The sandbox refuses to run in
sensitive directories such as your home directory, `~/.ssh` or system
directories (see [Blocked directories](#blocked-directories)).

### Network access

The egress mode sets what the agent can reach over the network (see [Egress
modes](#egress-modes) for details):

| Option     | Mode     | The agent can reach    |
| ---------- | -------- | ---------------------- |
| (none)     | `open`   | Anything               |
| `--closed` | `closed` | Only the agent's model |

### Options

The other options can also be set with an environment variable, which the option
overrides when both are given:

| Option            | Environment variable | Default | Description              |
| ----------------- | -------------------- | ------- | ------------------------ |
| `--arch <arch>`   | `SANDBOX_ARCH`       | `arm64` | Image architecture       |
| `--memory <size>` | `SANDBOX_MEMORY`     | `4g`    | Memory limit             |
| `--cpus <n>`      | `SANDBOX_CPUS`       | `2`     | CPU limit                |
| `--pids <n>`      | `SANDBOX_PIDS`       | `512`   | Process and thread limit |

Run `agent-sandbox --help` for a summary, including `--shell` (see
[Shell](#shell)) and `--cleanup` (see [Cleaning up](#cleaning-up)).

## Configuration

Personal configuration goes in `~/.config/agent-sandbox/`, outside this
repository and outside any directory the agent can be run in. All files are
optional:

| File           | Effect                                                                      |
| -------------- | --------------------------------------------------------------------------- |
| `blocked-dirs` | Adds to [`blocked-dirs`](./blocked-dirs)                                    |
| `AGENTS.md`    | Instructions for all agents (see [Agent instructions](#agent-instructions)) |
| `<agent>/`     | Config files for that agent                                                 |

Each file in `<agent>/` (`claude/` or `opencode/`) is mounted read-only into the
agent's config directory (`~/.claude/` or `~/.config/opencode/`) in all egress
modes, in place of the file with the same name in the agent's home directory,
_e.g._ `opencode/opencode.json` or `claude/settings.json`. The exception is the
agent's instructions file (`claude/CLAUDE.md` or `opencode/AGENTS.md`), which is
added to its instructions instead. As the agent can't change these files,
settings changed from within the agent that are stored in them aren't saved;
edit the files instead. Changes take effect the next time the agent is started.

For an example configuration, see [this
example](https://github.com/fasterius/dotfiles/tree/main/agent-sandbox).

### Blocked directories

The sandbox refuses to run in any directory listed in
[`blocked-dirs`](./blocked-dirs) or in your own
`~/.config/agent-sandbox/blocked-dirs`. A plain entry blocks only that exact
directory, while an entry ending in `/**` also blocks everything below it.
Symlinks are resolved before matching and matching is case-insensitive.

### Agent instructions

On each start, the sandbox generates the agent's instructions file and mounts it
read-only into the container. It combines, in order:

1. `~/.config/agent-sandbox/AGENTS.md`: instructions for all agents.
2. `~/.config/agent-sandbox/<agent>/CLAUDE.md` or `AGENTS.md`: instructions for
   that agent only.
3. [`instructions/sandbox.md`](./instructions/sandbox.md): a description of the
   sandbox, with the container's architecture filled in.
4. In the `closed` mode,
   [`instructions/egress-closed.md`](./instructions/egress-closed.md): the
   network restrictions.

The generated files are kept in the project's directory inside
`~/.local/share/agent-sandbox/projects/`. These instructions only cover what
would be _e.g._ `~/.claude/CLAUDE.md` in your home directory, were you running
Claude without the sandbox; you can still use _e.g._ `CLAUDE.md` or `AGENTS.md`
inside your project repository like normal.

## Reference

The rest of this README describes how the sandbox works in more detail:

- [Egress modes](#egress-modes)
- [Isolation](#isolation)
- [Git](#git)
- [Agents](#agents)
- [Shell](#shell)
- [Maintenance](#maintenance)

### Egress modes

#### Open

The default `open` mode runs the agent with no egress limits. The other
hardening (see [Isolation](#isolation)) still applies; only the network
restriction is lifted. For OpenCode, the model server is still reached through
the forwarder.

#### Closed

In the `closed` mode the agent can only reach its model, and nothing else:

```bash
agent-sandbox --closed opencode
```

The agent container has no direct route to the internet. Claude Code can only
reach a proxy (tinyproxy), which only allows the hosts in
[`proxy/model-claude`](./proxy/model-claude). OpenCode can only reach the
forwarder to the model server, so its model catalogue fetching and language
server downloads are disabled in this mode.

### Isolation

All containers run with all Linux capabilities dropped (`cap_drop: ALL`),
`no-new-privileges` and Docker's default seccomp profile (`seccomp:builtin`),
which blocks system calls that containers don't need, such as creating user
namespaces. The agent containers also have memory, CPU and PID limits (see
[Options](#options)).

The agent only sees two directories of the host:

- Your project directory (the current directory when you run `agent-sandbox`) is
  mounted at the same path inside the container, which the agent starts in —
  this is what the agent can read and edit. Claude Code keeps its session
  history and memory per project path, so each project gets its own.
- A home directory on the host, outside this repository, is mounted as the
  container's `$HOME` (`/home/dev`). This is where the agent persists its config
  and session history _between runs of the sandbox_. Each project has its own
  for each agent in `~/.local/share/agent-sandbox/projects/<id>/<agent>`, where
  `<id>` is the project directory's name followed by a checksum of its path
  (_e.g._ `~/.local/share/agent-sandbox/projects/my-project-1234567890/claude`).

Agents in different projects therefore share no writable files: one project's
agent can't read another's session history, and nothing it leaves in its home
directory, such as a skill, plugin or shell setting, reaches other projects.
Each project also gets its own Compose project, with its own networks and
supporting services (the proxy for Claude Code and the forwarder to the model
server for OpenCode), so agents in different projects can't reach each other
over the network either. What's still shared is read-only: the images, your
per-user configuration and the agent instructions, plus the model server for
OpenCode.

A project's data is kept together in its directory in
`~/.local/share/agent-sandbox/projects/`, along with the project's path and the
generated files the sandbox mounts. Moving or renaming a project gives it a new
directory there; move its data along by renaming the old one to the new ID.

### Git

The project's `.git/config` (plus `.git/config.worktree`, if present),
`.git/hooks/` and submodules under `.git/modules/` are mounted read-only into
the container, so that an agent can't use them to run commands outside the
sandbox, as is a hooks directory inside the project that the repository uses
instead (`core.hooksPath`, _e.g._ `.husky/`). Agents can still stage, commit,
branch, merge and so on, but can't change the repository's settings with _e.g._
`git config` or `git remote add`.

This only applies to a repository at the top of the project that exists when the
sandbox starts. Repositories that the agent creates during a session and other
repositories inside the project aren't protected. In a project whose `.git` is a
file, such as a linked worktree, the repository isn't protected either, and git
doesn't work in the container, as the repository itself is outside of the
project. Other files in the project remain writable as well, so carefully review
any changes the agent has made with _e.g._ `git diff` before you run anything
from the project outside the sandbox.

Agents can't push with your credentials, as the container has none for remotes:
your SSH keys, Git credentials and tokens stay outside the sandbox, as neither
your home directory nor `~/.ssh` is mounted. No setting blocks pushing as such,
so in the `open` mode an agent could push with credentials it finds in the
project, _e.g._ a token in a `.env` file or in a remote's URL, or with
credentials given to it through a prompt injection, _e.g._ to someone else's
repository. Keep credentials out of projects you run agents in. In the `closed`
mode, pushing also fails at the proxy, as it only allows the model's hosts.

### Agents

#### Claude Code

Claude Code logs in with a long-lived token (see [Installation](#installation)),
shared by all projects and modes. The token is passed to Claude Code in the
environment, so the agent can read it, as it needs it to reach the model.

Such a token only gives access to the model, so Claude Code in the sandbox has
no access to the features of your claude.ai account: connectors, artifacts,
Claude in Chrome, and cloud and remote sessions. These would otherwise connect
all projects through your account and bypass the egress modes.

#### OpenCode with a local model

OpenCode runs against a model server that runs natively on the host rather than
in a container, and is reached through the forwarder at
`http://llm.internal:8080/v1`. Any server with an OpenAI-compatible API
listening on port 8080 of the host works; the defaults assume `llama.cpp`.

If the model server requires an API key, keep it in a file on the host, by
default `~/.local/share/llama.cpp/api-key`, or set `SANDBOX_LLM_API_KEY_FILE` to
the file's path. The file is mounted read-only at `/run/secrets/llm-api-key`,
and the default config sends its content as the key with `"apiKey":
"{file:/run/secrets/llm-api-key}"`; if there's no file, the key is empty. The
agent can read the key, as it needs it to reach the model.

The models are listed in OpenCode's config,
[`opencode/opencode-default.json`](./opencode/opencode-default.json); model
names must match those served by the model server, _i.e._ the section names in
the `llama.cpp` presets file. The TUI config,
[`opencode/tui-default.json`](./opencode/tui-default.json), enables desktop
notifications without sound and loads the session bell plugin (see [Session
bell](#session-bell)). The defaults are mounted read-only in all egress modes;
to change them, copy them to `~/.config/agent-sandbox/opencode/` as
`opencode.json` or `tui.json` and edit them there (see
[Configuration](#configuration)).

To use the same theme in all modes, set it in a per-user `tui.json` (_e.g._
`"theme": "solarized"`); a theme chosen with `/theme` is only stored in the home
directory of that project and mode.

##### Session bell

OpenCode's built-in notifications use escape sequences that many terminals (such
as Alacritty) and tmux don't support. The
[`session-bell`](./opencode/session-bell-default.ts) plugin rings the terminal
bell when a session completes or needs user attention. tmux highlights the
window in its status line and passes the bell on to the terminal. A per-user
`tui.json` has to load the plugin itself with `"plugin": ["./session-bell.ts"]`.

### Shell

To work in the same environment as an agent without starting the agent itself,
use `--shell`: without anything after the agent it opens an interactive Bash
shell in the agent's container, otherwise it runs the given command there and
exits:

```bash
agent-sandbox --shell opencode
agent-sandbox --shell opencode <CMD>
```

### Maintenance

#### Architecture

The agent image is built and run for `arm64` by default, which runs natively on
Apple Silicon. It can instead be built and run as `amd64`, which runs under
emulation on Apple Silicon:

```bash
agent-sandbox --arch amd64 claude
```

Each architecture has its own image, so switching does not overwrite the other.

#### Updating the images

The agent's image is built from the included [`Dockerfile`](./Dockerfile) the
first time it is run, and is not updated after that. To update the agents and
the packages in the image, rebuild it from this repository with the latest base
images; `--no-cache` is needed as the agents' packages aren't pinned, so a
cached build would keep their old versions:

```bash
cd /path/to/this/repo
docker build --pull --no-cache --platform linux/arm64 --target claude -t claude-sandbox:arm64 .
docker build --pull --no-cache --platform linux/arm64 --target opencode -t opencode-sandbox:arm64 .
```

For the `amd64` image, replace both `arm64` with `amd64`. The image names must
match the `image` of the agent in `compose/<agent>.yml`, or the new image isn't
used. Also pull the latest images of the supporting services, the proxy for
Claude Code and the forwarder to the model server for OpenCode:

```bash
docker pull kalaksi/tinyproxy:latest
docker pull alpine/socat:latest
```

Running containers of the supporting services are recreated with the new images
the next time an agent starts.

#### Cleaning up

When the last session of a project exits, the sandbox removes the project's
supporting services and networks. If a session doesn't get to do so, _e.g._
because its terminal was closed, remove them with:

```bash
agent-sandbox --cleanup
```

This removes the containers and networks of all projects without a running
agent, and lists the data directories of projects whose directory no longer
exists, for you to delete if you don't need them.
