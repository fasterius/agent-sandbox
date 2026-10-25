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

# Create an unprivileged user that the agent will run under
RUN useradd -m -s /bin/bash dev

CMD ["bash"]

# Claude Code image
FROM base AS claude
RUN npm install -g @anthropic-ai/claude-code
USER dev

# OpenCode image
FROM base AS opencode
RUN npm install -g opencode-ai
USER dev
