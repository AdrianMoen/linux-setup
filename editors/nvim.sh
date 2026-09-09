#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/common.sh
. "$SCRIPT_DIR/../core/common.sh"

NVIM_TARGET_DIR="$HOME/.config/nvim"
LOCAL_NVIM_SOURCE="$REPO_ROOT/editors/nvim-config"
NVIM_CONFIG_REPO="${NVIM_CONFIG_REPO:-}"
DEFAULT_KICKSTART_REPO="git@github.com:AdrianMoen/kickstart.nvim.moen.git"
TREE_SITTER_VERSION="${TREE_SITTER_VERSION:-v0.26.3}"
LOCAL_BIN="$HOME/.local/bin"

# Resolved once so nvim and tree-sitter cannot disagree about the target arch.
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)
        NVIM_DIR_NAME="nvim-linux-x86_64"
        TREE_SITTER_ARCH="linux-x64"
        ;;
    aarch64)
        NVIM_DIR_NAME="nvim-linux-arm64"
        TREE_SITTER_ARCH="linux-arm64"
        ;;
    *)
        log_error "Unsupported architecture: $ARCH"
        add_closing_message "nvim setup skipped: unsupported architecture $ARCH."
        exit 0
        ;;
esac

NVIM_BIN_DIR="/opt/$NVIM_DIR_NAME/bin"

backup_if_exists() {
    local path="$1"

    if [ ! -e "$path" ]; then
        return 0
    fi

    local backup_path="${path}.bak"
    if [ -e "$backup_path" ]; then
        backup_path="${path}.bak.$(date +%Y%m%d%H%M%S)"
    fi

    if is_dry_run; then
        printf '[DRY-RUN] mv %s %s\n' "$path" "$backup_path"
    else
        mv "$path" "$backup_path"
        log_info "Backed up $path -> $backup_path"
    fi
}

install_nvim_latest() {
    log_info "Downloading latest stable neovim for $ARCH..."

    local nvim_file="$NVIM_DIR_NAME.tar.gz"
    local download_url="https://github.com/neovim/neovim/releases/download/stable/$nvim_file"

    if is_dry_run; then
        printf '[DRY-RUN] curl -fL -o <tmp>/%s %s\n' "$nvim_file" "$download_url"
        printf '[DRY-RUN] sudo rm -rf /opt/%s\n' "$NVIM_DIR_NAME"
        printf '[DRY-RUN] sudo tar -C /opt -xzf <tmp>/%s\n' "$nvim_file"
        return 0
    fi

    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' RETURN

    if ! curl -fsSL -o "$temp_dir/$nvim_file" "$download_url"; then
        log_error "Failed to download neovim from $download_url"
        return 1
    fi

    run_cmd sudo rm -rf "/opt/$NVIM_DIR_NAME"
    if ! run_cmd sudo tar -C /opt -xzf "$temp_dir/$nvim_file"; then
        log_error "Failed to extract neovim archive"
        return 1
    fi

    log_info "Installed neovim to /opt/$NVIM_DIR_NAME"
}

install_tree_sitter_cli() {
    if command -v tree-sitter >/dev/null 2>&1; then
        log_info "tree-sitter CLI already installed at $(command -v tree-sitter)"
        return 0
    fi

    # Prebuilt release binary. Building the crate from source needs a recent
    # rustc plus libclang for the rquickjs-sys bindgen step, which is what made
    # the old cargo-based path so fragile.
    local asset="tree-sitter-$TREE_SITTER_ARCH.gz"
    local url="https://github.com/tree-sitter/tree-sitter/releases/download/$TREE_SITTER_VERSION/$asset"

    if is_dry_run; then
        printf '[DRY-RUN] curl -fL %s | gzip -d > %s/tree-sitter\n' "$url" "$LOCAL_BIN"
        printf '[DRY-RUN] chmod +x %s/tree-sitter\n' "$LOCAL_BIN"
        ensure_path_entry "$LOCAL_BIN"
        return 0
    fi

    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' RETURN

    log_info "Downloading tree-sitter $TREE_SITTER_VERSION ($TREE_SITTER_ARCH)"
    if ! curl -fsSL -o "$temp_dir/$asset" "$url"; then
        log_error "Failed to download tree-sitter from $url"
        return 1
    fi

    if ! gzip -df "$temp_dir/$asset"; then
        log_error "Failed to decompress $asset"
        return 1
    fi

    mkdir -p "$LOCAL_BIN"
    if ! mv "$temp_dir/tree-sitter-$TREE_SITTER_ARCH" "$LOCAL_BIN/tree-sitter"; then
        log_error "Failed to install tree-sitter into $LOCAL_BIN"
        return 1
    fi

    chmod +x "$LOCAL_BIN/tree-sitter"
    ensure_path_entry "$LOCAL_BIN"
    log_info "Installed tree-sitter to $LOCAL_BIN/tree-sitter"
}

setup_node_for_mason() {
    # Mason installs several language servers through npm and resolves npm when
    # nvim starts, so node has to be on PATH before the first launch or those
    # servers quietly fail to install.
    if command -v npm >/dev/null 2>&1; then
        log_info "npm already available at $(command -v npm)"
        ensure_path_entry "$LOCAL_BIN"
        return 0
    fi

    log_info "Installing nodejs so Mason can manage npm-based language servers"
    if ! apt_install_packages nodejs node-corepack; then
        log_warn "Failed to install nodejs; Mason cannot install npm-based servers."
        add_closing_message "WARN: nodejs install failed; npm-based LSP servers in Mason will not install. Fix nodejs and rerun --nvim."
        return 1
    fi

    run_cmd mkdir -p "$LOCAL_BIN"

    if is_dry_run; then
        printf '[DRY-RUN] corepack enable --install-directory %s npm\n' "$LOCAL_BIN"
    elif ! corepack enable --install-directory "$LOCAL_BIN" npm; then
        log_warn "corepack could not shim npm into $LOCAL_BIN; Mason may not find npm."
    fi

    ensure_path_entry "$LOCAL_BIN"
}

# xclip talks to an X server. On WSL that is provided by WSLg, so it works
# there; on a native Wayland-only session it does not, and wl-clipboard is the
# right package instead.
clipboard_package() {
    if ! is_wsl && [ -n "${WAYLAND_DISPLAY:-}" ]; then
        printf 'wl-clipboard'
    else
        printf 'xclip'
    fi
}

# Kickstart-style reset, but only when about to clone into a directory this
# repo does not yet manage. Running it on every invocation would move the
# plugin and Mason state aside each time, so a rerun would re-bootstrap
# everything from scratch and leave a trail of .bak directories.
backup_nvim_state_before_clone() {
    if [ -e "$NVIM_TARGET_DIR" ] && [ ! -L "$NVIM_TARGET_DIR" ]; then
        backup_if_exists "$NVIM_TARGET_DIR"
    fi
    backup_if_exists "$HOME/.local/share/nvim"
    backup_if_exists "$HOME/.local/state/nvim"
    backup_if_exists "$HOME/.cache/nvim"
}

install_kickstart_external_dependencies() {
    apt_install_packages git make build-essential ripgrep fd-find unzip "$(clipboard_package)"

    # Best-effort: kickstart works without the CLI, parsers just compile via gcc.
    install_tree_sitter_cli || log_warn "tree-sitter CLI unavailable; parsers will compile via gcc."
    setup_node_for_mason || true
}

run_cmd mkdir -p "$LOCAL_BIN"

install_kickstart_external_dependencies

if ! command -v nvim >/dev/null 2>&1; then
    log_info "nvim not found, installing latest stable from GitHub..."
    if install_nvim_latest; then
        ensure_path_entry "$NVIM_BIN_DIR"
        add_closing_message "nvim installed. Restart your shell (or source your rc file), then run: nvim (plugins bootstrap on first launch)."
    else
        add_closing_message "WARN: nvim install failed. Rerun ./install.sh --nvim after checking network access to github.com."
    fi
else
    log_info "nvim already installed at $(command -v nvim)"
fi

if ! command -v git >/dev/null 2>&1; then
    log_info "git not found, attempting installation"
    apt_install_packages git
fi

run_cmd mkdir -p "$HOME/.config"

# Precedence: an explicit NVIM_CONFIG_REPO, then a local editors/nvim-config
# checkout, then the default private kickstart remote. The local checkout has to
# be tested before falling back to the default, otherwise it can never be used.
if [ -z "$NVIM_CONFIG_REPO" ] && [ -f "$LOCAL_NVIM_SOURCE/init.lua" ]; then
    if [ -e "$NVIM_TARGET_DIR" ] && [ ! -L "$NVIM_TARGET_DIR" ]; then
        backup_if_exists "$NVIM_TARGET_DIR"
    fi
    ensure_symlink "$LOCAL_NVIM_SOURCE" "$NVIM_TARGET_DIR"
    log_info "Linked nvim config from local editors/nvim-config"
else
    if [ -z "$NVIM_CONFIG_REPO" ]; then
        NVIM_CONFIG_REPO="$DEFAULT_KICKSTART_REPO"
    fi

    if [ -d "$NVIM_TARGET_DIR/.git" ]; then
        if is_dry_run; then
            printf '[DRY-RUN] git -C %s pull --ff-only\n' "$NVIM_TARGET_DIR"
        elif git -C "$NVIM_TARGET_DIR" pull --ff-only; then
            log_info "Updated nvim config from remote"
        else
            log_warn "Could not fast-forward $NVIM_TARGET_DIR; leaving it as-is."
        fi
    elif [ -L "$NVIM_TARGET_DIR" ]; then
        log_warn "$NVIM_TARGET_DIR is a symlink; leaving it as-is."
        log_warn "Remove the symlink if you want git clone management."
    else
        backup_nvim_state_before_clone

        if run_cmd git clone "$NVIM_CONFIG_REPO" "$NVIM_TARGET_DIR"; then
            log_info "Cloned nvim config from remote"
        else
            log_warn "Failed to clone $NVIM_CONFIG_REPO"
            case "$NVIM_CONFIG_REPO" in
                git@*)
                    # Common on a fresh machine: the SSH key is not set up yet.
                    log_warn "This is an SSH remote; a fresh machine needs a key on the host first."
                    add_closing_message "nvim config clone failed for $NVIM_CONFIG_REPO. Add an SSH key to GitHub, or rerun with an HTTPS URL: NVIM_CONFIG_REPO=https://github.com/AdrianMoen/kickstart.nvim.moen.git ./install.sh --nvim"
                    ;;
                *)
                    add_closing_message "nvim config clone failed for $NVIM_CONFIG_REPO. Check the URL and rerun: ./install.sh --nvim"
                    ;;
            esac
        fi
    fi
fi

log_info "nvim setup complete"
