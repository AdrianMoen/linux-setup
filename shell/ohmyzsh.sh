#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/common.sh
. "$SCRIPT_DIR/../core/common.sh"

OHMYZSH_DIR="$HOME/.oh-my-zsh"

if [ -d "$OHMYZSH_DIR" ]; then
    log_info "oh-my-zsh already installed at $OHMYZSH_DIR"
    exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
    log_info "curl not found, attempting installation"
    apt_install_packages curl
fi

INSTALL_CMD="RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""

if is_dry_run; then
    printf '[DRY-RUN] %s\n' "$INSTALL_CMD"
    exit 0
fi

RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
log_info "oh-my-zsh installation complete"
add_closing_message "oh-my-zsh installed. Customize themes/plugins in ~/.zshrc, then restart your shell."
