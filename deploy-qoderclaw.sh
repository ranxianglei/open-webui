#!/bin/bash
# deploy-qoderclaw.sh
# Deploy Open WebUI with QoderClaw integration using official image
# Usage: ./deploy-qoderclaw.sh [port] [qoderclaw_host] [api_key]

set -e

PORT=${1:-3001}
QODERCLAW_HOST=${2:-"host.docker.internal:8080"}
API_KEY=${3:-"sk-qoderclaw"}
CONTAINER_NAME="open-webui"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Deploying Open WebUI with QoderClaw integration ==="
echo "  Port:            $PORT"
echo "  QoderClaw host:  $QODERCLAW_HOST"
echo "  Container name:  $CONTAINER_NAME"
echo ""

# Stop and remove existing container
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Stopping existing container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# Start official Open WebUI container
echo "Starting container..."
docker run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    -p "${PORT}:8080" \
    -e ENABLE_SIGNUP=true \
    -e DEFAULT_USER_ROLE=user \
    -e OPENAI_API_BASE_URL="http://${QODERCLAW_HOST}/v1" \
    -e OPENAI_API_KEY="$API_KEY" \
    -e DEFAULT_MODEL=default-assistant \
    -e ENABLE_OLLAMA_API=false \
    -e RAG_EMBEDDING_ENGINE=openai \
    -e RAG_OPENAI_API_BASE_URL="http://${QODERCLAW_HOST}/v1" \
    -e RAG_OPENAI_API_KEY="$API_KEY" \
    -e ENABLE_RAG_WEB_SEARCH=false \
    -v open-webui-data:/app/backend/data \
    --add-host=host.docker.internal:host-gateway \
    ghcr.io/open-webui/open-webui:main

# Wait for container to start
echo "Waiting for container to start..."
for i in $(seq 1 30); do
    if docker exec "$CONTAINER_NAME" test -f /app/backend/open_webui/main.py 2>/dev/null; then
        break
    fi
    sleep 2
done

# Inject QoderClaw custom files
echo "Injecting QoderClaw integration files..."
docker cp "${SCRIPT_DIR}/backend/open_webui/routers/qoder_sessions.py" \
    "${CONTAINER_NAME}:/app/backend/open_webui/routers/qoder_sessions.py"
docker cp "${SCRIPT_DIR}/backend/open_webui/static/qoder-sessions.html" \
    "${CONTAINER_NAME}:/app/backend/open_webui/static/qoder-sessions.html"
docker cp "${SCRIPT_DIR}/backend/open_webui/static/qoder-session.html" \
    "${CONTAINER_NAME}:/app/backend/open_webui/static/qoder-session.html"
docker cp "${SCRIPT_DIR}/backend/open_webui/main.py" \
    "${CONTAINER_NAME}:/app/backend/open_webui/main.py"
docker cp "${SCRIPT_DIR}/backend/open_webui/routers/openai.py" \
    "${CONTAINER_NAME}:/app/backend/open_webui/routers/openai.py"

# Restart to apply changes
echo "Restarting container to apply changes..."
docker restart "$CONTAINER_NAME"

# Wait for service to be ready
echo "Waiting for service to be ready..."
for i in $(seq 1 30); do
    if docker exec "$CONTAINER_NAME" python3 -c "
import urllib.request
try:
    urllib.request.urlopen('http://localhost:8080/api/health')
    exit(0)
except:
    exit(1)
" 2>/dev/null; then
        echo ""
        echo "=== Deployment complete! ==="
        echo "  Open WebUI: http://localhost:${PORT}"
        echo "  Qoder Sessions: http://localhost:${PORT}/static/qoder-sessions.html"
        exit 0
    fi
    printf "."
    sleep 3
done

echo ""
echo "Service is starting, check with: docker logs $CONTAINER_NAME"
