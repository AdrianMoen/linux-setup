#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/common.sh
. "$SCRIPT_DIR/../core/common.sh"

GITCONFIG_TARGET="$HOME/.gitconfig"
TEMPLATE_PATH="$REPO_ROOT/configs/.gitconfig.template"

if [ -f "$GITCONFIG_TARGET" ] && [ ! -L "$GITCONFIG_TARGET" ]; then
    log_warn "$GITCONFIG_TARGET already exists and is not a symlink; skipping"
    log_warn "If you want this repo to manage it, back it up and rerun."
    exit 0
fi

ensure_symlink "$TEMPLATE_PATH" "$GITCONFIG_TARGET"

if git config --global user.name >/dev/null 2>&1 && git config --global user.email >/dev/null 2>&1; then
    log_info "Git user.name and user.email are already set"
else
    log_warn "Set your git identity if needed:"
    log_warn "  git config --global user.name \"Your Name\""
    log_warn "  git config --global user.email \"you@example.com\""
    add_closing_message "Set your git identity: git config --global user.name \"Your Name\" && git config --global user.email \"you@example.com\""
fi

log_info "git setup complete"
