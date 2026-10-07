#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  printf 'Usage: %s [all|build|test|run]\n' "$0"
}

ensure_mix() {
  if command -v mix >/dev/null 2>&1; then
    return
  fi

  local elixir_version erlang_version elixir_bin erlang_bin
  elixir_version="$(awk '$1 == "elixir" {print $2; exit}' "$ROOT_DIR/.tool-versions")"
  erlang_version="$(awk '$1 == "erlang" {print $2; exit}' "$ROOT_DIR/.tool-versions")"
  elixir_bin="$HOME/.asdf/installs/elixir/$elixir_version/bin"
  erlang_bin="$HOME/.asdf/installs/erlang/$erlang_version/bin"

  if [[ -x "$elixir_bin/mix" && -x "$erlang_bin/erl" ]]; then
    export PATH="$elixir_bin:$erlang_bin:$PATH"
    return
  fi

  printf 'Elixir and Erlang are required. Install the versions in .tool-versions or add mix to PATH.\n' >&2
  return 127
}

ensure_deps() {
  ensure_mix
  mix deps.get
  mix assets.setup
}

prepare_database() {
  ensure_mix
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
  ensure_mix
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
