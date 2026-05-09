#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="agentic_ai"
PACKAGE_NAME="agentic-ai"
DISPLAY_NAME="Agentic AI"
VERSION="${VERSION:-}"
ITERATION="${ITERATION:-1}"
DIST_DIR="$PROJECT_ROOT/dist"
BUILD_DIR="$PROJECT_ROOT/_build/release-packages"
RELEASE_DIR="$PROJECT_ROOT/_build/prod/rel/$APP_NAME"

usage() {
    cat <<'EOF'
Usage: scripts/release.sh [linux|macos|all]

Targets:
  linux   Build .deb and .rpm packages on Linux. Requires dpkg-deb and rpmbuild.
  macos   Build .dmg package on macOS. Requires hdiutil.
  all     Build every package supported by the current host.

Environment:
  VERSION      Override package version. Defaults to mix.exs project version.
  ITERATION    Package iteration/revision. Defaults to 1.
EOF
}

require_command() {
    local command_name="$1"
    local install_hint="$2"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "error: required command not found: $command_name" >&2
        echo "hint: $install_hint" >&2
        exit 1
    fi
}

detect_version() {
    if [[ -n "$VERSION" ]]; then
        echo "$VERSION"
        return
    fi

    mix eval 'Mix.Project.get!(); IO.write(Mix.Project.config()[:version])'
}

build_release() {
    cd "$PROJECT_ROOT"
    export MIX_ENV=prod

    mix deps.get --only prod
    mix assets.deploy
    mix release --overwrite
}

prepare_linux_root() {
    local package_root="$1"

    rm -rf "$package_root"
    mkdir -p \
        "$package_root/opt/$PACKAGE_NAME" \
        "$package_root/etc/$PACKAGE_NAME" \
        "$package_root/lib/systemd/system" \
        "$package_root/var/lib/$PACKAGE_NAME/workspace"

    cp -a "$RELEASE_DIR/." "$package_root/opt/$PACKAGE_NAME/"

    cat >"$package_root/etc/$PACKAGE_NAME/$APP_NAME.env" <<EOF
DATABASE_PATH=/var/lib/$PACKAGE_NAME/$APP_NAME.db
WORKSPACE_DIR=/var/lib/$PACKAGE_NAME/workspace
PHX_HOST=localhost
PORT=4000
SECRET_KEY_BASE=replace-with-output-of-mix-phx-gen-secret
AZURE_OPENAI_ENDPOINT=
AZURE_OPENAI_API_KEY=
AZURE_OPENAI_API_VERSION=2024-10-21
FIRECRAWL_API_KEY=
CONTEXT7_API_KEY=
MCP_FILESYSTEM_ROOT=/var/lib/$PACKAGE_NAME/workspace
EOF

    cat >"$package_root/lib/systemd/system/$PACKAGE_NAME.service" <<EOF
[Unit]
Description=$DISPLAY_NAME
After=network.target

[Service]
Type=simple
EnvironmentFile=-/etc/$PACKAGE_NAME/$APP_NAME.env
WorkingDirectory=/opt/$PACKAGE_NAME
ExecStart=/opt/$PACKAGE_NAME/bin/$APP_NAME start
Restart=on-failure
RestartSec=5
StateDirectory=$PACKAGE_NAME

[Install]
WantedBy=multi-user.target
EOF
}

prepare_deb_metadata() {
    local package_root="$1"
    local version="$2"

    mkdir -p "$package_root/DEBIAN"

    cat >"$package_root/DEBIAN/control" <<EOF
Package: $PACKAGE_NAME
Version: $version-$ITERATION
Section: web
Priority: optional
Architecture: $(dpkg --print-architecture)
Maintainer: mingyuchoo
Description: $DISPLAY_NAME Phoenix release
EOF

    cat >"$package_root/DEBIAN/postinst" <<EOF
#!/usr/bin/env bash
set -e
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
fi
echo "$DISPLAY_NAME installed."
echo "Edit /etc/$PACKAGE_NAME/$APP_NAME.env, then run:"
echo "  sudo systemctl enable --now $PACKAGE_NAME"
EOF

    cat >"$package_root/DEBIAN/prerm" <<EOF
#!/usr/bin/env bash
set -e
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop $PACKAGE_NAME >/dev/null 2>&1 || true
    systemctl disable $PACKAGE_NAME >/dev/null 2>&1 || true
fi
EOF

    cat >"$package_root/DEBIAN/postrm" <<EOF
#!/usr/bin/env bash
set -e
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
fi
EOF

    chmod 0755 "$package_root/DEBIAN/postinst" "$package_root/DEBIAN/prerm" "$package_root/DEBIAN/postrm"
}

build_deb_package() {
    local version="$1"
    local package_root="$BUILD_DIR/linux/deb-root"

    require_command dpkg-deb "Install dpkg-dev or dpkg-deb with your distribution package manager."

    prepare_linux_root "$package_root"
    prepare_deb_metadata "$package_root" "$version"
    dpkg-deb --root-owner-group --build "$package_root" "$DIST_DIR/${PACKAGE_NAME}_${version}-${ITERATION}_$(dpkg --print-architecture).deb"
}

rpm_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) uname -m ;;
    esac
}

prepare_rpm_spec() {
    local spec_path="$1"
    local version="$2"
    local package_root="$3"

    cat >"$spec_path" <<EOF
Name: $PACKAGE_NAME
Version: $version
Release: $ITERATION%{?dist}
Summary: $DISPLAY_NAME Phoenix release
License: MIT
URL: https://github.com/mingyuchoo/elixir-study-series
BuildArch: $(rpm_arch)

%description
$DISPLAY_NAME Phoenix release.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a "$package_root"/. %{buildroot}/

%post
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
fi
echo "$DISPLAY_NAME installed."
echo "Edit /etc/$PACKAGE_NAME/$APP_NAME.env, then run:"
echo "  sudo systemctl enable --now $PACKAGE_NAME"

%preun
if [ "\$1" = "0" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl stop $PACKAGE_NAME >/dev/null 2>&1 || true
    systemctl disable $PACKAGE_NAME >/dev/null 2>&1 || true
fi

%postun
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload || true
fi

%files
/opt/$PACKAGE_NAME
%dir /etc/$PACKAGE_NAME
%config(noreplace) /etc/$PACKAGE_NAME/$APP_NAME.env
/lib/systemd/system/$PACKAGE_NAME.service
%dir /var/lib/$PACKAGE_NAME
%dir /var/lib/$PACKAGE_NAME/workspace
EOF
}

build_rpm_package() {
    local version="$1"
    local package_root="$BUILD_DIR/linux/rpm-root"
    local rpm_topdir="$BUILD_DIR/linux/rpmbuild"
    local spec_path="$rpm_topdir/SPECS/$PACKAGE_NAME.spec"

    require_command rpmbuild "Install rpm-build with your distribution package manager."

    prepare_linux_root "$package_root"
    rm -rf "$rpm_topdir"
    mkdir -p "$rpm_topdir/BUILD" "$rpm_topdir/BUILDROOT" "$rpm_topdir/RPMS" "$rpm_topdir/SOURCES" "$rpm_topdir/SPECS" "$rpm_topdir/SRPMS" "$rpm_topdir/rpmdb"
    prepare_rpm_spec "$spec_path" "$version" "$package_root"

    rpmbuild \
        --define "_topdir $rpm_topdir" \
        --define "_dbpath $rpm_topdir/rpmdb" \
        --target "$(rpm_arch)" \
        -bb "$spec_path"

    find "$rpm_topdir/RPMS" -type f -name "*.rpm" -exec cp {} "$DIST_DIR/" \;
}

build_linux_packages() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "error: linux target must be built on Linux" >&2
        exit 1
    fi

    local version="$1"
    mkdir -p "$DIST_DIR"

    build_deb_package "$version"
    build_rpm_package "$version"
}

build_macos_dmg() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "error: macos target must be built on macOS" >&2
        exit 1
    fi

    require_command hdiutil "hdiutil is included with macOS."

    local version="$1"
    local staging_dir="$BUILD_DIR/macos/$DISPLAY_NAME"
    local dmg_path="$DIST_DIR/${PACKAGE_NAME}-${version}-macos.dmg"

    rm -rf "$staging_dir"
    mkdir -p "$staging_dir/$PACKAGE_NAME" "$DIST_DIR"

    cp -a "$RELEASE_DIR/." "$staging_dir/$PACKAGE_NAME/"

    cat >"$staging_dir/start.command" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "\$(dirname "\$0")/$PACKAGE_NAME"
exec ./bin/$APP_NAME start
EOF
    chmod +x "$staging_dir/start.command"

    cat >"$staging_dir/README.txt" <<EOF
$DISPLAY_NAME

Set required environment variables before running start.command:
DATABASE_PATH, SECRET_KEY_BASE, AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY.

Example:
  export DATABASE_PATH="\$HOME/Library/Application Support/$PACKAGE_NAME/$APP_NAME.db"
  export WORKSPACE_DIR="\$HOME/Library/Application Support/$PACKAGE_NAME/workspace"
  export SECRET_KEY_BASE="<output of mix phx.gen.secret>"
  export AZURE_OPENAI_ENDPOINT="https://your-resource.openai.azure.com"
  export AZURE_OPENAI_API_KEY="your-api-key"
EOF

    rm -f "$dmg_path"
    hdiutil create \
        -volname "$DISPLAY_NAME" \
        -srcfolder "$staging_dir" \
        -ov \
        -format UDZO \
        "$dmg_path"
}

main() {
    local target="${1:-}"

    if [[ "$target" == "-h" || "$target" == "--help" ]]; then
        usage
        exit 0
    fi

    if [[ -z "$target" ]]; then
        case "$(uname -s)" in
            Linux) target="linux" ;;
            Darwin) target="macos" ;;
            *) target="all" ;;
        esac
    fi

    case "$target" in
        linux|macos|all) ;;
        *)
            usage >&2
            exit 1
            ;;
    esac

    local version
    version="$(detect_version)"

    build_release

    case "$target" in
        linux)
            build_linux_packages "$version"
            ;;
        macos)
            build_macos_dmg "$version"
            ;;
        all)
            case "$(uname -s)" in
                Linux) build_linux_packages "$version" ;;
                Darwin) build_macos_dmg "$version" ;;
                *)
                    echo "error: no release.sh package target is supported on this host" >&2
                    exit 1
                    ;;
            esac
            ;;
    esac

    echo "Release artifacts written to $DIST_DIR"
    find "$DIST_DIR" -maxdepth 1 -type f -print
}

main "$@"
