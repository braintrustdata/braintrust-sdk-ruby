# Development container for braintrust-sdk-ruby
FROM debian:trixie-slim

# Set UTF-8 locale
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install curl, ca-certificates, and git first (needed for install-deps.sh and mise)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    openssh-client \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install Ruby build dependencies using shared script
COPY scripts/install-deps.sh /tmp/install-deps.sh
RUN chmod +x /tmp/install-deps.sh && /tmp/install-deps.sh && rm /tmp/install-deps.sh

# Create non-root user with configurable UID/GID
ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID dev && useradd -m -u $UID -g $GID dev

# Create directories for mise and bundle cache
RUN mkdir -p /home/dev/.local/share/mise /home/dev/.local/bin /usr/local/bundle \
    && chown -R dev:dev /home/dev /usr/local/bundle

# Switch to non-root user
USER dev
ENV HOME=/home/dev
ENV PATH="/home/dev/.local/bin:$PATH"

# Install mise as the dev user
RUN curl https://mise.run | sh

# Configure git safe.directory for mounted volumes
RUN git config --global --add safe.directory /app

# Activate mise in bash
RUN echo 'eval "$(mise activate bash)"' >> ~/.bashrc

WORKDIR /app

CMD ["bash"]
