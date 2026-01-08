#!/usr/bin/env bash
#
# manage-containerd-sysext.sh
#
# Description:
#   This script downloads static containerd binaries, constructs a valid
#   systemd-sysext directory structure, packages it into a SquashFS image,
#   and installs it to /var/lib/extensions.
#
# Dependencies:
#   curl, tar, mksquashfs (squashfs-tools), systemd-sysext
#
# Usage:
#   sudo ./manage-containerd-sysext.sh {install|remove|status}

set -euo pipefail

# --- Configuration ---
# We pin a stable version to ensure predictability.
# Users can override this by exporting the variable before running.
CONTAINERD_VERSION="${CONTAINERD_VERSION:-1.7.13}"
RUNC_VERSION="${RUNC_VERSION:-1.1.12}"
CNI_VERSION="${CNI_VERSION:-1.4.0}"

# Paths
SYSEXT_NAME="containerd"
EXTENSIONS_DIR="/var/lib/extensions"
TEMP_BUILD_DIR="/tmp/containerd-sysext-build"
ARCH=$(uname -m)

# --- Architecture Detection ---
case "${ARCH}" in
    x86_64)
        GO_ARCH="amd64"
        ;;
    aarch64)
        GO_ARCH="arm64"
        ;;
    *)
        echo "Error: Unsupported architecture: ${ARCH}"
        exit 1
        ;;
esac

# --- URLs ---
CONTAINERD_URL="https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${GO_ARCH}.tar.gz"
# Note: Bluefin usually has crun/runc, but containerd expects 'runc'. 
# We fetch runc to be self-contained within the extension.
RUNC_URL="https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${GO_ARCH}"

# --- Functions ---

function check_deps() {
    local deps=("curl" "tar" "mksquashfs" "systemd-sysext")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Error: Required dependency '$dep' not found."
            echo "Please ensure squashfs-tools is installed in the base image."
            exit 1
        fi
    done
}

function install_sysext() {
    echo ">>> Starting Containerd Sysext Installation..."
    check_deps

    # 1. Prepare Build Directory
    echo ">>> Preparing build directory at ${TEMP_BUILD_DIR}..."
    rm -rf "${TEMP_BUILD_DIR}"
    mkdir -p "${TEMP_BUILD_DIR}/usr/bin"
    mkdir -p "${TEMP_BUILD_DIR}/usr/lib/systemd/system"
    mkdir -p "${TEMP_BUILD_DIR}/usr/lib/extension-release.d"

    # 2. Download and Extract Containerd
    echo ">>> Downloading containerd v${CONTAINERD_VERSION}..."
    curl -L --fail --retry 3 "${CONTAINERD_URL}" | tar -xz -C "${TEMP_BUILD_DIR}/usr/bin" --strip-components=1 bin/containerd bin/ctr bin/containerd-shim-runc-v2

    # 3. Download Runc (Static)
    echo ">>> Downloading runc v${RUNC_VERSION}..."
    curl -L --fail --retry 3 "${RUNC_URL}" -o "${TEMP_BUILD_DIR}/usr/bin/runc"
    chmod +x "${TEMP_BUILD_DIR}/usr/bin/runc"

    # 4. Create Systemd Service Unit
    # We embed the unit file directly to avoid external dependencies.
    # Config points to /etc/containerd/config.toml (mutable path).
    echo ">>> Creating systemd unit..."
    cat <<EOF > "${TEMP_BUILD_DIR}/usr/lib/systemd/system/containerd.service"
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
# ExecStartPre loads the overlay module if not present
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
# Unlimited resources for container runtime
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

    # 5. Create Extension Metadata
    # ID=_any allows the extension to load on any OS version (Fedora/CentOS/etc)
    # This is critical for rolling release stability.
    echo ">>> Creating extension metadata..."
    echo 'ID=_any' > "${TEMP_BUILD_DIR}/usr/lib/extension-release.d/extension-release.${SYSEXT_NAME}"
    # Optional: Add version metadata
    echo "SYSEXT_LEVEL=1.0" >> "${TEMP_BUILD_DIR}/usr/lib/extension-release.d/extension-release.${SYSEXT_NAME}"

    # 6. Build SquashFS Image
    echo ">>> Packaging extension into SquashFS..."
    mkdir -p "${EXTENSIONS_DIR}"
    # Remove existing image if present
    rm -f "${EXTENSIONS_DIR}/${SYSEXT_NAME}.raw"
    
    # mksquashfs flags:
    # -all-root: ensure all files are owned by root:root inside the image
    # -noappend: overwrite destination
    # -comp zstd: use Zstandard compression (fast and efficient)
    mksquashfs "${TEMP_BUILD_DIR}" "${EXTENSIONS_DIR}/${SYSEXT_NAME}.raw" -all-root -noappend -comp zstd -quiet

    # 7. Activate Extension
    echo ">>> Activating extension..."
    systemd-sysext refresh
    
    # 8. Reload Systemd and Enable Service
    echo ">>> reloading systemd..."
    systemctl daemon-reload
    echo ">>> Enabling and starting containerd..."
    systemctl enable --now containerd

    # Cleanup
    rm -rf "${TEMP_BUILD_DIR}"
    
    echo ">>> Success! Containerd is now active."
    echo "    Verify with: systemctl status containerd"
    echo "    CLI tool:    ctr version"
}

function remove_sysext() {
    echo ">>> Removing Containerd Sysext..."
    
    # 1. Stop and Disable Service
    if systemctl is-active --quiet containerd; then
        echo ">>> Stopping containerd service..."
        systemctl disable --now containerd
    fi

    # 2. Remove Extension Image
    if [[ -f "${EXTENSIONS_DIR}/${SYSEXT_NAME}.raw" ]]; then
        echo ">>> Deleting extension image..."
        rm -f "${EXTENSIONS_DIR}/${SYSEXT_NAME}.raw"
    else
        echo ">>> Extension image not found."
    fi

    # 3. Refresh Systemd-Sysext
    echo ">>> Refreshing system extensions..."
    systemd-sysext refresh
    systemctl daemon-reload

    echo ">>> Containerd has been removed."
}

function status_sysext() {
    if [[ -f "${EXTENSIONS_DIR}/${SYSEXT_NAME}.raw" ]]; then
        echo "Status: Installed"
        systemctl status containerd --no-pager
    else
        echo "Status: Not Installed"
    fi
}

# --- CLI Entrypoint ---
case "${1:-}" in
    install)
        install_sysext
        ;;
    remove)
        remove_sysext
        ;;
    status)
        status_sysext
        ;;
    *)
        echo "Usage: $0 {install|remove|status}"
        exit 1
        ;;
esac
