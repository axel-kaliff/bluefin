#!/usr/bin/bash
# COSMIC Desktop first-run setup hook

set -euo pipefail

# Create user config directory if it doesn't exist
mkdir -p "${HOME}/.config/cosmic"

# Log setup completion
echo "COSMIC desktop user setup completed"
