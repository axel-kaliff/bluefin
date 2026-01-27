#!/usr/bin/bash

set -xeou pipefail

echo "::group:: Copy COSMIC Files"

# Copy COSMIC-specific files to image
rsync -rvK /ctx/system_files/cosmic/ /

mkdir -p /tmp/scripts/helpers
install -Dm0755 /ctx/build_files/shared/utils/ghcurl /tmp/scripts/helpers/ghcurl
export PATH="/tmp/scripts/helpers:$PATH"

echo "::endgroup::"

# Install COSMIC Desktop packages
/ctx/build_files/cosmic/00-cosmic-packages.sh

# Remove fedora-logos if pulled in as a dependency
rpm --erase --nodeps fedora-logos || true

# Validate all repos are disabled before committing
/ctx/build_files/shared/validate-repos.sh

# Clean Up
echo "::group:: Cleanup"
/ctx/build_files/shared/clean-stage.sh

echo "::endgroup::"
