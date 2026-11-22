FROM ghcr.io/prefix-dev/pixi:latest AS pixi-src

# Shared base for all agent images
FROM node:22-bookworm-slim AS base

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        fd-find \
        git \
        ripgrep \
        wget \
    && rm -rf /var/lib/apt/lists/* \
    # Symlink `fdfind` (default on Debian) into `fd`
    && ln -s /usr/bin/fdfind /usr/local/bin/fd

# Copy Pixi binary from official image
COPY --from=pixi-src /usr/local/bin/pixi /usr/local/bin/pixi

# Create an unprivileged user that the agent will run under, with the user and
# group IDs of the user on the host, so that it can write to the directories
# mounted from there on Linux; the base image's own user is removed, as it would
# otherwise have the usual first user ID, 1000
ARG UID=1000
ARG GID=1000
RUN userdel -r node \
    && groupadd -o -g "$GID" dev \
    && useradd -m -o -u "$UID" -g "$GID" -s /bin/bash dev

CMD ["bash"]

# Claude Code image
FROM base AS claude
RUN npm install -g @anthropic-ai/claude-code
USER dev

# OpenCode image
FROM base AS opencode
RUN npm install -g opencode-ai
USER dev
