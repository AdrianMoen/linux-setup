#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
RUN_ANY=0
CLOSING_FILE=""

# Module toggles
RUN_APT=0
RUN_ZSH=0
RUN_OHMYZSH=0
RUN_ALIASES=0
RUN_VIM=0
RUN_TMUX=0
RUN_ALACRITTY=0
RUN_FONT=0
RUN_GIT=0

print_usage() {
    cat <<'EOF'
Usage:
  ./install.sh [flags]

Flags:
  --all        Run all modules
  --apt        Run apt/package setup
  --zsh        Install/configure zsh
  --ohmyzsh    Install/configure oh-my-zsh
  --aliases    Apply aliases setup
  --vim        Install/configure neovim (compat alias)
  --nvim       Install/configure neovim
  --tmux       Install/configure tmux
  --alacritty  Install/configure alacritty
  --font       Install the JetBrainsMonoNL Nerd Font
  --git        Apply git config setup
  --dry-run    Show what would run without executing
  --help       Show this help message

Examples:
  ./install.sh --all
  ./install.sh --apt --zsh --ohmyzsh --aliases --nvim --tmux --git
  ./install.sh --git --dry-run
EOF
}

log() {
    printf '[INFO] %s\n' "$1"
}

warn() {
    printf '[WARN] %s\n' "$1"
}

err() {
    printf '[ERROR] %s\n' "$1" >&2
}

run_script_if_exists() {
    local label="$1"
    local script_path="$2"

    if [ ! -f "$script_path" ]; then
        warn "$label module not found at: $script_path (skipping)"
        return 0
    fi

    log "Running $label module: $script_path"

    # Modules are run even in dry-run mode: each one guards its own side
    # effects with is_dry_run/run_cmd, so letting them execute is what actually
    # reports the planned changes. Short-circuiting here would just print the
    # module name and skip every [DRY-RUN] line it would have produced.
    LINUX_SETUP_DRY_RUN="$DRY_RUN" LINUX_SETUP_CLOSING_FILE="$CLOSING_FILE" bash "$script_path"
}

run_aliases_module() {
    # Prefer the planned modular path, with a fallback to the current legacy script.
    if [ -f "$SCRIPT_DIR/shell/aliases.sh" ]; then
        run_script_if_exists "aliases" "$SCRIPT_DIR/shell/aliases.sh"
    else
        run_script_if_exists "aliases" "$SCRIPT_DIR/setup_aliases.sh" # i removed this script btw...
    fi
}

run_editor_module() {
    # Prefer nvim.sh, keep vim.sh as backward-compatible fallback.
    if [ -f "$SCRIPT_DIR/editors/nvim.sh" ]; then
        run_script_if_exists "nvim" "$SCRIPT_DIR/editors/nvim.sh"
    else
        run_script_if_exists "nvim" "$SCRIPT_DIR/editors/vim.sh"
    fi
}

print_closing_messages() {
    if [ -z "$CLOSING_FILE" ] || [ ! -s "$CLOSING_FILE" ]; then
        return 0
    fi

    printf '\n'
    printf '==================== NEXT STEPS ====================\n'
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf '  - %s\n' "$line"
    done < "$CLOSING_FILE"
    printf '===================================================\n'
}

parse_args() {
    if [ "$#" -eq 0 ]; then
        print_usage
        exit 0
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --all)
                RUN_APT=1
                RUN_ZSH=1
                RUN_OHMYZSH=1
                RUN_ALIASES=1
                RUN_VIM=1
                RUN_TMUX=1
                RUN_ALACRITTY=1
                RUN_FONT=1
                RUN_GIT=1
                RUN_ANY=1
                ;;
            --apt)
                RUN_APT=1
                RUN_ANY=1
                ;;
            --zsh)
                RUN_ZSH=1
                RUN_ANY=1
                ;;
            --ohmyzsh)
                RUN_OHMYZSH=1
                RUN_ANY=1
                ;;
            --aliases)
                RUN_ALIASES=1
                RUN_ANY=1
                ;;
            --vim|--nvim)
                RUN_VIM=1
                RUN_ANY=1
                ;;
            --tmux)
                RUN_TMUX=1
                RUN_ANY=1
                ;;
            --alacritty)
                RUN_ALACRITTY=1
                RUN_ANY=1
                ;;
            --font|--nerdfont)
                RUN_FONT=1
                RUN_ANY=1
                ;;
            --git)
                RUN_GIT=1
                RUN_ANY=1
                ;;
            --dry-run)
                DRY_RUN=1
                ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            *)
                err "Unknown flag: $1"
                print_usage
                exit 1
                ;;
        esac
        shift
    done

    if [ "$RUN_ANY" -eq 0 ]; then
        warn "No modules selected. Use --help for available flags."
        exit 1
    fi
}

main() {
    parse_args "$@"

    log "Starting linux setup"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "Dry-run mode enabled; no commands will be executed"
    fi

    CLOSING_FILE="$(mktemp)"
    trap 'rm -f "$CLOSING_FILE"' EXIT

    if [ "$RUN_APT" -eq 1 ]; then
        run_script_if_exists "apt" "$SCRIPT_DIR/core/apt.sh"
    fi

    if [ "$RUN_ZSH" -eq 1 ]; then
        run_script_if_exists "zsh" "$SCRIPT_DIR/shell/zsh.sh"
    fi

    if [ "$RUN_OHMYZSH" -eq 1 ]; then
        run_script_if_exists "oh-my-zsh" "$SCRIPT_DIR/shell/ohmyzsh.sh"
    fi

    if [ "$RUN_ALIASES" -eq 1 ]; then
        run_aliases_module
    fi

    if [ "$RUN_VIM" -eq 1 ]; then
        run_editor_module
    fi

    if [ "$RUN_TMUX" -eq 1 ]; then
        run_script_if_exists "tmux" "$SCRIPT_DIR/terminal/tmux.sh"
    fi

    if [ "$RUN_ALACRITTY" -eq 1 ]; then
        run_script_if_exists "alacritty" "$SCRIPT_DIR/terminal/alacritty.sh"
    fi

    if [ "$RUN_FONT" -eq 1 ]; then
        run_script_if_exists "font" "$SCRIPT_DIR/fonts/nerdfont.sh"
    fi

    if [ "$RUN_GIT" -eq 1 ]; then
        run_script_if_exists "git" "$SCRIPT_DIR/git/gitconfig.sh"
    fi

    log "Setup run complete"
    print_closing_messages
}

main "$@"
