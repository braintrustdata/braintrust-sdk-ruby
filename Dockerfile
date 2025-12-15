# Development container for braintrust-sdk-ruby
FROM debian:trixie-slim

# Install curl, ca-certificates, and git first (needed for install-deps.sh and mise)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Ruby build dependencies using shared script
COPY scripts/install-deps.sh /tmp/install-deps.sh
RUN chmod +x /tmp/install-deps.sh && /tmp/install-deps.sh && rm /tmp/install-deps.sh

# Install mise
RUN curl https://mise.run | sh
ENV PATH="/root/.local/bin:$PATH"

# Configure git safe.directory for mounted volumes
RUN git config --global --add safe.directory /app

# Activate mise in bash
RUN echo 'eval "$(mise activate bash)"' >> ~/.bashrc

WORKDIR /app

CMD ["bash"]
