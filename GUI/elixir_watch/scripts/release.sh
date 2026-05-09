#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_ROOT"

APP_NAME="elixir_watch"
PACKAGE_NAME="elixir-watch"
DISPLAY_NAME="Elixir Watch"
LINUX_ICON_SOURCE="$APP_ROOT/assets/icons/$PACKAGE_NAME.svg"
MIX_ENV_VALUE="${MIX_ENV:-prod}"
MIX_TARGET_VALUE="${MIX_TARGET:-host}"
DIST_DIR="${DIST_DIR:-$APP_ROOT/dist}"
BUILD_DIR="$APP_ROOT/_build/package"
COMMAND="${1:-all}"

usage() {
  cat <<'USAGE'
Usage: scripts/release.sh [deps|build|linux|macos|all|clean]

Commands:
  deps    Install Hex/Rebar and fetch production dependencies.
  build   Build the production Mix release.
  linux   Build Linux .deb and .rpm packages from the production release.
  macos   Build a macOS .dmg package from the production release.
  all     Build packages for the current host OS. Linux creates .deb and .rpm;
          macOS creates .dmg. This is the default.
  clean   Remove packaging output under dist/ and _build/package.

Environment:
  MIX_ENV             Defaults to prod.
  MIX_TARGET          Defaults to host.
  DIST_DIR            Output directory. Defaults to ./dist.
  LINUX_DEB_DEPENDS   Comma-separated fpm dependencies for .deb.
                      Defaults to libglfw3,libglew2.2.
  LINUX_RPM_DEPENDS   Comma-separated fpm dependencies for .rpm.
                      Defaults to glfw,glew.

Requirements:
  All platforms: Elixir/Mix plus Scenic native build dependencies.
  Linux: fpm, pkg-config, glfw3, glew.
  macOS: hdiutil, pkg-config, glfw, glew.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

version() {
  MIX_ENV="$MIX_ENV_VALUE" mix run --no-start -e 'IO.write(Mix.Project.config()[:version])'
}

setup_mix() {
  require_command mix
  mix local.hex --force
  mix local.rebar --force
}

check_scenic_native_deps() {
  case "$(uname -s)" in
    Linux|Darwin)
      require_command pkg-config
      if ! pkg-config --exists glfw3 glew; then
        cat >&2 <<'MESSAGE'
Missing Scenic native dependencies: glfw3 and/or glew.

Install them before building release packages.
  Debian/Ubuntu: sudo apt install build-essential pkg-config libglfw3-dev libglew-dev
  Fedora:        sudo dnf install gcc make pkgconf-pkg-config glfw-devel glew-devel
  macOS:         brew install pkg-config glfw glew
MESSAGE
        exit 1
      fi
      ;;
  esac
}

release_dir() {
  printf '%s/_build/%s/rel/%s' "$APP_ROOT" "$MIX_ENV_VALUE" "$APP_NAME"
}

fetch_deps() {
  setup_mix
  MIX_ENV="$MIX_ENV_VALUE" MIX_TARGET="$MIX_TARGET_VALUE" mix deps.get --only "$MIX_ENV_VALUE"
}

build_release() {
  check_scenic_native_deps
  fetch_deps
  MIX_ENV="$MIX_ENV_VALUE" MIX_TARGET="$MIX_TARGET_VALUE" mix compile
  MIX_ENV="$MIX_ENV_VALUE" MIX_TARGET="$MIX_TARGET_VALUE" mix release --overwrite
}

prepare_dirs() {
  mkdir -p "$DIST_DIR" "$BUILD_DIR"
}

copy_release() {
  local target="$1"
  rm -rf "$target"
  mkdir -p "$(dirname "$target")"
  cp -a "$(release_dir)" "$target"
}

install_linux_desktop_integration() {
  local stage="$1"

  if [[ ! -f "$LINUX_ICON_SOURCE" ]]; then
    echo "Missing Linux desktop icon: $LINUX_ICON_SOURCE" >&2
    exit 1
  fi

  install -d \
    "$stage/usr/bin" \
    "$stage/usr/share/applications" \
    "$stage/usr/share/icons/hicolor/scalable/apps"

  cat > "$stage/usr/bin/$APP_NAME" <<EOF
#!/usr/bin/env bash
export SCENIC_WINDOW_TITLE="\${SCENIC_WINDOW_TITLE:-$DISPLAY_NAME}"
exec /opt/$APP_NAME/bin/$APP_NAME start "\$@"
EOF
  chmod 755 "$stage/usr/bin/$APP_NAME"

  install -m 644 "$LINUX_ICON_SOURCE" "$stage/usr/share/icons/hicolor/scalable/apps/$PACKAGE_NAME.svg"

  cat > "$stage/usr/share/applications/$PACKAGE_NAME.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$DISPLAY_NAME
Comment=Scenic desktop clock
Exec=$APP_NAME
Icon=$PACKAGE_NAME
Terminal=false
Categories=Utility;Clock;
StartupNotify=true
StartupWMClass=scenic_driver_local
EOF
}

fpm_dep_args() {
  local csv="$1"
  local dep
  local args=()

  IFS=',' read -ra deps <<< "$csv"
  for dep in "${deps[@]}"; do
    dep="${dep#"${dep%%[![:space:]]*}"}"
    dep="${dep%"${dep##*[![:space:]]}"}"
    if [[ -n "$dep" ]]; then
      args+=(--depends "$dep")
    fi
  done

  printf '%s\n' "${args[@]}"
}

build_linux_package() {
  local type="$1"
  local app_version="$2"
  local stage="$BUILD_DIR/linux-$type"
  local release_target="$stage/opt/$APP_NAME"
  local dep_env
  local dep_args=()
  local package_path="$DIST_DIR/${PACKAGE_NAME}_${app_version}_$(uname -m).$type"

  [[ "$(uname -s)" == "Linux" ]] || {
    echo "Linux packages must be built on Linux." >&2
    exit 1
  }

  require_command fpm
  prepare_dirs
  copy_release "$release_target"

  install_linux_desktop_integration "$stage"

  if [[ "$type" == "deb" ]]; then
    dep_env="${LINUX_DEB_DEPENDS:-libglfw3,libglew2.2}"
  else
    dep_env="${LINUX_RPM_DEPENDS:-glfw,glew}"
  fi

  mapfile -t dep_args < <(fpm_dep_args "$dep_env")
  rm -f "$package_path"

  fpm \
    -s dir \
    -t "$type" \
    -C "$stage" \
    -n "$PACKAGE_NAME" \
    -v "$app_version" \
    --description "Scenic desktop clock application" \
    --maintainer "${USER:-elixir-watch}" \
    --license "MIT" \
    "${dep_args[@]}" \
    -p "$package_path" \
    .
}

build_linux() {
  local app_version
  build_release
  app_version="$(version)"
  build_linux_package deb "$app_version"
  build_linux_package rpm "$app_version"
}

build_macos() {
  local app_version
  local app_dir
  local dmg_root
  local release_target

  [[ "$(uname -s)" == "Darwin" ]] || {
    echo "macOS packages must be built on macOS." >&2
    exit 1
  }

  require_command hdiutil
  build_release
  app_version="$(version)"
  prepare_dirs

  dmg_root="$BUILD_DIR/macos-dmg"
  app_dir="$dmg_root/$DISPLAY_NAME.app"
  release_target="$app_dir/Contents/Resources/$APP_NAME"
  rm -rf "$dmg_root"
  mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
  copy_release "$release_target"

  cat > "$app_dir/Contents/MacOS/$APP_NAME" <<EOF
#!/usr/bin/env bash
APP_DIR="\$(cd "\$(dirname "\$0")/.." && pwd)"
exec "\$APP_DIR/Resources/$APP_NAME/bin/$APP_NAME" start "\$@"
EOF
  chmod 755 "$app_dir/Contents/MacOS/$APP_NAME"

  cat > "$app_dir/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.mingyuchoo.$APP_NAME</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$app_version</string>
  <key>CFBundleVersion</key>
  <string>$app_version</string>
</dict>
</plist>
EOF

  hdiutil create \
    -volname "$DISPLAY_NAME" \
    -srcfolder "$dmg_root" \
    -ov \
    -format UDZO \
    "$DIST_DIR/${PACKAGE_NAME}_${app_version}_macos.dmg"
}

clean() {
  rm -rf "$DIST_DIR" "$BUILD_DIR"
}

case "$COMMAND" in
  deps)
    fetch_deps
    ;;
  build)
    build_release
    ;;
  linux)
    build_linux
    ;;
  macos)
    build_macos
    ;;
  all)
    case "$(uname -s)" in
      Linux)
        build_linux
        ;;
      Darwin)
        build_macos
        ;;
      *)
        echo "Unsupported host OS for release.sh: $(uname -s)" >&2
        exit 1
        ;;
    esac
    ;;
  clean)
    clean
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
