# List all sdk-ruby containers

echo "SDK Ruby containers:"
echo ""

docker ps -a --filter "label=${DOCKER_LABEL}=true" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}" | head -20

if [ $(docker ps -a --filter "label=${DOCKER_LABEL}=true" -q | wc -l) -eq 0 ]; then
    echo "No containers found"
fi
