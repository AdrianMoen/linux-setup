#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/common.sh
. "$SCRIPT_DIR/../core/common.sh"

# Pinned so a rerun on another machine gets byte-identical fonts.
NERD_FONT_VERSION="${NERD_FONT_VERSION:-v3.5.1}"

# The release zip is ~128MB and holds 6 families x 16 weights. Only the plain
# "NoLigatures" family is used (configs/alacritty/base.toml asks for
# "JetBrainsMonoNL NF"), and a terminal only ever renders these four faces, so
# fetch the individual files instead: ~9.5MB total, and no unzip dependency.
FONT_BASE_URL="https://github.com/ryanoasis/nerd-fonts/raw/$NERD_FONT_VERSION/patched-fonts/JetBrainsMono/NoLigatures"
FONT_PREFIX="JetBrainsMonoNLNerdFont"
FONT_STYLES="Regular Bold Italic BoldItalic"

# The patched TTFs register two family names: the full "JetBrainsMonoNL Nerd
# Font" and the legacy "JetBrainsMonoNL NF". Either may appear in a config, so
# accept both when checking whether the font is already present.
FONT_FAMILY_PATTERN="JetBrainsMonoNL (Nerd Font|NF)"

download_fonts() {
    local dest_dir="$1"
    local style url target

    for style in $FONT_STYLES; do
        target="$dest_dir/$FONT_PREFIX-$style.ttf"
        url="$FONT_BASE_URL/$FONT_PREFIX-$style.ttf"

        if is_dry_run; then
            printf '[DRY-RUN] curl -fL -o %s %s\n' "$target" "$url"
            continue
        fi

        log_info "Downloading $FONT_PREFIX-$style.ttf"
        if ! curl -fsSL -o "$target" "$url"; then
            log_error "Failed to download $url"
            return 1
        fi

        # A truncated or HTML error page would silently install as a dead font.
        if [ ! -s "$target" ]; then
            log_error "Downloaded font is empty: $target"
            return 1
        fi
    done
}

font_installed_linux() {
    command -v fc-list >/dev/null 2>&1 || return 1
    fc-list : family 2>/dev/null | grep -Eq "$FONT_FAMILY_PATTERN"
}

# Windows keeps machine-wide fonts in C:\Windows\Fonts and per-user ones under
# %LOCALAPPDATA%. Checking for the files is enough to avoid re-downloading and
# re-littering Downloads on every rerun; reading the registry would be more
# precise but is not worth it just for an idempotency check.
font_installed_windows() {
    local dir style found
    for dir in "/mnt/c/Windows/Fonts" "$WIN_USERPROFILE/AppData/Local/Microsoft/Windows/Fonts"; do
        [ -d "$dir" ] || continue
        found=1
        for style in $FONT_STYLES; do
            if [ ! -f "$dir/$FONT_PREFIX-$style.ttf" ]; then
                found=0
                break
            fi
        done
        [ "$found" -eq 1 ] && return 0
    done
    return 1
}

install_native() {
    local font_dir="$HOME/.local/share/fonts"

    if font_installed_linux; then
        log_info "JetBrainsMonoNL Nerd Font already installed (fontconfig)"
        return 0
    fi

    if ! command -v fc-cache >/dev/null 2>&1; then
        log_info "fontconfig not found, attempting installation"
        apt_install_packages fontconfig
    fi

    run_cmd mkdir -p "$font_dir"
    download_fonts "$font_dir" || return 1
    run_cmd fc-cache -f "$font_dir"

    log_info "Installed JetBrainsMonoNL Nerd Font to $font_dir"
    add_closing_message "JetBrainsMonoNL Nerd Font installed. Set your terminal font to 'JetBrainsMonoNL NF'."
}

# On WSL the terminal is a Windows process rendering with Windows-registered
# fonts, so a fontconfig install inside the distro would be invisible to it.
# Stage the files where Explorer can see them and let the user run the install:
# doing it automatically would mean writing to the Windows registry, which is
# more than a setup script should do behind your back.
install_wsl() {
    log_info "WSL detected; staging fonts for a manual Windows install."

    if ! load_windows_paths; then
        log_warn "Could not resolve Windows paths (cmd.exe/wslpath unavailable)."
        add_closing_message "Fonts: could not reach the Windows filesystem. Download JetBrainsMono from https://github.com/ryanoasis/nerd-fonts/releases/tag/$NERD_FONT_VERSION and install the JetBrainsMonoNLNerdFont-*.ttf faces on Windows."
        return 0
    fi

    if font_installed_windows; then
        log_info "JetBrainsMonoNL Nerd Font already installed on Windows"
        return 0
    fi

    local stage_dir="$WIN_USERPROFILE/Downloads/nerd-fonts-jetbrainsmono-nl"
    run_cmd mkdir -p "$stage_dir"
    download_fonts "$stage_dir" || return 1

    local win_display
    win_display="$(to_windows_path "$stage_dir")"

    log_info "Staged fonts in $win_display"
    add_closing_message "Fonts staged in $win_display -- open it in Explorer, select all four .ttf files, right-click and choose Install (or 'Install for all users'). Restart alacritty afterwards, then confirm the font is 'JetBrainsMonoNL NF'."
}

if ! command -v curl >/dev/null 2>&1; then
    log_info "curl not found, attempting installation"
    apt_install_packages curl
fi

if is_wsl; then
    install_wsl
else
    install_native
fi

log_info "Nerd Font setup complete"
