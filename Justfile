# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Burble — voice-first communications platform
# https://just.systems/man/en/

set shell := ["bash", "-uc"]
set dotenv-load := true
set positional-arguments := true

project := "burble"
version := "0.1.0-alpha.1"

# ═══════════════════════════════════════════════════════════════════════════════
# DEFAULT & HELP
# ═══════════════════════════════════════════════════════════════════════════════

# Show all available recipes
default:
    @just --list --unsorted

# Show project info
info:
    @echo "Project: {{project}} {{version}}"
    @echo "Server:  Elixir/Phoenix (server/)"
    @echo "FFI:     Zig SIMD coprocessor (ffi/zig/)"
    @echo "Client:  ReScript + WebRTC (client/web/)"

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD
# ═══════════════════════════════════════════════════════════════════════════════

# Build everything (FFI + server deps)
build: build-ffi build-server

# Build Zig coprocessor NIFs
build-ffi:
    cd ffi/zig && zig build -Doptimize=ReleaseFast
    cp ffi/zig/zig-out/lib/libburble_coprocessor.so server/priv/ 2>/dev/null || true

# Build Zig coprocessor (debug mode)
build-ffi-debug:
    cd ffi/zig && zig build
    cp ffi/zig/zig-out/lib/libburble_coprocessor.so server/priv/ 2>/dev/null || true

# Fetch Elixir deps and compile server
build-server:
    cd server && mix deps.get && mix compile

# Build web client
build-client:
    cd client/web && deno task build

# ═══════════════════════════════════════════════════════════════════════════════
# RUN
# ═══════════════════════════════════════════════════════════════════════════════

# Quick start — install, start server, open browser client
start:
    ./burble-launcher.sh --start

# Install desktop + menu shortcuts
install:
    ./burble-launcher.sh --install

# Uninstall shortcuts
uninstall:
    ./burble-launcher.sh --uninstall

# Open the quick-join voice client in browser (server must be running)
join:
    xdg-open "file://{{justfile_directory()}}/client/web/quick-join.html"

# P2P voice — no server needed, just share a code
p2p:
    xdg-open "file://{{justfile_directory()}}/client/web/p2p-voice.html"

# Start the Elixir server (dev mode)
server:
    cd server && mix phx.server

# Start the web client dev server
client:
    cd client/web && deno task dev

# Start everything via containers (one command)
up:
    cd containers && podman-compose -f compose.toml up

# Stop containers
down:
    cd containers && podman-compose -f compose.toml down

# ═══════════════════════════════════════════════════════════════════════════════
# TEST
# ═══════════════════════════════════════════════════════════════════════════════

# Run all tests
test: test-server test-ffi

# Run Elixir server tests
test-server:
    cd server && mix test --no-start

# Run Zig FFI unit tests
test-ffi:
    cd ffi/zig && zig build test

# Run coprocessor benchmarks (Elixir vs Zig)
bench:
    cd server && mix bench.coprocessor

# ═══════════════════════════════════════════════════════════════════════════════
# QUALITY
# ═══════════════════════════════════════════════════════════════════════════════

# Format all code
fmt:
    cd server && mix format
    cd ffi/zig && zig fmt src/

# Run Elixir linter
lint:
    cd server && mix credo --strict

# Type-check Elixir (Dialyzer)
dialyzer:
    cd server && mix dialyzer

# Run panic-attack static analysis
scan:
    panic-attack assail .

# ═══════════════════════════════════════════════════════════════════════════════
# RELEASE
# ═══════════════════════════════════════════════════════════════════════════════

# Build a release
release: build
    cd server && MIX_ENV=prod mix release

# Build container images
container-build:
    cd containers && podman build -f Containerfile.server -t burble-server ..
    cd containers && podman build -f Containerfile.web -t burble-web ../client/web

# ═══════════════════════════════════════════════════════════════════════════════
# CLEAN
# ═══════════════════════════════════════════════════════════════════════════════

# Clean all build artifacts
clean:
    cd server && mix clean
    cd ffi/zig && rm -rf zig-out .zig-cache
    rm -f server/priv/libburble_coprocessor.so
