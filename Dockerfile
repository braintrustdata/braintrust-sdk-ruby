# Development container for braintrust-sdk-ruby
FROM debian:trixie-slim

# Install minimal dependencies for mise and Ruby compilation
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    git \
    build-essential \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

# Install mise
RUN curl https://mise.run | sh
ENV PATH="/root/.local/bin:$PATH"

# Configure git safe.directory for mounted volumes
RUN git config --global --add safe.directory /app

# Activate mise in bash
RUN echo 'eval "$(mise activate bash)"' >> ~/.bashrc

WORKDIR /app

CMD ["bash"]
