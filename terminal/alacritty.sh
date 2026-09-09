#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/common.sh
. "$SCRIPT_DIR/../core/common.sh"

CONFIG_SOURCE_DIR="$REPO_ROOT/configs/alacritty"

# Alacritty itself is installed on the Windows host (winget/scoop/msi), which
# is outside this repo's remit. Warn rather than fail: writing the config for a
# not-yet-installed alacritty is harmless and correct once it is installed.
warn_if_windows_alacritty_missing() {
    command -v where.exe >/dev/null 2>&1 || return 0

    # Run from /mnt/c so where.exe does not complain about a UNC working dir.
    if (cd /mnt/c 2>/dev/null && where.exe alacritty >/dev/null 2>&1); then
        return 0
    fi

    log_warn "alacritty does not appear to be installed on the Windows host."
    add_closing_message "alacritty is not installed on Windows. Install it there (e.g. winget install Alacritty.Alacritty), then rerun ./install.sh --alacritty."
}

# On WSL, alacritty is a Windows application: it runs on the host and spawns
# wsl.exe. Installing the Linux build inside the distro would be a second,
# unused terminal, so this module only manages the Windows-side config there.
setup_wsl() {
    log_info "WSL detected; managing the Windows-side alacritty config only."
    warn_if_windows_alacritty_missing

    if ! load_windows_paths; then
        log_warn "Could not resolve Windows paths (cmd.exe/wslpath unavailable)."
        add_closing_message "alacritty: could not reach the Windows filesystem; copy configs/alacritty/{base,windows}.toml to %APPDATA%\\alacritty\\ manually (windows.toml becomes alacritty.toml)."
        return 0
    fi

    local target_dir="$WIN_APPDATA/alacritty"
    local backup_dir="$WIN_APPDATA/alacritty.bak.$(date +%Y%m%d_%H%M%S)"
    local win_display
    win_display="$(to_windows_path "$target_dir")"

    if is_dry_run; then
        if [ -d "$target_dir" ]; then
            printf '[DRY-RUN] cp -r %s %s\n' "$target_dir" "$backup_dir"
        else
            printf '[DRY-RUN] mkdir -p %s\n' "$target_dir"
        fi
        printf '[DRY-RUN] cp %s/base.toml %s/base.toml\n' "$CONFIG_SOURCE_DIR" "$target_dir"
        printf '[DRY-RUN] cp %s/windows.toml %s/alacritty.toml\n' "$CONFIG_SOURCE_DIR" "$target_dir"
    else

        # Backup target dir
        if [ -d "$target_dir" ]; then
            log_info "Backing up existing alacritty directory to $backup_dir"
            cp -r "$target_dir" "$backup_dir"
        else
            mkdir -p "$target_dir"
        fi


        # Copies, not symlinks: Windows will not follow a symlink created from
        # WSL, so config edits need a rerun of this module to take effect.
        if ! cp "$CONFIG_SOURCE_DIR/base.toml" "$target_dir/base.toml"; then
            log_error "Failed to copy base.toml to $win_display"
            return 1
        fi

        if ! cp "$CONFIG_SOURCE_DIR/windows.toml" "$target_dir/alacritty.toml"; then
            log_error "Failed to copy windows.toml to $win_display"
            return 1
        fi

        log_info "Installed alacritty config to $win_display"
    fi

    add_closing_message "alacritty config copied to $win_display (no symlink, rerun ./install.sh --alacritty after editing configs/alacritty/ in this repo). Restart alacritty to pick it up."
}

setup_native() {
    if ! command -v alacritty >/dev/null 2>&1; then
        log_info "alacritty not found, attempting installation"
        apt_install_packages snap
        run_cmd sudo snap install alacritty --classic
    else
        log_info "alacritty already installed at $(command -v alacritty)"
    fi

    local target_dir="$HOME/.config/alacritty"
    run_cmd mkdir -p "$target_dir"

    ensure_symlink "$CONFIG_SOURCE_DIR/base.toml" "$target_dir/base.toml"
    ensure_symlink "$CONFIG_SOURCE_DIR/linux.toml" "$target_dir/alacritty.toml"

    add_closing_message "alacritty configured. Set your terminal font to 'JetBrainsMonoNL NF' if it is not picked up automatically (run ./install.sh --font to install it)."
}


#############################################################
#                                                           #
#                    ENTRYPOINT                             #
#                                                           #
#############################################################
if [ ! -d "$CONFIG_SOURCE_DIR" ]; then
    log_error "Missing $CONFIG_SOURCE_DIR; cannot configure alacritty."
    exit 0
fi

if is_wsl; then
    setup_wsl
else
    setup_native
fi

log_info "alacritty setup complete"
