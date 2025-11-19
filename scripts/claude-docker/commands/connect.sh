# Connect to an existing claude-docker container

CONTAINER_NAME="${1:-}"

if [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: $0 connect <container-name>"
    echo ""
    echo "Available containers:"
    docker ps -a --filter "label=${DOCKER_LABEL}=true" --format "  {{.Names}}"
    exit 1
fi

echo "Connecting to container: $CONTAINER_NAME"

if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container not found: $CONTAINER_NAME"
    echo "Use '$0 list' to see available containers"
    exit 1
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Starting stopped container..."
    docker start "$CONTAINER_NAME"
fi

# Execute bash in the container, starting in the repo directory
echo "Connecting to container..."
echo ""
echo "To update Claude:"
echo "  claude /update"
echo ""
echo "To run Claude in unsafe mode:"
echo "  claude --dangerously-skip-permissions"
echo ""
docker exec -it -w /workspace/repo "$CONTAINER_NAME" bash
