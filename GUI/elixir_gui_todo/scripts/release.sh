#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

prepare_release() {
  export MIX_ENV=prod
  export ELIXIR_GUI_TODO_DESKTOP=true

  mix compile
  mix assets.deploy
  mix release --overwrite

  local resource_dir="$ROOT_DIR/src-tauri/resources/elixir_gui_todo"
  mkdir -p "$resource_dir"
  shopt -s dotglob nullglob
  for entry in "$resource_dir"/*; do
    if [[ "$(basename "$entry")" != ".gitkeep" ]]; then
      rm -rf "$entry"
    fi
  done
  shopt -u dotglob nullglob
  cp -R "$ROOT_DIR/_build/prod/rel/elixir_gui_todo/." "$resource_dir/"
}

build_installers() {
  case "$(uname -s)" in
    Linux)
      npm exec -- tauri build --bundles deb,rpm
      ;;
    Darwin)
      npm exec -- tauri build --bundles dmg
      ;;
    *)
      printf 'Unsupported release platform: %s\n' "$(uname -s)" >&2
      printf 'Use scripts/release.ps1 on Windows.\n' >&2
      exit 64
      ;;
  esac
}

case "${1:-build}" in
  build)
    build_installers
    ;;
  prepare)
    prepare_release
    ;;
  -h|--help|help)
    printf 'Usage: %s [build|prepare]\n' "$0"
    ;;
  *)
    printf 'Usage: %s [build|prepare]\n' "$0" >&2
    exit 64
    ;;
esac
