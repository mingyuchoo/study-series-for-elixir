#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_ROOT"

MIX_ENV_VALUE="${MIX_ENV:-dev}"
MIX_TARGET_VALUE="${MIX_TARGET:-host}"
SCENIC_WINDOW_TITLE_VALUE="${SCENIC_WINDOW_TITLE:-elixir_watch}"
COMMAND="${1:-all}"
KIOSK_APP_PID=""

usage() {
  cat <<'USAGE'
Usage: scripts/run.sh [deps|build|test|run|all]

Commands:
  deps   Install Hex/Rebar if needed and fetch dependencies.
  build  Compile the Scenic desktop application.
  test   Run the test suite.
  run    Start the Scenic desktop application.
  all    Run deps, build, test, then run. This is the default.

Environment:
  MIX_ENV  Mix environment to use. Defaults to dev.
  MIX_TARGET  Scenic local target to build. Defaults to host.
  SCENIC_DEBUG  Set to 1 to enable Scenic local driver debug logging.
  SCENIC_KIOSK  Set to 1 on Linux to request fullscreen kiosk mode.
  SCENIC_VIEWPORT_SIZE  Viewport size as WIDTHxHEIGHT. Kiosk mode auto-detects it.
  SCENIC_WINDOW_TITLE  Window title used for WM fullscreen matching. Defaults to elixir_watch.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

setup_mix() {
  require_command mix
  mix local.hex --force
  mix local.rebar --force
}

check_scenic_native_deps() {
  case "$(uname -s)" in
    Linux)
      require_command pkg-config
      if ! pkg-config --exists glfw3 glew; then
        cat >&2 <<'MESSAGE'
Missing Scenic native dependencies: glfw3 and/or glew.

Install them before building or running the desktop app.
  Debian/Ubuntu: sudo apt install build-essential pkg-config libglfw3-dev libglew-dev
  Fedora:        sudo dnf install gcc make pkgconf-pkg-config glfw-devel glew-devel
  Arch:          sudo pacman -S base-devel pkgconf glfw-x11 glew
MESSAGE
        exit 1
      fi
      ;;
    Darwin)
      require_command pkg-config
      if ! pkg-config --exists glfw3 glew; then
        cat >&2 <<'MESSAGE'
Missing Scenic native dependencies: glfw3 and/or glew.

Install them before building or running the desktop app.
  macOS/Homebrew: brew install pkg-config glfw glew
MESSAGE
        exit 1
      fi
      ;;
  esac
}

check_graphical_session() {
  case "$(uname -s)" in
    Linux)
      if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        cat >&2 <<'MESSAGE'
No graphical session detected.

Scenic.Driver.Local uses GLFW for the host desktop target and needs DISPLAY or
WAYLAND_DISPLAY to open a window. Run this from a desktop session, or use Xvfb
for headless CI.
MESSAGE
        exit 1
      fi
      ;;
  esac
}

detect_display_size() {
  if [[ -n "${SCENIC_VIEWPORT_SIZE:-}" ]]; then
    printf '%s' "$SCENIC_VIEWPORT_SIZE"
    return
  fi

  if command -v xrandr >/dev/null 2>&1; then
    local size
    size="$(xrandr 2>/dev/null | awk '/\*/ {print $1; exit}')"

    if [[ "$size" =~ ^[0-9]+x[0-9]+$ ]]; then
      printf '%s' "$size"
      return
    fi
  fi

  printf '480x480'
}

apply_linux_kiosk_fullscreen() {
  if [[ "${SCENIC_KIOSK:-0}" != "1" || "$(uname -s)" != "Linux" ]]; then
    return
  fi

  if [[ -z "${DISPLAY:-}" ]]; then
    echo "SCENIC_KIOSK=1 is active, but DISPLAY is not set; skipping WM fullscreen request." >&2
    return
  fi

  if ! command -v wmctrl >/dev/null 2>&1; then
    echo "SCENIC_KIOSK=1 is active. Install wmctrl to remove the Linux window-manager title bar automatically." >&2
    return
  fi

  for _attempt in $(seq 1 40); do
    if wmctrl -r "$SCENIC_WINDOW_TITLE_VALUE" -b add,fullscreen 2>/dev/null; then
      wmctrl -r "$SCENIC_WINDOW_TITLE_VALUE" -b add,above 2>/dev/null || true
      return
    fi

    sleep 0.1
  done

  echo "Unable to find Scenic window titled '$SCENIC_WINDOW_TITLE_VALUE' for fullscreen request." >&2
}

cleanup_kiosk_app() {
  if [[ -n "${KIOSK_APP_PID:-}" ]]; then
    kill "$KIOSK_APP_PID" 2>/dev/null || true
    wait "$KIOSK_APP_PID" 2>/dev/null || true
  fi
}

scenic_driver_binary() {
  local env_name="$1"
  printf '%s/_build/%s/lib/scenic_driver_local/priv/scenic_driver_local' "$APP_ROOT" "$env_name"
}

ensure_scenic_driver_compiled() {
  local env_name="$1"
  local driver_bin
  driver_bin="$(scenic_driver_binary "$env_name")"

  if [[ ! -x "$driver_bin" ]]; then
    echo "Scenic local driver executable is missing; rebuilding scenic_driver_local for MIX_ENV=$env_name." >&2
    MIX_ENV="$env_name" MIX_TARGET="$MIX_TARGET_VALUE" mix deps.compile scenic_driver_local --force
  fi
}

fetch_deps() {
  setup_mix
  MIX_ENV="$MIX_ENV_VALUE" MIX_TARGET="$MIX_TARGET_VALUE" mix deps.get
}

build_app() {
  check_scenic_native_deps
  ensure_scenic_driver_compiled "$MIX_ENV_VALUE"
  MIX_ENV="$MIX_ENV_VALUE" MIX_TARGET="$MIX_TARGET_VALUE" mix compile
}

test_app() {
  check_scenic_native_deps
  ensure_scenic_driver_compiled test
  MIX_ENV=test MIX_TARGET="$MIX_TARGET_VALUE" mix test --no-start
}

run_app() {
  check_graphical_session

  if [[ "${SCENIC_KIOSK:-0}" == "1" && "$(uname -s)" == "Linux" ]]; then
    export SCENIC_VIEWPORT_SIZE
    SCENIC_VIEWPORT_SIZE="$(detect_display_size)"
    echo "Starting kiosk mode with SCENIC_VIEWPORT_SIZE=$SCENIC_VIEWPORT_SIZE." >&2

    MIX_ENV="$MIX_ENV_VALUE" MIX_TARGET="$MIX_TARGET_VALUE" SCENIC_WINDOW_TITLE="$SCENIC_WINDOW_TITLE_VALUE" mix run --no-halt &
    KIOSK_APP_PID=$!

    trap cleanup_kiosk_app INT TERM EXIT
    apply_linux_kiosk_fullscreen
    wait "$KIOSK_APP_PID"
    local status=$?
    KIOSK_APP_PID=""
    trap - INT TERM EXIT
    return "$status"
  fi

  MIX_ENV="$MIX_ENV_VALUE" MIX_TARGET="$MIX_TARGET_VALUE" SCENIC_WINDOW_TITLE="$SCENIC_WINDOW_TITLE_VALUE" mix run --no-halt
}

case "$COMMAND" in
  deps)
    fetch_deps
    ;;
  build)
    fetch_deps
    build_app
    ;;
  test)
    fetch_deps
    test_app
    ;;
  run)
    fetch_deps
    build_app
    run_app
    ;;
  all)
    fetch_deps
    build_app
    test_app
    run_app
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    usage >&2
    exit 1
    ;;
esac
