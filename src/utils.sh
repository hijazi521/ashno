#!/usr/bin/env bash
# ==============================================================================
# SECTION: UTILITY & UI HELPERS
# ==============================================================================

# Importing this module must be side-effect free. The entrypoint decides when
# optional Termux UI dependencies should be installed.

bootstrap_core() {
    local missing=()
    command -v tput >/dev/null 2>&1 || missing+=(ncurses-utils)
    command -v gum >/dev/null 2>&1 || missing+=(gum)
    [ "${#missing[@]}" -eq 0 ] && return 0

    if ! command -v pkg >/dev/null 2>&1; then
        printf 'Ashno requires Termux pkg to install optional UI dependencies.\n' >&2
        return 1
    fi

    printf 'Installing optional UI dependencies: %s\n' "${missing[*]}"
    if ! pkg update -y -o Dpkg::Options::=--force-confnew; then
        printf 'Unable to update Termux package indexes.\n' >&2
        return 1
    fi
    if ! pkg install -y "${missing[@]}"; then
        printf 'Unable to install optional UI dependencies.\n' >&2
        return 1
    fi
}

cursor_hide() {
    if command -v tput >/dev/null 2>&1; then
        tput civis 2>/dev/null || true
    fi
}

cursor_show() {
    if command -v tput >/dev/null 2>&1; then
        tput cnorm 2>/dev/null || true
    fi
}

cleanup_runtime() {
    cursor_show
    if [ -n "${ASHNO_RUN_LOG_DIR:-}" ] && [ -d "$ASHNO_RUN_LOG_DIR" ]; then
        chmod -R go-rwx "$ASHNO_RUN_LOG_DIR" 2>/dev/null || true
    fi
}

handle_signal() {
    cleanup_runtime
    printf '\n\n%sSIGINT received. Shutting down safely.%s\n' "$YELLOW" "$NC" >&2
    exit 130
}

trap handle_signal INT TERM

fatal_error() {
    print_formatting error "$1"
    return 1
}

validate_profile_name() {
    local name="$1"
    if [ -z "$name" ] || [[ ! "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        return 1
    fi
    local profile_path="$PROFILES_DIR/$name"
    [ -d "$profile_path" ] || return 1
    [ ! -L "$profile_path" ] || return 1
    local root candidate
    root=$(CDPATH='' cd -- "$PROFILES_DIR" && pwd -P) || return 1
    candidate=$(CDPATH='' cd -- "$profile_path" && pwd -P) || return 1
    case "$candidate/" in
        "$root"/*) return 0 ;;
        *) return 1 ;;
    esac
}

require_termux() {
    command -v pkg >/dev/null 2>&1 || {
        print_formatting error "This operation requires the Termux pkg command."
        return 1
    }
}

ensure_run_log_dir() {
    if [ -z "${ASHNO_RUN_LOG_DIR:-}" ]; then
        ASHNO_RUN_LOG_DIR="$ASHNO_LOG_ROOT/$(date +%Y%m%d_%H%M%S)_$$"
    fi
    if ! mkdir -p "$ASHNO_RUN_LOG_DIR"; then
        printf 'Cannot create private log directory: %s\n' "$ASHNO_RUN_LOG_DIR" >&2
        return 1
    fi
    chmod 700 "$ASHNO_RUN_LOG_DIR" 2>/dev/null || true
}

# Execute a command with a bounded timeout when the timeout utility exists.
# The command and all arguments must be passed as separate words/array items.
run_timed() {
    local seconds="$1"
    shift
    if ! [[ "$seconds" =~ ^[0-9]+$ ]] || [ "$seconds" -le 0 ]; then
        printf 'Invalid timeout: %s\n' "$seconds" >&2
        return 2
    fi
    if command -v timeout >/dev/null 2>&1; then
        timeout --preserve-status "$seconds" "$@"
    else
        "$@"
    fi
}

# Run a command in the background, showing a spinner, then return its status.
run_with_spinner() {
    local seconds="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout --preserve-status "$seconds" "$@" >/dev/null 2>&1 &
    else
        "$@" >/dev/null 2>&1 &
    fi
    local pid=$!
    spinner "$pid"
    wait "$pid"
    return $?
}

run_logged() {
    local seconds="$1"
    local log_name="$2"
    shift 2
    ensure_run_log_dir || return 1
    local log_file="$ASHNO_RUN_LOG_DIR/$log_name.log"
    run_timed "$seconds" "$@" >"$log_file" 2>&1
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        return 0
    fi
    printf '%s\n' "Command failed; log: $log_file" >&2
    return "$rc"
}

print_banner() {
    local title="$1"
    if command -v gum >/dev/null 2>&1; then
        printf '\n'
        gum style --border double --margin '0 1' --padding '0 3' \
            --border-foreground 212 --foreground 212 --bold --align center "$title"
        printf '\n'
    else
        local padded=" $title "
        local inner_len=$(( ${#padded} + 2 ))
        local border_line
        border_line=$(printf '─%.0s' $(seq 1 "$inner_len"))
        printf '\n%s╭─%s─╮%s\n' "$BLUE" "$border_line" "$NC"
        printf '%s│  %s%s%s  │%s\n' "$BLUE" "$BOLD" "$YELLOW" "$padded" "$NC"
        printf '%s╰─%s─╯%s\n' "$BLUE" "$border_line" "$NC"
    fi
}

print_formatting() {
    local mode="$1"
    local msg="$2"
    if command -v gum >/dev/null 2>&1; then
        local badge badge_text
        case "$mode" in
            info)    badge=$(gum style --foreground 255 --background 39 --bold ' INFO '); badge_text=$(gum style --foreground 39 "$msg") ;;
            success) badge=$(gum style --foreground 255 --background 46 --bold '  OK  '); badge_text=$(gum style --foreground 46 "$msg") ;;
            warn)    badge=$(gum style --foreground 0 --background 214 --bold ' WARN '); badge_text=$(gum style --foreground 214 "$msg") ;;
            error)   badge=$(gum style --foreground 255 --background 196 --bold ' FAIL '); badge_text=$(gum style --foreground 196 "$msg") ;;
            *)       badge=$(gum style --foreground 255 --background 39 --bold ' INFO '); badge_text=$(gum style --foreground 39 "$msg") ;;
        esac
        printf '%s %s\n' "$badge" "$badge_text"
        return 0
    fi
    case "$mode" in
        info)    printf ' %sℹ%s %s\n' "$BLUE" "$NC" "$msg" ;;
        success) printf ' %s✔%s %s\n' "$GREEN" "$NC" "$msg" ;;
        warn)    printf ' %s⚠%s %s\n' "$YELLOW" "$NC" "$msg" ;;
        error)   printf ' %s✖%s %s\n' "$RED" "$NC" "$msg" >&2 ;;
        *)       printf ' %s%s%s\n' "$NC" "$msg" "$NC" ;;
    esac
}

print_prompt() { printf '\n%s>%s%s Select an option:%s ' "$CYAN" "$NC" "$BOLD" "$NC"; }

spinner() {
    local pid="$1"
    cursor_hide
    local frames='⣾⣽⣻⢿⡿⣟⣯⣷'
    local index=0
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r\033[38;5;212m%s\033[0m' "${frames:index:1}"
        index=$(( (index + 1) % ${#frames} ))
        sleep 0.08
    done
    printf '\r '
    cursor_show
}

wait_for_key() {
    if [ "$NONINTERACTIVE" = true ]; then
        return 0
    fi
    if command -v gum >/dev/null 2>&1; then
        gum style --foreground 245 --italic --margin '0 2' 'Press any key to continue...'
    else
        printf '  Press any key to continue...\n'
    fi
    IFS= read -r -n 1 -s || true
}
