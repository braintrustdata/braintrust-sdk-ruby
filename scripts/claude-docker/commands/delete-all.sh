# Delete all containers

CONTAINERS=$(docker ps -a --filter "label=${DOCKER_LABEL}=true" --format "{{.Names}}")

if [ -z "$CONTAINERS" ]; then
    echo "No containers found"
    exit 0
fi

echo "Found containers:"
echo "$CONTAINERS" | sed 's/^/  /'
echo ""

read -p "Delete all containers? [y/N] " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

echo "Deleting all containers..."
docker ps -a --filter "label=${DOCKER_LABEL}=true" -q | xargs -r docker rm -f

echo "All containers deleted"
