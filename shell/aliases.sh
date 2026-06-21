#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/common.sh
. "$SCRIPT_DIR/../core/common.sh"

ALIASES_SOURCE="$REPO_ROOT/configs/.aliases"
ALIASES_TARGET="$HOME/.aliases"

ensure_symlink "$ALIASES_SOURCE" "$ALIASES_TARGET"

ensure_line_in_file "[ -f ~/.aliases ] && source ~/.aliases" "$HOME/.zshrc"
ensure_line_in_file "[ -f ~/.aliases ] && source ~/.aliases" "$HOME/.bashrc"

add_closing_message "Aliases linked to ~/.aliases. Restart your shell or run: source ~/.aliases"

log_info "Alias setup complete"
