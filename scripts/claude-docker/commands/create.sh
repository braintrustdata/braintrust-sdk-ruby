# Create a new claude-docker container

BASE_BRANCH="main"
BRANCH_NAME=""

# Parse create arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --base-branch)
            BASE_BRANCH="$2"
            shift 2
            ;;
        *)
            BRANCH_NAME="$1"
            shift
            ;;
    esac
done

if [ -z "$BRANCH_NAME" ]; then
    echo "Usage: $0 create [--base-branch BRANCH] <branch-name>"
    exit 1
fi

# Get repo URL
REPO_URL=$(cd "$REPO_ROOT" && git remote get-url origin)
HTTPS_REPO_URL=$(echo "$REPO_URL" | sed 's|git@github.com:|https://github.com/|')

FEATURE_BRANCH="$BRANCH_NAME"

# Sanitize branch name for container name
CONTAINER_NAME="sdk-ruby-$(echo "$FEATURE_BRANCH" | sed 's|/|-|g')"

echo "Creating container: $CONTAINER_NAME"
echo "Repo: $HTTPS_REPO_URL"
echo "Base branch: $BASE_BRANCH"
echo "Feature branch: $FEATURE_BRANCH"
echo ""

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container already exists: $CONTAINER_NAME"
    echo "Use '$0 connect $FEATURE_BRANCH' to reconnect"
    echo "Or '$0 delete $FEATURE_BRANCH' to remove it first"
    exit 1
fi

# Load ALL keys from .env file if it exists
ENV_ARGS=()
ENV_FILE="$REPO_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
    echo "Loading environment from .env file..."

    while IFS='=' read -r key value; do
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key ]] && continue

        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")

        if [ -n "$value" ]; then
            ENV_ARGS+=("-e" "$key=$value")
            echo "  $key"
        fi
    done < "$ENV_FILE"
    echo ""
fi

# Set git config if not in env
if [ -z "${GIT_AUTHOR_NAME:-}" ]; then
    GIT_AUTHOR_NAME=$(git config user.name || echo "Claude")
    ENV_ARGS+=("-e" "GIT_AUTHOR_NAME=$GIT_AUTHOR_NAME")
fi

if [ -z "${GIT_AUTHOR_EMAIL:-}" ]; then
    GIT_AUTHOR_EMAIL=$(git config user.email || echo "claude@anthropic.com")
    ENV_ARGS+=("-e" "GIT_AUTHOR_EMAIL=$GIT_AUTHOR_EMAIL")
fi

echo "Running Docker container..."
echo ""

# Create temp workspace for init script
TEMP_WORKSPACE=$(mktemp -d)
cp "$SCRIPT_DIR/claude-docker/init.sh" "$TEMP_WORKSPACE/init.sh"
chmod +x "$TEMP_WORKSPACE/init.sh"

# Run docker container in background (no --rm so it persists)
echo "Initializing container in background..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --label "${DOCKER_LABEL}=true" \
    --label "branch=$FEATURE_BRANCH" \
    -v "$TEMP_WORKSPACE:/workspace" \
    "${ENV_ARGS[@]}" \
    -e "REPO_URL=$HTTPS_REPO_URL" \
    -e "BASE_BRANCH=$BASE_BRANCH" \
    -e "FEATURE_BRANCH=$FEATURE_BRANCH" \
    -w /workspace \
    docker/sandbox-templates:claude-code \
    tail -f /dev/null

# Wait for container to be running
sleep 2

# Run init script
echo "Running initialization..."
docker exec "$CONTAINER_NAME" bash /workspace/init.sh

# Show instructions
echo ""
echo "Container created: $CONTAINER_NAME"
echo ""
echo "Connect with:"
echo "  $0 connect $CONTAINER_NAME"
echo ""

EXIT_CODE=0
exit $EXIT_CODE
