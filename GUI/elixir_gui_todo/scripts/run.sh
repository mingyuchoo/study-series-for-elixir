#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  printf 'Usage: %s [all|build|test|run]\n' "$0"
}

ensure_deps() {
  mix deps.get
  mix assets.setup
}

prepare_database() {
  mkdir -p "$ROOT_DIR/data"
  mix ecto.create --quiet
  mix ecto.migrate --quiet
}

build_app() {
  ensure_deps
  prepare_database
  mix assets.build
}

test_app() {
  mix precommit
}

run_app() {
  export ELIXIR_GUI_TODO_NO_WATCHERS=true
  exec mix phx.server
}

case "${1:-all}" in
  all)
    build_app
    test_app
    run_app
    ;;
  build)
    build_app
    ;;
  test)
    test_app
    ;;
  run)
    prepare_database
    run_app
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
