#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

REPO_URL="https://github.com/Adaptix-Framework/AdaptixC2.git"
INSTALL_DIR="${INSTALL_DIR:-/opt/AdaptixC2}"
GO_VERSION="1.25.4"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
GO_WIN7_REPO="https://github.com/Adaptix-Framework/go-win7"
GO_WIN7_DIR="/usr/lib/go-win7"

log()  { printf '\n[+] %s\n' "$*"; }
warn() { printf '\n[!] %s\n' "$*" >&2; }
die()  { printf '\n[-] %s\n' "$*" >&2; exit 1; }

trap 'code=$?; [ "$code" -ne 0 ] && warn "Installation failed."; exit "$code"' EXIT

require_root() {
    [ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash $0"
}

check_os() {
    [ -r /etc/os-release ] || die "/etc/os-release not found."
    . /etc/os-release
    log "Detected OS: ${PRETTY_NAME:-unknown}"
}

apt_install_prereqs() {
    log "Updating APT metadata"
    apt-get update -y

    log "Installing build dependencies"
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        curl \
        git \
        make \
        gcc \
        g++ \
        build-essential \
        mingw-w64 \
        g++-mingw-w64 \
        pkg-config \
        file \
        unzip \
        xz-utils

    update-ca-certificates || true
}

install_go() {
    log "Installing Go ${GO_VERSION}"
    wget -q --show-progress "${GO_URL}" -O "/tmp/${GO_TARBALL}"

    rm -rf /usr/local/go
    tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
    ln -sf /usr/local/go/bin/go /usr/local/bin/go

    export GOROOT=/usr/local/go
    export PATH="/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

    go version | grep -q "go${GO_VERSION}" || die "Go version mismatch: $(go version)"
    [ "$(go env GOROOT)" = "/usr/local/go" ] || die "GOROOT mismatch: $(go env GOROOT)"

    log "Go installed: $(go version)"
}

install_go_win7_patch() {
    log "Installing patched Go tree for optional Windows 7 gopher-agent support"
    rm -rf "${GO_WIN7_DIR}" /tmp/go-win7
    git clone --depth 1 "${GO_WIN7_REPO}" /tmp/go-win7
    mv /tmp/go-win7 "${GO_WIN7_DIR}"
    log "Patched Go tree placed at ${GO_WIN7_DIR}"
}

clone_or_update_repo() {
    local clone_tmp=""

    if [ -d "${INSTALL_DIR}/.git" ]; then
        log "Updating existing repo at ${INSTALL_DIR}"
        git -C "${INSTALL_DIR}" fetch --all --tags
        git -C "${INSTALL_DIR}" checkout main
        git -C "${INSTALL_DIR}" pull --ff-only
    elif [ -e "${INSTALL_DIR}" ] && [ -n "$(find "${INSTALL_DIR}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
        log "Installing AdaptixC2 repo into existing ${INSTALL_DIR}"
        clone_tmp="$(mktemp -d /tmp/adaptixc2.XXXXXX)"
        git clone "${REPO_URL}" "${clone_tmp}"
        git -C "${clone_tmp}" checkout main
        cp -R "${clone_tmp}/." "${INSTALL_DIR}/"
        rm -rf "${clone_tmp}"
    else
        log "Cloning AdaptixC2 into ${INSTALL_DIR}"
        mkdir -p "$(dirname "${INSTALL_DIR}")"
        git clone "${REPO_URL}" "${INSTALL_DIR}"
        git -C "${INSTALL_DIR}" checkout main
    fi
}

build_server_and_extenders() {
    log "Building Adaptix server and extenders with pinned Go toolchain"
    cd "${INSTALL_DIR}"

    export GOROOT=/usr/local/go
    export PATH="/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    unset GOPATH GOBIN GOENV GOTOOLDIR ASDF_DIR ASDF_DATA_DIR

    hash -r

    command -v go >/dev/null 2>&1 || die "go not found"
    command -v make >/dev/null 2>&1 || die "make not found"

    [ "$(go env GOROOT)" = "/usr/local/go" ] || die "Wrong GOROOT: $(go env GOROOT)"
    go version | grep -q "go1.25.4" || die "Wrong Go version: $(go version)"

    make clean || true

    env \
      GOROOT="/usr/local/go" \
      PATH="/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
      make server-ext
}

post_build_checks() {
    log "Running post-build checks"
    cd "${INSTALL_DIR}"

    [ -d "dist" ] || warn "dist directory not found"

    find dist -maxdepth 2 -type f 2>/dev/null | sort || true

    log "Go version: $(go version)"
    log "GOROOT: $(go env GOROOT)"
    log "Build completed"
}

main() {
    require_root
    check_os
    apt_install_prereqs
    install_go
    install_go_win7_patch
    clone_or_update_repo
    build_server_and_extenders
    post_build_checks

    cat <<'EOF'

[+] Done.

Useful checks:
  cd /opt/AdaptixC2
  ls -lah dist
  go env GOROOT
EOF
}

main "$@"
