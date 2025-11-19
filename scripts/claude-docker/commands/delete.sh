# Delete a claude-docker container

CONTAINER_NAME="${1:-}"

if [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: $0 delete <container-name>"
    echo ""
    echo "Available containers:"
    docker ps -a --filter "label=claude-docker=true" --format "  {{.Names}}"
    exit 1
fi

echo "Deleting container: $CONTAINER_NAME"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker rm -f "$CONTAINER_NAME"
    echo "Deleted container: $CONTAINER_NAME"
else
    echo "Container not found: $CONTAINER_NAME"
    exit 1
fi
