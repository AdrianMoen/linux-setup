#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/common.sh
. "$SCRIPT_DIR/../core/common.sh"

if ! command -v tmux >/dev/null 2>&1; then
    log_info "tmux not found, attempting installation"
    apt_install_packages tmux
else
    log_info "tmux already installed"
fi

TMUX_SOURCE="$REPO_ROOT/configs/.tmux.conf"
TMUX_TARGET="$HOME/.tmux.conf"
ensure_symlink "$TMUX_SOURCE" "$TMUX_TARGET"

add_closing_message "tmux configured. Start a session with: tmux (reload config inside tmux with: tmux source-file ~/.tmux.conf)."

log_info "tmux setup complete"
