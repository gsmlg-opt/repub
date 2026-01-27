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
mkdir -p data/packages data/metadata data/cache

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Repub Development Environment${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Unified Dev Server:${NC}  http://localhost:4920"
echo -e "${YELLOW}  - API endpoints at /api/*${NC}"
echo -e "${YELLOW}  - Web UI (Jaspr) with hot reload${NC}"
echo -e "${YELLOW}  - Admin UI (Flutter) at /admin with hot reload${NC}"
echo ""

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Shutting down...${NC}"
    # Kill all background jobs
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Start unified dev server on 4920 first (handles API + proxies to webdev)
echo -e "${BLUE}[DEV]${NC} Starting unified dev server on port 4920..."
REPUB_STORAGE_PATH=./data/packages \
REPUB_DATABASE_URL=sqlite:./data/metadata/repub.db \
dart run packages/repub_server/bin/repub_dev_server.dart 2>&1 | sed "s/^/$(printf "${BLUE}[DEV]${NC} ")/" &
SERVER_PID=$!

# Wait for dev server to be ready
sleep 2

# Start webdev server on 4921 (for Jaspr hot reload)
# Use --hostname 0.0.0.0 to allow access from other machines on the network
echo -e "${GREEN}[WEB]${NC} Starting webdev server for Jaspr hot reload on port 4921..."
cd packages/repub_web
dart run webdev serve web:4921 --auto=refresh --hostname 0.0.0.0 2>&1 | sed "s/^/$(printf "${GREEN}[WEB]${NC} ")/" &
WEB_PID=$!
cd "$PROJECT_ROOT"

# Start Flutter admin dev server on 4922 (for Flutter hot reload)
echo -e "${GREEN}[ADMIN]${NC} Starting Flutter admin dev server on port 4922..."
cd packages/repub_admin
flutter run -d web-server --web-port 4922 --web-hostname 0.0.0.0 --web-browser-flag="--disable-web-security" 2>&1 | sed "s/^/$(printf "${GREEN}[ADMIN]${NC} ")/" &
ADMIN_PID=$!
cd "$PROJECT_ROOT"

echo ""
echo -e "${GREEN}✓ Development environment ready!${NC}"
echo -e "Open ${YELLOW}http://localhost:4920${NC} in your browser"
echo -e "  - Web UI: ${YELLOW}http://localhost:4920/${NC}"
echo -e "  - Admin UI: ${YELLOW}http://localhost:4920/admin${NC}"
echo -e "Press ${RED}Ctrl+C${NC} to stop all services"
echo ""

# Wait for processes
wait
