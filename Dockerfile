# Build stage
FROM dart:stable AS build

WORKDIR /app

# Install melos globally
RUN dart pub global activate melos

# Copy workspace configuration first (melos config is in pubspec.yaml in melos 7.x)
COPY pubspec.yaml ./

# Copy all package pubspec files for dependency resolution
COPY packages/repub_model/pubspec.yaml packages/repub_model/
COPY packages/repub_auth/pubspec.yaml packages/repub_auth/
COPY packages/repub_storage/pubspec.yaml packages/repub_storage/
COPY packages/repub_migrate/pubspec.yaml packages/repub_migrate/
COPY packages/repub_server/pubspec.yaml packages/repub_server/
COPY packages/repub_cli/pubspec.yaml packages/repub_cli/

# Bootstrap melos workspace
RUN dart pub global run melos bootstrap

# Copy all source code
COPY packages/ packages/

# Create output directory and compile executables
RUN mkdir -p bin

# Compile repub_server to native executable
RUN dart compile exe packages/repub_server/bin/repub_server.dart -o bin/repub_server

# Compile repub_cli to native executable
RUN dart compile exe packages/repub_cli/bin/repub_cli.dart -o bin/repub_cli

# Runtime stage
FROM debian:bookworm-slim

# Install CA certificates for HTTPS
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the compiled binaries
COPY --from=build /app/bin/repub_server /app/bin/repub_server
COPY --from=build /app/bin/repub_cli /app/bin/repub_cli

# Create non-root user
RUN useradd -r -s /bin/false repub
USER repub

EXPOSE 8080

# Default to running the server
ENTRYPOINT ["/app/bin/repub_server"]
