# Sandbox environment

You are running inside a Docker container (the agent sandbox), as the
unprivileged user `dev`. If something fails due to the sandbox's restrictions,
**say so clearly** rather than retrying or exploring workarounds that would also
fail.

- The starting working directory is the project, mounted from the host at the
  same path as there; changes here persist on the host.
- `/home/dev` is your home directory, persistent between sessions.
- Anything else in the file system is lost when the container exits.
- There is no `sudo`, so system packages can't be installed; install software
  into the project or home directory instead, _e.g._ with Pixi.
- Available tools include git, ripgrep (`rg`), fd, curl, wget, Pixi and build
  tools (`gcc`, `make`).
- Pushing with git isn't possible, as there are no credentials for remotes.
- The project's `.git/config` and hooks directory are read-only, so commands
  that change the repository's settings (_e.g._ `git config`, `git remote add`
  or setting an upstream branch) fail; staging, committing, branching and
  merging work. Don't work around this; ask the user to make the change instead.
- The container runs as `@ARCH@`, so Conda packages follow the `@PLATFORM@`
  platform; the sandbox can also be started as `@OTHER_ARCH@`.
