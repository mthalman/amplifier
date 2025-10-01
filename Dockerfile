FROM ubuntu:22.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update \
    && apt-get install -y \
    curl \
    git \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (required for Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Install Python 3.11
RUN apt-get update && \
    apt-get install -y \
    python3.11 \
    python3.11-venv \
    python3.11-dev && \
    rm -rf /var/lib/apt/lists/*

# Install uv (Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:/root/.cargo/bin:$PATH"
ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Install Claude Code, pyright, and pnpm
ENV SHELL=/bin/bash
RUN npm install -g @anthropic-ai/claude-code pyright pnpm && \
    SHELL=/bin/bash pnpm setup && \
    echo 'export PNPM_HOME="/root/.local/share/pnpm"' >> ~/.bashrc && \
    echo 'export PATH="$PNPM_HOME:$PATH"' >> ~/.bashrc

# Pre-configure Claude Code to use environment variables
RUN mkdir -p /root/.config/claude-code

ENV AMPLIFIER_DIR=/app/amplifier \
    AMPLIFIER_DATA_DIR=/app/amplifier-data

# Set working directory to amplifier
WORKDIR ${AMPLIFIER_DIR}

COPY pyproject.toml .

# Initialize Python environment with uv and install dependencies
RUN uv venv --python python3.11 .venv && \
    uv sync --group dev

COPY . .

# Create data directory for Amplifier and required subdirectories
RUN mkdir -p ${AMPLIFIER_DATA_DIR}

# Set environment variables
ENV TARGET_DIR=/workspace \
    PATH="${AMPLIFIER_DIR}:$PATH"

# Create volumes for mounting
VOLUME ["/workspace", "${AMPLIFIER_DATA_DIR}"]

# Set the working directory to Amplifier before entrypoint
WORKDIR ${AMPLIFIER_DIR}

# Set entrypoint
ENTRYPOINT ["/app/amplifier/entrypoint.sh"]
