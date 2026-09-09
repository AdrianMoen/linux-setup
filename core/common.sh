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

# --- Platform detection ----------------------------------------------------

# WSL needs different handling from a native box for anything Windows owns
# (fonts, terminal emulators). WSL_DISTRO_NAME is set by modern WSL2;
# /proc/version is the fallback for older or unusual setups.
is_wsl() {
    if [ -n "${WSL_DISTRO_NAME:-}" ]; then
        return 0
    fi
    grep -qi microsoft /proc/version 2>/dev/null
}

# The authoritative login shell lives in /etc/passwd. $SHELL is only an
# inherited env var, so during a fresh --all run it still reads "bash" while
# the zsh module is busy chsh-ing. Never branch on $SHELL.
login_shell() {
    getent passwd "$(id -un)" 2>/dev/null | awk -F: '{print $NF}'
}

# Windows shell folders as WSL paths. cmd.exe is slow and warns when the cwd
# is a WSL path, so ask once from /mnt/c and cache the answer.
WIN_USERPROFILE=""
WIN_APPDATA=""

load_windows_paths() {
    is_wsl || return 1
    [ -z "$WIN_USERPROFILE" ] || return 0
    command -v wslpath >/dev/null 2>&1 || return 1

    local raw first second
    raw="$(cd /mnt/c 2>/dev/null && cmd.exe /c "echo %USERPROFILE%&echo %APPDATA%" 2>/dev/null | tr -d '\r')"
    [ -n "$raw" ] || return 1

    first="$(printf '%s\n' "$raw" | awk 'NR==1')"
    second="$(printf '%s\n' "$raw" | awk 'NR==2')"
    [ -n "$first" ] && [ -n "$second" ] || return 1

    WIN_USERPROFILE="$(wslpath -u "$first" 2>/dev/null)"
    WIN_APPDATA="$(wslpath -u "$second" 2>/dev/null)"

    [ -n "$WIN_USERPROFILE" ] && [ -d "$WIN_USERPROFILE" ]
}

# Render a WSL path the way Explorer shows it, for user-facing instructions.
to_windows_path() {
    wslpath -w "$1" 2>/dev/null || printf '%s' "$1"
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

    if is_dry_run; then
        if [ -f "$file" ] && grep -Fxq "$line" "$file" 2>/dev/null; then
            return 0
        fi
        printf '[DRY-RUN] append to %s: %s\n' "$file" "$line"
        return 0
    fi

    touch "$file"
    if ! grep -Fxq "$line" "$file" 2>/dev/null; then
        printf '\n%s\n' "$line" >> "$file"
    fi
}

# --- PATH management -------------------------------------------------------

# Modules that install binaries outside the system prefix all append to one
# managed file, which the rc files source with a single line. This replaces
# each module hand-rolling its own append to .zshrc/.bashrc, which previously
# produced three different idioms and two different match tests.

SETUP_CONFIG_DIR="$HOME/.config/linux-setup"
SETUP_PATH_FILE="$SETUP_CONFIG_DIR/path.sh"
SETUP_RC_SOURCE_LINE='[ -f "$HOME/.config/linux-setup/path.sh" ] && . "$HOME/.config/linux-setup/path.sh"'

ensure_setup_path_file() {
    if [ -f "$SETUP_PATH_FILE" ]; then
        return 0
    fi

    if is_dry_run; then
        printf '[DRY-RUN] create %s\n' "$SETUP_PATH_FILE"
        return 0
    fi

    mkdir -p "$SETUP_CONFIG_DIR"
    cat > "$SETUP_PATH_FILE" <<'EOF'
# Managed by linux-setup; sourced from ~/.zshrc and ~/.bashrc.
# Delete this file and rerun ./install.sh to regenerate it.
EOF
    log_info "Created $SETUP_PATH_FILE"
}

ensure_rc_sources_path_file() {
    local rc
    for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
        ensure_line_in_file "$SETUP_RC_SOURCE_LINE" "$rc"
    done
}

# Add a directory to PATH persistently, and for the rest of this run too, so a
# just-installed binary is usable by later steps without a shell restart.
ensure_path_entry() {
    local dir="$1"
    local portable="$dir"

    # Keep $HOME symbolic so the generated file stays readable across machines.
    case "$dir" in
        "$HOME"/*) portable="\$HOME/${dir#"$HOME"/}" ;;
    esac

    ensure_setup_path_file
    ensure_rc_sources_path_file
    ensure_line_in_file "export PATH=\"$portable:\$PATH\"" "$SETUP_PATH_FILE"

    case ":$PATH:" in
        *":$dir:"*) ;;
        *)
            PATH="$dir:$PATH"
            export PATH
            ;;
    esac
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
