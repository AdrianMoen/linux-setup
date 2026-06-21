#!/usr/bin/env bash

set -u

if [ -n "${LINUX_SETUP_COMMON_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
LINUX_SETUP_COMMON_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log_info() {
    printf '[INFO] %s\n' "$1"
}

log_warn() {
    printf '[WARN] %s\n' "$1"
}

log_error() {
    printf '[ERROR] %s\n' "$1" >&2
}

is_dry_run() {
    [ "${LINUX_SETUP_DRY_RUN:-0}" = "1" ]
}

run_cmd() {
    if is_dry_run; then
        printf '[DRY-RUN] %s\n' "$*"
        return 0
    fi
    "$@"
}

# Queue a message to be printed at the very end of the install run.
# install.sh points LINUX_SETUP_CLOSING_FILE at a shared file and prints it
# after all modules finish, so each module can add context-specific guidance
# (e.g. "run chsh to set zsh as default") depending on what it actually did.
add_closing_message() {
    local msg="$1"
    local file="${LINUX_SETUP_CLOSING_FILE:-}"

    if [ -z "$file" ]; then
        # No collector configured (module run directly); surface it inline.
        printf '[NEXT STEP] %s\n' "$msg"
        return 0
    fi

    printf '%s\n' "$msg" >> "$file"
}

apt_available() {
    command -v apt-get >/dev/null 2>&1
}

apt_install_packages() {
    if ! apt_available; then
        log_warn "apt-get not available on this system. Skipping package install."
        return 0
    fi

    if is_dry_run; then
        printf '[DRY-RUN] sudo apt-get update\n'
        printf '[DRY-RUN] sudo apt-get install -y %s\n' "$*"
        return 0
    fi

    sudo apt-get update
    sudo apt-get install -y "$@"
}

ensure_line_in_file() {
    local line="$1"
    local file="$2"

    touch "$file"
    if ! grep -Fxq "$line" "$file" 2>/dev/null; then
        if is_dry_run; then
            printf '[DRY-RUN] append to %s: %s\n' "$file" "$line"
        else
            printf '\n%s\n' "$line" >> "$file"
        fi
    fi
}

ensure_symlink() {
    local source_path="$1"
    local target_path="$2"

    if [ ! -e "$source_path" ]; then
        log_warn "Source missing for symlink: $source_path"
        return 0
    fi

    if [ -L "$target_path" ]; then
        local current_target
        current_target="$(readlink "$target_path")"
        if [ "$current_target" = "$source_path" ]; then
            log_info "Symlink already correct: $target_path"
            return 0
        fi
    fi

    if [ -e "$target_path" ] && [ ! -L "$target_path" ]; then
        log_warn "Target exists and is not a symlink: $target_path (skipping)"
        return 0
    fi

    run_cmd ln -sfn "$source_path" "$target_path"
    log_info "Linked $target_path -> $source_path"
}
