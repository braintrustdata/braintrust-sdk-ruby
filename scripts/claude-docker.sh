#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Docker container label
export DOCKER_LABEL="braintrust-ruby-sdk"

COMMAND="${1:-}"

usage() {
    cat << EOF
Usage: $0 <command> [options]

Commands:
    create      Create a new container for a branch
    connect     Connect to an existing container
    list        List all containers
    delete      Delete a container
    delete-all  Delete all containers

Examples:
    $0 create matt/ruby-llm
    $0 list
    $0 connect <container-name>
    $0 delete <container-name>
    $0 delete-all
EOF
    exit 0
}

if [ -z "$COMMAND" ]; then
    usage
fi

shift  # Remove command from args

case $COMMAND in
    create)
        source "$SCRIPT_DIR/claude-docker/commands/create.sh"
        ;;
    connect)
        source "$SCRIPT_DIR/claude-docker/commands/connect.sh"
        ;;
    list)
        source "$SCRIPT_DIR/claude-docker/commands/list.sh"
        ;;
    delete)
        source "$SCRIPT_DIR/claude-docker/commands/delete.sh"
        ;;
    delete-all)
        source "$SCRIPT_DIR/claude-docker/commands/delete-all.sh"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo "Unknown command: $COMMAND"
        usage
        ;;
esac
