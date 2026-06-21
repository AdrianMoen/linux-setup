#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=core/common.sh
. "$SCRIPT_DIR/common.sh"

log_info "Installing baseline packages via apt"
apt_install_packages curl git tmux zsh ripgrep fd-find build-essential unzip
