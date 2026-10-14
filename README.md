# Claude Code sandbox

A Docker Compose setup for running [Claude Code](https://github.com/anthropics/claude-code)
against an arbitrary local project directory, with outbound network access
locked down to only the endpoints at Anthropic.

- The `claude` container has **no direct route to the internet**: the only thing
  it can reach at all is the `proxy` container.
- The `proxy` (tinyproxy) container is the sole egress path, and only forwards
  HTTPS `CONNECT` requests to hosts matching the allow-list in
  [`filter`](./filter)
- Both containers run with all Linux capabilities dropped (`cap_drop: ALL`),
  `no-new-privileges`, and the `claude` container has memory/CPU/PID limits.

## Requirements

- Docker and Docker Compose

## Usage

First build the images using `Docker compose` (the environment variables are not
used during build but are required, so initialise them to the current directory):

```bash
PROJECT_DIR=. CLAUDE_HOME=. docker compose build
```

You can then run Claude Code with egress filtering like so:

```bash
cd /path/to/your/project
/path/to/this/repo/run-claude-egress-filtered.sh [optional args]
```

The `run-claude-egress-filtered.sh` script can be run from any directory: it
uses `$PWD` as the project to mount. Any extra arguments are forwarded to the
`claude` CLI, _e.g._:

```bash
run-claude-egress-filtered.sh -p "summarise this repository"
```

The first time you run it, Docker will build the `claude` image from the
included [`Dockerfile`](./Dockerfile)). You'll also have to authenticate outside
of the sandbox, but subsequent sessions will use the credentials that have now
been stored in the `~/.claude-sandbox-home-egress-filtered` directory.

## What gets mounted

- Your project directory (`$PWD` when you invoke the script) is mounted at
  `/home/dev/workspace` inside the container — this is what Claude Code can
  read and edit.
- `CLAUDE_HOME` (on the host, outside this repository) is mounted as the
  container's `$HOME` (`/home/dev`). This is where Claude Code persists its
  config, credentials, and session history _between runs of the sandbox_. It
  contains real secrets (`.credentials.json`, `.claude.json`) once you've
  logged in — treat it like any other credentials directory.
  `run-claude-egress-filtered.sh` sets this to
  `~/.claude-sandbox-home-egress-filtered`; `run-claude-egress-open.sh` uses a
  separate `~/.claude-sandbox-home-egress-open` (see
  [Unrestricted egress](#unrestricted-egress)), so the two modes can have
  their own `CLAUDE.md` and credentials.

## Extending the allow-list

Add an anchored regular expression line to `filter` (e.g. `^some\.host\.com$`)
and restart using the `restart-proxy.sh` script.

## Blocked directories

The wrapper scripts refuse to run in any directory listed in
[`blocked-dirs`](./blocked-dirs), such as your home directory, credential
directories like `~/.ssh` and system directories; add and remove entries as you
see fit. A plain entry blocks only that exact directory, while an entry ending
in `/**` also blocks everything below it. Symlinks are resolved before matching
and matching is case-insensitive.

## Unrestricted egress

It is also possible to run this setup with no egress limits, just execute
`run-claude-egress-open.sh` instead of `run-claude-egress-filtered.sh`:

```bash
cd /path/to/your/project
/path/to/this/repo/run-claude-egress-open.sh [optional args]
```

The other hardening (dropped capabilities, `no-new-privileges`, memory/CPU/PID
limits) still applies; only the network restriction is lifted.

This mode also uses its own `~/.claude-sandbox-home-egress-open` directory
rather than the one `run-claude-egress-filtered.sh` uses, so it can have
separate `CLAUDE.md` instructions, config and credentials from the
egress-filtered sandbox.
