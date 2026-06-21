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

ZSH_PATH="$(command -v zsh 2>/dev/null)"

if [ -z "$ZSH_PATH" ]; then
    log_error "zsh is not available on PATH; cannot configure default shell."
    add_closing_message "zsh could not be installed/located; default shell was not changed."
    exit 0
fi

# chsh only persists if the target shell is registered in /etc/shells.
# A missing entry is the usual reason a 'chsh' change silently reverts to bash
# on the next login.
ensure_zsh_in_etc_shells() {
    if grep -Fxq "$ZSH_PATH" /etc/shells 2>/dev/null; then
        return 0
    fi

    log_info "Registering $ZSH_PATH in /etc/shells"
    if is_dry_run; then
        printf '[DRY-RUN] echo %s | sudo tee -a /etc/shells\n' "$ZSH_PATH"
        return 0
    fi

    if printf '%s\n' "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null; then
        log_info "Added $ZSH_PATH to /etc/shells"
    else
        log_warn "Could not write to /etc/shells; chsh may not persist."
    fi
}

# Authoritative login shell comes from /etc/passwd, not $SHELL (which is just
# an inherited env var from the current session).
current_login_shell() {
    getent passwd "$(id -un)" 2>/dev/null | awk -F: '{print $NF}'
}

ensure_zsh_in_etc_shells

LOGIN_SHELL="$(current_login_shell)"

if [ "$LOGIN_SHELL" = "$ZSH_PATH" ]; then
    log_info "Default login shell already set to zsh ($ZSH_PATH)"
elif command -v chsh >/dev/null 2>&1; then
    log_info "Setting default login shell to zsh via chsh"
    if is_dry_run; then
        printf '[DRY-RUN] chsh -s %s\n' "$ZSH_PATH"
    elif chsh -s "$ZSH_PATH"; then
        if [ "$(current_login_shell)" = "$ZSH_PATH" ]; then
            log_info "Default login shell changed to zsh; log out and back in to use it."
            add_closing_message "zsh is now your default login shell. Log out and back in (new SSH session) to start using it."
        else
            log_warn "chsh ran but login shell did not change. Try: sudo chsh -s $ZSH_PATH $(id -un)"
            add_closing_message "zsh installed but the login shell did not change. Run: sudo chsh -s $ZSH_PATH $(id -un), then verify with: getent passwd $(id -un)"
        fi
    else
        log_warn "chsh failed. Set it manually: chsh -s $ZSH_PATH (ensure $ZSH_PATH is in /etc/shells)"
        add_closing_message "Could not change login shell automatically. Run: chsh -s $ZSH_PATH (verify with: getent passwd $(id -un))"
    fi
else
    log_warn "chsh is unavailable; set zsh as default shell manually."
    add_closing_message "zsh installed, but chsh is unavailable; set zsh as your default shell manually (e.g. via usermod -s $ZSH_PATH $(id -un))."
fi
