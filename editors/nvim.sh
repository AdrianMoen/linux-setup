#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/common.sh
. "$SCRIPT_DIR/../core/common.sh"

NVIM_TARGET_DIR="$HOME/.config/nvim"
LOCAL_NVIM_SOURCE="$REPO_ROOT/editors/nvim-config"
NVIM_CONFIG_REPO="${NVIM_CONFIG_REPO:-}"
DEFAULT_KICKSTART_REPO="git@github.com:AdrianMoen/kickstart.nvim.moen.git"

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
    log_info "Downloading latest stable neovim..."

    local arch
    arch="$(uname -m)"
    local nvim_file
    local extracted_dir

    case "$arch" in
        x86_64)
            nvim_file="nvim-linux-x86_64.tar.gz"
            extracted_dir="nvim-linux-x86_64"
            ;;
        aarch64)
            nvim_file="nvim-linux-arm64.tar.gz"
            extracted_dir="nvim-linux-arm64"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    local download_url="https://github.com/neovim/neovim/releases/download/stable/$nvim_file"
    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' RETURN

    if is_dry_run; then
        printf '[DRY-RUN] curl -L -o %s/%s %s\n' "$temp_dir" "$nvim_file" "$download_url"
        printf '[DRY-RUN] sudo rm -rf /opt/%s\n' "$extracted_dir"
        printf '[DRY-RUN] sudo tar -C /opt -xzf %s/%s\n' "$temp_dir" "$nvim_file"
        printf '[DRY-RUN] ensure /opt/%s/bin is on PATH\n' "$extracted_dir"
        return 0
    fi

    if ! curl -sL -o "$temp_dir/$nvim_file" "$download_url"; then
        log_error "Failed to download neovim from $download_url"
        return 1
    fi

    run_cmd sudo rm -rf "/opt/$extracted_dir"
    run_cmd sudo tar -C /opt -xzf "$temp_dir/$nvim_file"

    log_info "Installed neovim to /opt/$extracted_dir"
}

ensure_nvim_in_path() {
    local profile_file
    local nvim_bin_dir

    if [ -d "/opt/nvim-linux-x86_64/bin" ]; then
        nvim_bin_dir="/opt/nvim-linux-x86_64/bin"
    elif [ -d "/opt/nvim-linux-arm64/bin" ]; then
        nvim_bin_dir="/opt/nvim-linux-arm64/bin"
    else
        # Fallback for dry-run or systems where extraction has not happened yet.
        nvim_bin_dir="/opt/nvim-linux-x86_64/bin"
    fi

    for profile_file in "$HOME/.zshrc" "$HOME/.bashrc"; do
        touch "$profile_file"
        if ! grep -Fq "$nvim_bin_dir" "$profile_file" 2>/dev/null; then
            if is_dry_run; then
                printf '[DRY-RUN] append to %s: export PATH=%s:$PATH\n' "$profile_file" "$nvim_bin_dir"
            else
                printf '\nexport PATH=%s:$PATH\n' "$nvim_bin_dir" >> "$profile_file"
                log_info "Updated PATH in $profile_file"
            fi
        fi
    done
}

ensure_cargo_bin_in_path() {
    local profile_file
    local cargo_bin_dir="$HOME/.cargo/bin"

    for profile_file in "$HOME/.zshrc" "$HOME/.bashrc"; do
        touch "$profile_file"
        if ! grep -Fq "$cargo_bin_dir" "$profile_file" 2>/dev/null; then
            if is_dry_run; then
                printf '[DRY-RUN] append to %s: export PATH=%s:$PATH\n' "$profile_file" "$cargo_bin_dir"
            else
                printf '\nexport PATH=%s:$PATH\n' "$cargo_bin_dir" >> "$profile_file"
                log_info "Updated PATH in $profile_file"
            fi
        fi
    done

    # Make the CLI usable within this same run too.
    case ":$PATH:" in
        *":$cargo_bin_dir:"*) ;;
        *) PATH="$cargo_bin_dir:$PATH" ;;
    esac
}

# Minimum rustc the current tree-sitter-cli crate needs to build.
RUST_MIN_VERSION="1.84.0"

rust_version_ok() {
    command -v rustc >/dev/null 2>&1 || return 1
    local current
    current="$(rustc --version 2>/dev/null | awk '{print $2}')"
    [ -n "$current" ] || return 1
    # True when current >= RUST_MIN_VERSION (lowest of the two is the minimum).
    [ "$(printf '%s\n%s\n' "$RUST_MIN_VERSION" "$current" | sort -V | head -n1)" = "$RUST_MIN_VERSION" ]
}

ensure_modern_rust() {
    # The apt rust toolchain is often too old (e.g. 1.75 on Ubuntu 22.04) to
    # build the current tree-sitter-cli. If so, install latest stable via rustup.
    if rust_version_ok; then
        return 0
    fi

    log_warn "Active rustc is older than $RUST_MIN_VERSION; installing latest stable via rustup."

    if ! command -v rustup >/dev/null 2>&1; then
        if is_dry_run; then
            printf '[DRY-RUN] curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path\n'
        elif ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
            log_warn "rustup installation failed."
            return 1
        fi
    fi

    ensure_cargo_bin_in_path

    if ! is_dry_run; then
        # shellcheck source=/dev/null
        [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
        rustup default stable >/dev/null 2>&1 || true
        rustup update stable >/dev/null 2>&1 || true
    fi

    rust_version_ok
}

install_tree_sitter_cli() {
    # The tree-sitter CLI binary is named `tree-sitter` (provided by the
    # `tree-sitter-cli` apt package or the `tree-sitter-cli` cargo crate).
    if command -v tree-sitter >/dev/null 2>&1; then
        log_info "tree-sitter CLI already installed at $(command -v tree-sitter)"
        return 0
    fi

    # 1. Try apt (only packaged on Ubuntu 23.04+/Debian 12+).
    log_info "Attempting to install tree-sitter-cli via apt..."
    if apt_install_packages tree-sitter-cli && command -v tree-sitter >/dev/null 2>&1; then
        log_info "Installed tree-sitter-cli via apt"
        return 0
    fi
    log_warn "tree-sitter-cli unavailable via apt; falling back to cargo."

    # 2. Ensure cargo (rust toolchain) is available.
    if ! command -v cargo >/dev/null 2>&1; then
        log_info "Installing cargo (rust toolchain) via apt..."
        if ! apt_install_packages cargo; then
            log_warn "Failed to install cargo; skipping tree-sitter-cli."
            log_warn "kickstart works without it (parsers compile via gcc)."
            add_closing_message "WARN: failed to install cargo for tree-sitter, fix valid tree-sitter-cli or cargo and rerun with --nvim"
            return 1
        fi
    fi

    # 2b. The current crate needs a recent rustc; upgrade via rustup if needed.
    if ! ensure_modern_rust; then
        log_warn "Could not provide rustc >= $RUST_MIN_VERSION; skipping tree-sitter-cli."
        log_warn "kickstart works without it (parsers compile via gcc)."
        add_closing_message "WARN: failed to ensure a recent rustc, fix a valid rustc and rerun with --nvim"
        return 1
    fi

    # 2c. Building tree-sitter-cli pulls in rquickjs-sys, whose bindgen step
    # needs libclang at compile time. Install it so the cargo build doesn't fail.
    if ! ldconfig -p 2>/dev/null | grep -q 'libclang'; then
        log_info "Installing libclang-dev (build dependency for tree-sitter-cli)..."
        if ! apt_install_packages libclang-dev; then
            log_warn "Failed to install libclang-dev; the cargo build will likely fail."
        fi
    fi

    # 3. Install the CLI from crates.io and make sure ~/.cargo/bin is on PATH.
    log_info "Installing tree-sitter-cli via cargo (this can take a few minutes)..."
    if is_dry_run; then
        printf '[DRY-RUN] cargo install tree-sitter-cli\n'
    elif ! cargo install tree-sitter-cli; then
        log_warn "cargo install tree-sitter-cli failed; skipping."
        log_warn "kickstart works without it (parsers compile via gcc)."
        add_closing_message "WARN: cargo failed to install tree-sitter-cli, fix a valid tree-sitter-cli and rerun with --nvim"
        return 1
    fi

    ensure_cargo_bin_in_path
    log_info "Installed tree-sitter-cli via cargo"
}

install_kickstart_external_dependencies () {
    apt_install_packages git make build-essential ripgrep fd-find unzip xclip

    # tree-sitter-cli is best-effort: apt first, then cargo as a fallback.
    install_tree_sitter_cli || true
}


install_kickstart_external_dependencies


if ! command -v nvim >/dev/null 2>&1; then
    log_info "nvim not found, installing latest stable from GitHub..."
    install_nvim_latest
    ensure_nvim_in_path
    log_info "nvim installed; restart your shell and run nvim to bootstrap plugins"
    add_closing_message "nvim installed. Restart your shell (or source your rc file), then run: nvim (plugins bootstrap on first launch)."
else
    log_info "nvim already installed at $(command -v nvim)"
fi

if ! command -v git >/dev/null 2>&1; then
    log_info "git not found, attempting installation"
    apt_install_packages git
fi

run_cmd mkdir -p "$HOME/.config"

if [ -z "$NVIM_CONFIG_REPO" ]; then
    NVIM_CONFIG_REPO="$DEFAULT_KICKSTART_REPO"
fi

if [ -n "$NVIM_CONFIG_REPO" ]; then
    # Kickstart-style reset: preserve any old nvim state before taking ownership.
    if [ ! -d "$NVIM_TARGET_DIR/.git" ] && [ -e "$NVIM_TARGET_DIR" ] && [ ! -L "$NVIM_TARGET_DIR" ]; then
        backup_if_exists "$NVIM_TARGET_DIR"
    fi
    backup_if_exists "$HOME/.local/share/nvim"
    backup_if_exists "$HOME/.local/state/nvim"
    backup_if_exists "$HOME/.cache/nvim"

    if [ -d "$NVIM_TARGET_DIR/.git" ]; then
        if is_dry_run; then
            printf '[DRY-RUN] git -C %s pull --ff-only\n' "$NVIM_TARGET_DIR"
        else
            git -C "$NVIM_TARGET_DIR" pull --ff-only
        fi
        log_info "Updated nvim config from remote"
    elif [ -L "$NVIM_TARGET_DIR" ]; then
        log_warn "$NVIM_TARGET_DIR is a symlink; leaving it as-is."
        log_warn "Remove the symlink if you want git clone management."
    else
        run_cmd git clone "$NVIM_CONFIG_REPO" "$NVIM_TARGET_DIR"
        log_info "Cloned nvim config from remote"
    fi
elif [ -f "$LOCAL_NVIM_SOURCE/init.lua" ]; then
    if [ -e "$NVIM_TARGET_DIR" ] && [ ! -L "$NVIM_TARGET_DIR" ]; then
        backup_if_exists "$NVIM_TARGET_DIR"
    fi
    ensure_symlink "$LOCAL_NVIM_SOURCE" "$NVIM_TARGET_DIR"
    log_info "Linked nvim config from local editors/nvim-config"
else
    log_warn "No nvim config source found."
    log_warn "Set NVIM_CONFIG_REPO to your private kickstart repo URL or add editors/nvim-config."
    add_closing_message "nvim has no config yet. Set NVIM_CONFIG_REPO to your kickstart repo URL and rerun --nvim, or add editors/nvim-config."
fi

log_info "nvim setup complete"
