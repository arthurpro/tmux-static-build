# Static tmux builder using Docker on Ubuntu 22.04
#
# Usage:
#   just build-all                 # Build for both amd64 and arm64 into ./dist
#   just build amd64               # Build for a single arch into ./dist
#   just build arm64               # Build for a single arch into ./dist
#   just setup-binfmt              # (Optional) Enable cross-arch emulation on the host
#   just clean                     # Remove ./dist
#
# Notes:
# - Artifacts are copied from container /tmp/tmux-static/bin/*.gz to host ./dist/
# - Compression via UPX can be enabled with: just build-all USE_UPX=1
#   or per-arch: just build amd64 USE_UPX=1
#
# Requirements:
# - Docker installed and running
# - For cross-arch on a single-arch host, run `just setup-binfmt` once.

IMAGE := "ubuntu:22.04"
WORKSPACE := "."
DIST := "./dist"
DOCKER := "docker"

# Set to "1" to compress binaries with UPX inside the build script
# e.g. `just build-all USE_UPX=1`
USE_UPX := "0"

# Default target
default: build-all

# Build for both amd64 and arm64
build-all:
	@just build amd64
	@just build arm64
	@echo "All builds completed. Artifacts in: {{DIST}}"
	@ls -la {{DIST}} || true

# Build for a specific architecture: amd64 or arm64
build arch:
    #!/bin/zsh
    set -euo pipefail
    mkdir -p {{DIST}}
    if [ "{{arch}}" != "amd64" ] && [ "{{arch}}" != "arm64" ]; then
        echo "Invalid arch '{{arch}}'. Use 'amd64' or 'arm64'."
        exit 1
    fi
    echo "Building tmux statically in Docker (arch={{arch}}, image={{IMAGE}})"
    {{DOCKER}} run --rm --platform=linux/{{arch}} \
    -e DEBIAN_FRONTEND=noninteractive \
    -e USE_UPX="{{USE_UPX}}" \
    -e LOCAL_UID="$(id -u)" \
    -e LOCAL_GID="$(id -g)" \
    -v "{{WORKSPACE}}:/workspace" \
    -w /workspace \
    {{IMAGE}} \
    bash -lc 'set -euo pipefail; \
        echo "Installing build dependencies..."; \
        apt-get update; \
        apt-get install -y --no-install-recommends \
        build-essential bison wget ca-certificates xz-utils tar gzip pkg-config binutils; \
        rm -rf /var/lib/apt/lists/*; \
        echo "Running build script..."; \
        /bin/sh build-static-tmux.sh -d; \
        echo "Copying artifacts to mounted workspace..."; \
        mkdir -p /workspace/dist; \
        cp -v /tmp/tmux-static/bin/tmux.*.gz /workspace/dist/; \
        # Best-effort to match host file ownership for artifacts \
        if [ -n "$${LOCAL_UID:-}" ] && [ -n "$${LOCAL_GID:-}" ]; then \
        chown -R "$${LOCAL_UID}":"$${LOCAL_GID}" /workspace/dist || true; \
        fi';
    echo "Done: artifacts for {{arch}} in {{DIST}}"
    ls -la {{DIST}} || true

# Enable cross-arch emulation (QEMU binfmt) to run non-native images
setup-binfmt:
	@echo "Setting up binfmt for cross-arch emulation (requires privileges)..."
	@{{DOCKER}} run --privileged --rm tonistiigi/binfmt --install all
	@echo "binfmt set. You can now run cross-arch containers with --platform."

# Remove dist directory
clean:
	@rm -rf {{DIST}}
	@echo "Cleaned {{DIST}}"
