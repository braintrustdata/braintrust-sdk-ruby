#!/bin/bash
# Install Ruby build dependencies
# Run this BEFORE running `mise install`

set -e

if [ "$(uname)" = "Darwin" ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing Ruby build dependencies via Homebrew..."
    brew install openssl@3 readline libyaml gmp
    echo "✓ Dependencies installed successfully"
    echo ""
    echo "Next steps:"
    echo "  1. Run: mise install"
    echo "  2. Run: bundle install"
  else
    echo "Error: Homebrew not found. Please install Homebrew first:"
    echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
  fi
elif [ -f /etc/debian_version ]; then
  echo "Installing Ruby build dependencies for Debian/Ubuntu..."
  sudo apt-get update
  sudo apt-get install -y \
    build-essential \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libyaml-dev \
    libgmp-dev
  echo "✓ Dependencies installed successfully"
  echo ""
  echo "Next steps:"
  echo "  1. Run: mise install"
  echo "  2. Run: bundle install"
elif [ -f /etc/redhat-release ]; then
  echo "Installing Ruby build dependencies for Fedora/CentOS/RHEL..."
  sudo dnf install -y \
    gcc \
    make \
    openssl-devel \
    readline-devel \
    zlib-devel \
    libyaml-devel \
    gmp-devel
  echo "✓ Dependencies installed successfully"
  echo ""
  echo "Next steps:"
  echo "  1. Run: mise install"
  echo "  2. Run: bundle install"
else
  echo "Unsupported OS. Please install build dependencies manually."
  echo "See CONTRIBUTING.md for instructions."
  exit 1
fi
