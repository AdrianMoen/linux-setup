#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/common.sh
. "$SCRIPT_DIR/../core/common.sh"

if ! command -v zsh >/dev/null 2>&1; then
    log_info "zsh not found, attempting installation"
    apt_install_packages zsh
else
    log_info "zsh already installed"
fi

if [ "${SHELL:-}" != "$(command -v zsh 2>/dev/null)" ]; then
    if command -v chsh >/dev/null 2>&1; then
        log_warn "Default shell is not zsh. Run: chsh -s $(command -v zsh)"
        add_closing_message "zsh installed. Set it as your default shell: chsh -s $(command -v zsh)"
    else
        log_warn "chsh is unavailable; set zsh as default shell manually."
        add_closing_message "zsh installed, but chsh is unavailable; set zsh as your default shell manually."
    fi
else
    log_info "Default shell already set to zsh"
fi
