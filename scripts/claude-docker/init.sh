#!/bin/bash
set -euo pipefail

echo "Initializing environment..."

# Step 1: Install Claude settings for plan mode
mkdir -p ~/.claude
cat > ~/.claude/settings.json << 'EOF'
{
  "allowUnsandboxedCommands": true,
  "defaultMode": "plan"
}
EOF

# Clear any existing Claude auth to avoid conflicts with ANTHROPIC_API_KEY
claude /logout > /dev/null 2>&1 || true

# Update Claude to latest version
echo "Updating Claude..."
sudo npm install -g @anthropic-ai/claude-code@latest

# Add Braintrust MCP server
echo "Adding Braintrust MCP server..."
claude mcp add --transport http braintrust https://api.braintrust.dev/mcp

echo "Claude settings installed (plan mode enabled with Braintrust MCP)"

# Step 2: Clone repo and create feature branch
if [ -n "${REPO_URL:-}" ]; then
    # Configure git to use GITHUB_TOKEN for HTTPS authentication
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        git config --global credential.helper store
        echo "https://oauth2:${GITHUB_TOKEN}@github.com" > ~/.git-credentials
    fi

    echo "Cloning repository: $REPO_URL"
    git clone "$REPO_URL" /workspace/repo

    cd /workspace/repo

    # Check if base branch exists
    if ! git rev-parse --verify "origin/$BASE_BRANCH" >/dev/null 2>&1; then
        echo "Error: Base branch 'origin/$BASE_BRANCH' does not exist"
        echo "Available branches:"
        git branch -r | head -10
        exit 1
    fi

    echo "Creating feature branch: $FEATURE_BRANCH from $BASE_BRANCH"
    git checkout -b "$FEATURE_BRANCH" "origin/$BASE_BRANCH"

    echo "Repository ready at /workspace/repo"
fi

# Step 3: Install mise and Ruby
if [ -d "/workspace/repo" ]; then
    cd /workspace/repo

    if [ -f "mise.toml" ]; then
        echo "Installing system dependencies..."
        if command -v sudo &> /dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq \
                build-essential \
                curl \
                libssl-dev \
                libreadline-dev \
                zlib1g-dev \
                libyaml-dev \
                libgmp-dev
        fi

        echo "Installing mise..."
        curl https://mise.run | sh
        export PATH="$HOME/.local/bin:$PATH"

        echo "Installing Ruby via mise..."
        mise trust
        mise install

        # Activate mise for this shell
        eval "$(mise activate bash)"

        # Create activation script for interactive shells (.bashrc)
        cat >> ~/.bashrc << 'EOFBASH'
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"
EOFBASH

        # Also add to .profile for login shells
        cat >> ~/.profile << 'EOFPROFILE'
export PATH="$HOME/.local/bin:$PATH"
eval "$(mise activate bash)"
EOFPROFILE

        echo "Ruby environment ready"
        ruby --version
        bundle --version
    fi
fi

echo "Initialization complete"
