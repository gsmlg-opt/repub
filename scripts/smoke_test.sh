#!/bin/bash
#
# Smoke test for repub package registry.
# This script tests the full publish and install flow.
#
# Usage:
#   ./scripts/smoke_test.sh
#
# Prerequisites:
#   - docker compose up -d (or services running)
#   - dart SDK installed
#

set -e

REPUB_URL="${REPUB_URL:-http://localhost:4920}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR=$(mktemp -d)
TOKEN=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    log_info "Cleaning up..."
    rm -rf "$TEST_DIR"

    # Remove the token from dart pub
    if [ -n "$TOKEN" ]; then
        dart pub token remove "$REPUB_URL" 2>/dev/null || true
    fi
}

trap cleanup EXIT

wait_for_service() {
    local url="$1"
    local max_attempts=30
    local attempt=1

    log_info "Waiting for service at $url..."

    while [ $attempt -le $max_attempts ]; do
        if curl -s "$url/health" > /dev/null 2>&1; then
            log_info "Service is ready"
            return 0
        fi
        echo -n "."
        sleep 1
        attempt=$((attempt + 1))
    done

    echo ""
    log_error "Service did not become ready after $max_attempts seconds"
    return 1
}

create_token() {
    log_info "Creating auth token..."

    # Use docker compose to run token create command via repub_cli
    TOKEN=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T repub /app/bin/repub_cli token create smoke-test publish:all 2>&1 | grep "^Created token:" | cut -d: -f2 | tr -d ' ')

    if [ -z "$TOKEN" ]; then
        # Try running locally with melos if docker doesn't work
        cd "$PROJECT_DIR"
        if command -v melos &> /dev/null; then
            TOKEN=$(dart run -C packages/repub_cli repub_cli token create smoke-test publish:all 2>&1 | grep "^Created token:" | cut -d: -f2 | tr -d ' ')
        fi
    fi

    if [ -z "$TOKEN" ]; then
        log_error "Failed to create token"
        exit 1
    fi

    log_info "Token created successfully"
}

add_token_to_dart() {
    log_info "Adding token to dart pub..."

    # Remove existing token if any
    dart pub token remove "$REPUB_URL" 2>/dev/null || true

    # Add the new token
    echo "$TOKEN" | dart pub token add "$REPUB_URL"

    log_info "Token added to dart pub"
}

create_test_package() {
    log_info "Creating test package..."

    local pkg_dir="$TEST_DIR/smoke_test_pkg"
    mkdir -p "$pkg_dir/lib"

    # Create pubspec.yaml
    cat > "$pkg_dir/pubspec.yaml" << EOF
name: smoke_test_pkg
version: 1.0.0
description: A test package for smoke testing repub
environment:
  sdk: ^3.0.0
publish_to: $REPUB_URL
EOF

    # Create a simple library file
    cat > "$pkg_dir/lib/smoke_test_pkg.dart" << 'EOF'
/// A simple test library.
library smoke_test_pkg;

/// Returns a greeting message.
String greet(String name) => 'Hello, $name!';
EOF

    # Create CHANGELOG
    cat > "$pkg_dir/CHANGELOG.md" << 'EOF'
# Changelog

## 1.0.0

- Initial release
EOF

    # Create LICENSE
    cat > "$pkg_dir/LICENSE" << 'EOF'
MIT License

Copyright (c) 2024

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction.
EOF

    log_info "Test package created at $pkg_dir"
    echo "$pkg_dir"
}

publish_package() {
    local pkg_dir="$1"

    log_info "Publishing test package..."

    cd "$pkg_dir"

    # Run dart pub publish with force flag
    dart pub publish --force 2>&1

    log_info "Package published successfully"
}

verify_package_exists() {
    log_info "Verifying package exists in registry..."

    local response
    response=$(curl -s "$REPUB_URL/api/packages/smoke_test_pkg")

    if echo "$response" | grep -q '"name":"smoke_test_pkg"'; then
        log_info "Package found in registry"
    else
        log_error "Package not found in registry"
        log_error "Response: $response"
        exit 1
    fi

    if echo "$response" | grep -q '"version":"1.0.0"'; then
        log_info "Version 1.0.0 found"
    else
        log_error "Version 1.0.0 not found"
        exit 1
    fi
}

create_consumer_app() {
    log_info "Creating consumer app..."

    local app_dir="$TEST_DIR/consumer_app"
    mkdir -p "$app_dir/bin"

    # Create pubspec.yaml
    cat > "$app_dir/pubspec.yaml" << EOF
name: consumer_app
version: 1.0.0
description: A test app that consumes smoke_test_pkg
environment:
  sdk: ^3.0.0
dependencies:
  smoke_test_pkg:
    hosted:
      url: $REPUB_URL
    version: ^1.0.0
EOF

    # Create main.dart
    cat > "$app_dir/bin/consumer_app.dart" << 'EOF'
import 'package:smoke_test_pkg/smoke_test_pkg.dart';

void main() {
  print(greet('World'));
}
EOF

    log_info "Consumer app created at $app_dir"
    echo "$app_dir"
}

install_package() {
    local app_dir="$1"

    log_info "Installing package in consumer app..."

    cd "$app_dir"

    # Run dart pub get
    dart pub get 2>&1

    log_info "Package installed successfully"
}

run_consumer_app() {
    local app_dir="$1"

    log_info "Running consumer app..."

    cd "$app_dir"

    local output
    output=$(dart run bin/consumer_app.dart 2>&1)

    if echo "$output" | grep -q "Hello, World!"; then
        log_info "Consumer app ran successfully: $output"
    else
        log_error "Consumer app output unexpected: $output"
        exit 1
    fi
}

main() {
    log_info "Starting smoke test for repub at $REPUB_URL"
    log_info "Test directory: $TEST_DIR"

    # Wait for service
    wait_for_service "$REPUB_URL"

    # Create and configure token
    create_token
    add_token_to_dart

    # Create and publish test package
    local pkg_dir
    pkg_dir=$(create_test_package)
    publish_package "$pkg_dir"

    # Verify package in registry
    verify_package_exists

    # Create consumer app and install package
    local app_dir
    app_dir=$(create_consumer_app)
    install_package "$app_dir"

    # Run the consumer app
    run_consumer_app "$app_dir"

    log_info ""
    log_info "========================================="
    log_info "  SMOKE TEST PASSED!"
    log_info "========================================="
    log_info ""
}

main "$@"
