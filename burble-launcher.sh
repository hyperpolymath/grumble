#!/usr/bin/env bash
# SPDX-License-Identifier: PMPL-1.0-or-later
# Burble Launcher — first-run setup + desktop shortcut + start server + open client.
# Works on Fedora (rpm-ostree/dnf), Debian/Ubuntu, Parrot OS.

set -euo pipefail

BURBLE_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$BURBLE_DIR/server"
CLIENT_HTML="$BURBLE_DIR/client/web/quick-join.html"
BURBLE_PORT=4020
BURBLE_URL="http://localhost:$BURBLE_PORT"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/burble"
FIRST_RUN_FLAG="$CONFIG_DIR/.first-run-complete"
ICON_DIR="$BURBLE_DIR/assets/icons"
DESKTOP_FILE="burble-voice.desktop"

# Colours
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log() { echo -e "${GREEN}[Burble]${NC} $1"; }
warn() { echo -e "${YELLOW}[Burble]${NC} $1"; }
err() { echo -e "${RED}[Burble]${NC} $1" >&2; }

# ---------------------------------------------------------------------------
# Detect OS
# ---------------------------------------------------------------------------
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  else
    echo "unknown"
  fi
}

OS=$(detect_os)

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
check_deps() {
  local missing=()

  command -v elixir >/dev/null 2>&1 || missing+=("elixir")
  command -v mix >/dev/null 2>&1 || missing+=("mix")

  if [ ${#missing[@]} -gt 0 ]; then
    err "Missing dependencies: ${missing[*]}"
    log "Installing..."
    case "$OS" in
      fedora)
        # Fedora Atomic uses rpm-ostree, regular uses dnf
        if command -v rpm-ostree >/dev/null 2>&1; then
          warn "Fedora Atomic detected — using asdf for Elixir (rpm-ostree is immutable)"
          install_via_asdf
        else
          sudo dnf install -y elixir erlang
        fi
        ;;
      parrot|debian|ubuntu)
        sudo apt-get update && sudo apt-get install -y elixir erlang-dev erlang-nox
        ;;
      *)
        err "Unknown OS '$OS' — install Elixir manually: https://elixir-lang.org/install.html"
        exit 1
        ;;
    esac
  fi

  log "Elixir $(elixir --version 2>&1 | tail -1)"
}

install_via_asdf() {
  if ! command -v asdf >/dev/null 2>&1; then
    err "asdf not found — install from https://asdf-vm.com"
    exit 1
  fi
  asdf plugin add erlang 2>/dev/null || true
  asdf plugin add elixir 2>/dev/null || true
  asdf install erlang latest 2>/dev/null || true
  asdf install elixir latest 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# First-run setup
# ---------------------------------------------------------------------------
first_run() {
  if [ -f "$FIRST_RUN_FLAG" ]; then
    return 0
  fi

  log "First run detected — setting up Burble..."
  mkdir -p "$CONFIG_DIR"

  # Fetch deps if needed
  if [ ! -d "$SERVER_DIR/deps" ] || [ ! -d "$SERVER_DIR/_build" ]; then
    log "Fetching server dependencies..."
    (cd "$SERVER_DIR" && mix deps.get && mix compile)
  fi

  # Create icon directory with placeholder
  mkdir -p "$ICON_DIR"
  if [ ! -f "$ICON_DIR/burble-256.png" ]; then
    # Generate a simple SVG icon and convert if possible
    cat > "$ICON_DIR/burble.svg" << 'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
  <circle cx="128" cy="128" r="120" fill="#0d1117" stroke="#3fb950" stroke-width="8"/>
  <circle cx="128" cy="100" r="40" fill="none" stroke="#e6edf3" stroke-width="6"/>
  <path d="M88 140 C88 180 168 180 168 140" fill="none" stroke="#e6edf3" stroke-width="6"/>
  <line x1="128" y1="180" x2="128" y2="210" stroke="#e6edf3" stroke-width="6"/>
  <line x1="108" y1="210" x2="148" y2="210" stroke="#e6edf3" stroke-width="6" stroke-linecap="round"/>
</svg>
SVG
    # Try to convert to PNG if rsvg-convert or inkscape available
    if command -v rsvg-convert >/dev/null 2>&1; then
      rsvg-convert -w 256 -h 256 "$ICON_DIR/burble.svg" > "$ICON_DIR/burble-256.png"
    elif command -v inkscape >/dev/null 2>&1; then
      inkscape -w 256 -h 256 "$ICON_DIR/burble.svg" -o "$ICON_DIR/burble-256.png" 2>/dev/null
    fi
  fi

  # Offer desktop shortcut
  local response=""
  echo ""
  log "Would you like to install Burble shortcuts?"
  echo "  1) Desktop shortcut only"
  echo "  2) Application menu only"
  echo "  3) Both desktop and menu"
  echo "  4) Skip"
  read -rp "  Choice [3]: " response
  response="${response:-3}"

  case "$response" in
    1) install_desktop_shortcut ;;
    2) install_menu_shortcut ;;
    3) install_desktop_shortcut; install_menu_shortcut ;;
    4) log "Skipping shortcuts" ;;
  esac

  touch "$FIRST_RUN_FLAG"
  log "First-run setup complete!"
}

# ---------------------------------------------------------------------------
# Desktop shortcut
# ---------------------------------------------------------------------------
create_desktop_entry() {
  local icon_path="$ICON_DIR/burble-256.png"
  [ ! -f "$icon_path" ] && icon_path="$ICON_DIR/burble.svg"
  [ ! -f "$icon_path" ] && icon_path="call-start"  # fallback to system icon

  cat << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Burble Voice
GenericName=Voice Chat
Comment=Voice first. Friction last. Complexity optional.
Exec=$BURBLE_DIR/burble-launcher.sh --start
Icon=$icon_path
Terminal=false
Categories=Network;Chat;AudioVideo;
Keywords=voice;chat;voip;webrtc;
StartupNotify=true
StartupWMClass=burble
Actions=stop;status;

[Desktop Action stop]
Name=Stop Server
Exec=$BURBLE_DIR/burble-launcher.sh --stop
Icon=process-stop

[Desktop Action status]
Name=Server Status
Exec=$BURBLE_DIR/burble-launcher.sh --status
Icon=dialog-information
EOF
}

install_desktop_shortcut() {
  local dest="$HOME/Desktop/$DESKTOP_FILE"
  create_desktop_entry > "$dest"
  chmod +x "$dest"
  # Mark as trusted on GNOME/KDE
  gio set "$dest" metadata::trusted true 2>/dev/null || true
  log "Desktop shortcut installed: $dest"
}

install_menu_shortcut() {
  local dest="$HOME/.local/share/applications/$DESKTOP_FILE"
  mkdir -p "$(dirname "$dest")"
  create_desktop_entry > "$dest"
  log "Application menu entry installed: $dest"
  # Update desktop database
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Server management
# ---------------------------------------------------------------------------
is_server_running() {
  curl -s -o /dev/null -w "%{http_code}" "$BURBLE_URL/" 2>/dev/null | grep -q "200\|404\|500"
}

start_server() {
  if is_server_running; then
    log "Server already running on port $BURBLE_PORT"
    return 0
  fi

  log "Starting Burble server on port $BURBLE_PORT..."

  # Try systemd user service first
  if systemctl --user is-enabled burble.service >/dev/null 2>&1; then
    systemctl --user start burble.service
    sleep 3
  else
    # Direct start in background
    (cd "$SERVER_DIR" && MIX_ENV=dev mix phx.server &) 2>/dev/null
    sleep 4
  fi

  if is_server_running; then
    log "Server started successfully"
  else
    warn "Server may still be starting — check: curl $BURBLE_URL/api/v1/setup/check"
  fi
}

stop_server() {
  if systemctl --user is-active burble.service >/dev/null 2>&1; then
    systemctl --user stop burble.service
    log "Server stopped (systemd)"
  else
    local pids
    pids=$(lsof -ti ":$BURBLE_PORT" 2>/dev/null || true)
    if [ -n "$pids" ]; then
      echo "$pids" | xargs kill 2>/dev/null
      log "Server stopped (PID)"
    else
      warn "Server not running"
    fi
  fi
}

open_client() {
  local url="file://$CLIENT_HTML"

  if is_server_running; then
    log "Opening Burble client..."
  else
    warn "Server not running — client will connect when server starts"
  fi

  # Open in default browser
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" &
  elif command -v firefox >/dev/null 2>&1; then
    firefox "$url" &
  elif command -v chromium >/dev/null 2>&1; then
    chromium "$url" &
  else
    log "Open manually: $url"
  fi
}

show_status() {
  if is_server_running; then
    log "Server: ${GREEN}running${NC} on port $BURBLE_PORT"
    local check
    check=$(curl -s "$BURBLE_URL/api/v1/setup/check" 2>/dev/null || echo '{}')
    echo "  Setup: $check"
  else
    log "Server: ${RED}stopped${NC}"
  fi
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
case "${1:-}" in
  --start)
    check_deps
    first_run
    start_server
    open_client
    ;;
  --stop)
    stop_server
    ;;
  --status)
    show_status
    ;;
  --install)
    check_deps
    first_run
    ;;
  --uninstall)
    rm -f "$HOME/Desktop/$DESKTOP_FILE"
    rm -f "$HOME/.local/share/applications/$DESKTOP_FILE"
    rm -f "$FIRST_RUN_FLAG"
    log "Shortcuts and first-run flag removed"
    ;;
  --help|-h)
    echo "Usage: burble-launcher.sh [OPTION]"
    echo ""
    echo "Options:"
    echo "  --start      Start server and open client (default)"
    echo "  --stop       Stop the server"
    echo "  --status     Show server status"
    echo "  --install    Run first-time setup only"
    echo "  --uninstall  Remove shortcuts"
    echo "  --help       Show this help"
    ;;
  *)
    check_deps
    first_run
    start_server
    open_client
    ;;
esac
