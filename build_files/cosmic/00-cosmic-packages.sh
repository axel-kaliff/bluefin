#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# COSMIC Desktop packages from Fedora repos
FEDORA_PACKAGES=(
    # Core COSMIC desktop components
    cosmic-session
    cosmic-comp
    cosmic-panel
    cosmic-applets
    cosmic-settings
    cosmic-settings-daemon
    cosmic-bg
    cosmic-osd
    cosmic-notifications
    cosmic-screenshot
    cosmic-workspaces
    cosmic-idle
    cosmic-randr
    # COSMIC applications
    cosmic-files
    cosmic-term
    cosmic-edit
    cosmic-launcher
    cosmic-app-library
    cosmic-store
    cosmic-player
    # COSMIC greeter (display manager)
    cosmic-greeter
    cosmic-initial-setup
    # Theming and configuration
    cosmic-icon-theme
    cosmic-wallpapers
    cosmic-config-fedora
    # Portal integration
    xdg-desktop-portal-cosmic
    xdg-user-dirs
    xdg-user-dirs-gtk
    # Qt integration
    cutecosmic-qt6
)

echo "Installing ${#FEDORA_PACKAGES[@]} COSMIC packages from Fedora repos..."
dnf -y install "${FEDORA_PACKAGES[@]}"

# Enable COSMIC greeter
systemctl enable cosmic-greeter.service

# Disable GDM if present (shouldn't be on base image, but just in case)
systemctl disable gdm.service || true

echo "::endgroup::"
