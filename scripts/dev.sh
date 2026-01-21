#!/bin/bash
# Development script - runs API server and web UI with hot reload

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Create data directories if they don't exist
mkdir -p data/packages data/metadata

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Repub Development Environment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}API Server:${NC}  http://localhost:8080"
echo -e "${YELLOW}Web UI:${NC}      http://localhost:8081"
echo ""

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Shutting down...${NC}"
    # Kill all background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Start API server in background
echo -e "${BLUE}[API]${NC} Starting server..."
REPUB_STORAGE_PATH=./data/packages \
REPUB_DATABASE_URL=sqlite:./data/metadata/repub.db \
dart run packages/repub_server/bin/repub_server.dart 2>&1 | sed "s/^/$(printf "${BLUE}[API]${NC} ")/" &
SERVER_PID=$!

# Wait for server to be ready
sleep 3

# Start web dev server using webdev
echo -e "${GREEN}[WEB]${NC} Starting dev server with hot reload..."
cd packages/repub_web
dart run webdev serve web:8081 --auto=refresh 2>&1 | sed "s/^/$(printf "${GREEN}[WEB]${NC} ")/" &
WEB_PID=$!

echo ""
echo -e "${GREEN}Development environment ready!${NC}"
echo -e "Open ${YELLOW}http://localhost:8081${NC} in your browser"
echo -e "Press ${RED}Ctrl+C${NC} to stop all services"
echo ""

# Wait for processes
wait
