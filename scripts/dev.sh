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
echo -e "${YELLOW}Unified Dev Server:${NC}  http://localhost:8080"
echo -e "${YELLOW}  - API endpoints at /api/*${NC}"
echo -e "${YELLOW}  - Web UI with hot reload${NC}"
echo ""

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Shutting down...${NC}"
    # Kill all background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Start webdev server on 8081 (for hot reload) - run silently in background
echo -e "${GREEN}[WEB]${NC} Starting webdev server for hot reload on port 8081..."
cd packages/repub_web
dart run webdev serve web:8081 --auto=refresh > /dev/null 2>&1 &
WEB_PID=$!
cd "$PROJECT_ROOT"

# Wait for webdev to be ready
sleep 3

# Start unified dev server on 8080 (proxies to webdev + handles API)
echo -e "${BLUE}[DEV]${NC} Starting unified dev server on port 8080..."
REPUB_STORAGE_PATH=./data/packages \
REPUB_DATABASE_URL=sqlite:./data/metadata/repub.db \
dart run packages/repub_server/bin/repub_dev_server.dart 2>&1 | sed "s/^/$(printf "${BLUE}[DEV]${NC} ")/" &
SERVER_PID=$!

# Wait a moment for the server to start
sleep 2

echo ""
echo -e "${GREEN}✓ Development environment ready!${NC}"
echo -e "Open ${YELLOW}http://localhost:8080${NC} in your browser"
echo -e "Press ${RED}Ctrl+C${NC} to stop all services"
echo ""

# Wait for processes
wait
