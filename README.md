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
- The agent can change any file in the project, so review its changes before
  running anything from the project on your computer, such as scripts or
  pre-commit hooks (see [Git](#git)).
- All containers run with all Linux capabilities dropped (`cap_drop: ALL`) and
  `no-new-privileges`, and the agent containers have memory/CPU/PID limits.
- In the `filtered` and `closed` egress modes the agent container has **no
  direct route to the internet**: the only things it can reach are the `proxy`
  (tinyproxy) container, which only forwards requests to hosts on the agent's
  allow-list, and, for OpenCode, a forwarder to the model server on the host
  (see [Egress modes](#egress-modes)).

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
`--filtered` restricts egress to the allow-list and `--closed` to the agent's
model (see [Egress modes](#egress-modes)); the other options can also be set
with an environment variable, which the option overrides when both are given:

| Option            | Environment variable | Default | Description              |
| ----------------- | -------------------- | ------- | ------------------------ |
| `--arch <arch>`   | `SANDBOX_ARCH`       | `arm64` | Image architecture       |
| `--memory <size>` | `SANDBOX_MEMORY`     | `4g`    | Memory limit             |
| `--cpus <n>`      | `SANDBOX_CPUS`       | `2`     | CPU limit                |
| `--pids <n>`      | `SANDBOX_PIDS`       | `512`   | Process and thread limit |

Run `agent-sandbox --help` for a summary.

The agents share the hardening ([`compose/common.yml`](./compose/common.yml)),
the base image layers and the blocked-directories check, but are otherwise
separate: each has its own image (built from its own target of the
`Dockerfile`), compose file (`compose/<agent>.yml`), allow-list, compose project
and networks.

## Updating the images

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
used. Also pull the latest images of the supporting services, the proxy and, for
OpenCode, the forwarder to the model server:

```bash
docker pull kalaksi/tinyproxy:latest
docker pull alpine/socat:latest
```

Running containers of the supporting services are recreated with the new images
the next time an agent starts.

## What gets mounted

- Your project directory (the current directory when you run `agent-sandbox`) is
  mounted at the same path inside the container, which the agent starts in —
  this is what the agent can read and edit. Claude Code keeps its session
  history and memory per project path, so each project gets its own.
- A home directory on the host, outside this repository, is mounted as the
  container's `$HOME` (`/home/dev`). This is where the agent persists its
  config, credentials and session history _between runs of the sandbox_. Each
  agent and egress mode has its own,
  `~/.local/share/agent-sandbox/<agent>-<mode>` (_e.g._
  `~/.local/share/agent-sandbox/claude-open`), so each can have its own config
  and credentials. It contains real secrets once you've logged in — treat it
  like any other credentials directory.

## Git

The project's `.git/config` (plus `.git/config.worktree`, if present),
`.git/hooks/` and submodules under `.git/modules/` are mounted read-only into
the container, so that an agent can't use them to run commands outside the
sandbox, as is a hooks directory inside the project that the repository uses
instead (`core.hooksPath`, _e.g._ `.husky/`). Agents can still stage, commit,
branch, merge and so on, but can't change the repository's settings with _e.g._
`git config` or `git remote add`. This only applies to a repository at the top
of the project that exists when the sandbox starts.

Other files in the project that your computer runs remain writable, though, such
as `.pre-commit-config.yaml` (whose hooks `git commit` runs if you use
[pre-commit](https://pre-commit.com)), Makefiles, scripts and pipelines. An
agent could add commands to them that then run outside the sandbox, so review
the changes with _e.g._ `git diff` before running anything from the project
after a session.

Agents can't push, as the container has no credentials for remotes: your SSH
keys, Git credentials and tokens stay on the host, as neither your home
directory nor `~/.ssh` is mounted. No setting blocks pushing as such, so in the
`open` mode an agent could push with credentials it finds in the project, _e.g._
a token in a `.env` file or in a remote's URL; keep credentials out of projects
you run agents in. In the `filtered` and `closed` modes, pushing also fails at
the proxy, as no Git hosts are on the default allow-lists.

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
and [`proxy/model-claude`](./proxy/model-claude) adds the Anthropic API for
Claude Code. Each line is an anchored regular expression, _e.g._
`^some\.host\.com$`.

Changes to the allow-lists are picked up the next time the agent is started in
this mode, which recreates the proxy if the combined list changed; restart the
agent to apply them to a running session.

For OpenCode, this mode also disables model catalogue fetching and language
server downloads, which the allow-list would block.

### Closed

In the `closed` mode the agent can only reach its model, and nothing else:

```bash
agent-sandbox --closed opencode
```

All egress goes through the proxy, which only allows the hosts the agent's model
needs: those in [`proxy/model-claude`](./proxy/model-claude) for Claude Code,
and none for OpenCode, whose model is reached through the forwarder instead.
Your own allow-list additions are not used. Installing packages and downloading
files is therefore not possible in this mode.

## Per-user configuration

Personal configuration goes in `~/.config/agent-sandbox/`, outside this
repository and outside any directory the agent can be run in. All files are
optional:

| File            | Effect                                                                      |
| --------------- | --------------------------------------------------------------------------- |
| `blocked-dirs`  | Adds to [`blocked-dirs`](./blocked-dirs)                                    |
| `allow-common`  | Adds to the `filtered` mode's allow-lists of all agents                     |
| `allow-<agent>` | Adds to the `filtered` mode's allow-list of that agent only                 |
| `AGENTS.md`     | Instructions for all agents (see [Agent instructions](#agent-instructions)) |
| `<agent>/`      | Config files for that agent                                                 |

Each file in `<agent>/` (`claude/` or `opencode/`) is mounted read-only into the
agent's config directory (`~/.claude/` or `~/.config/opencode/`) in all egress
modes, in place of the file with the same name in that mode's home directory,
_e.g._ `opencode/opencode.json` or `claude/settings.json`. The exception is the
agent's instructions file (`claude/CLAUDE.md` or `opencode/AGENTS.md`), which is
added to its instructions instead. As the agent can't change these files,
settings changed from within the agent that are stored in them aren't saved;
edit the files instead. Changes take effect the next time the agent is started.

## Agent instructions

On each start, the sandbox generates the agent's personal instructions file
(`~/.claude/CLAUDE.md` for Claude Code, `~/.config/opencode/AGENTS.md` for
OpenCode) and mounts it read-only into the container. It combines, in order:

1. `~/.config/agent-sandbox/AGENTS.md`: instructions for all agents.
2. `~/.config/agent-sandbox/<agent>/CLAUDE.md` or `AGENTS.md`: instructions for
   that agent only.
3. [`instructions/sandbox.md`](./instructions/sandbox.md): a description of the
   sandbox, with the container's architecture filled in.
4. In the `filtered` and `closed` modes,
   [`instructions/egress-<mode>.md`](./instructions): the network restrictions;
   in the `filtered` mode, followed by the hosts on the combined allow-list.

The generated files are kept in `~/.local/state/agent-sandbox/`. They take the
place of any personal instructions file in a mode's home directory, so keep your
own instructions in `~/.config/agent-sandbox/` instead; instruction files in the
project itself are not affected.

## Agents

### Claude Code

The first time you run Claude Code in a given mode you'll have to authenticate
outside of the sandbox, but subsequent sessions will use the credentials that
have now been stored in that mode's home directory.

### OpenCode with a local model

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
`opencode.json` or `tui.json` and edit them there (see [Per-user
configuration](#per-user-configuration)).

To use the same theme in all modes, set it in a per-user `tui.json` (_e.g._
`"theme": "solarized"`); a theme chosen with `/theme` is only stored in that
mode's home directory.

### Session bell

OpenCode's built-in notifications use escape sequences that many terminals (such
as Alacritty) and Tmux don't support. The
[`session-bell`](./opencode/session-bell-default.ts) plugin rings the terminal
bell when a session completes or needs user attention. Tmux highlights the
window in its status line and passes the bell on to the terminal. A per-user
`tui.json` has to load the plugin itself with `"plugin": ["./session-bell.ts"]`.

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
