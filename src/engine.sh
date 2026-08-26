#!/usr/bin/env bash
# ==============================================================================
# SECTION: INSTALLATION ENGINE
# ==============================================================================

_trim_profile_entry() {
    local entry="$1"
    entry=$(printf '%s' "$entry" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//')
    case "$entry" in
        \#*) entry="" ;;
    esac
    printf '%s' "$entry"
}

_profile_level_directory() {
    local level="$1"
    local candidate
    local -a matches=()
    for candidate in "$PROFILES_DIR/${level}_"*; do
        if [ -d "$candidate" ] && [ ! -L "$candidate" ]; then
            matches+=("$candidate")
        fi
    done
    [ "${#matches[@]}" -eq 1 ] || return 1
    printf '%s\n' "${matches[0]}"
}

_profile_directory() {
    local profile="$1"
    if [ -n "${PROFILE_PATH_OVERRIDE:-}" ]; then
        printf '%s\n' "$PROFILE_PATH_OVERRIDE"
        return 0
    fi
    validate_profile_name "$profile" >/dev/null 2>&1 || return 1
    printf '%s\n' "$PROFILES_DIR/$profile"
}

_read_profile_file() {
    local list_file="$1"
    [ -f "$list_file" ] || return 0

    local raw entry
    while IFS= read -r raw || [ -n "$raw" ]; do
        entry=$(_trim_profile_entry "$raw")
        [ -z "$entry" ] && continue
        if [[ "$entry" =~ [[:space:]] ]] || [[ "$entry" == -* ]]; then
            printf 'Ashno ignored malformed package entry in %s: %s\n' "$list_file" "$raw" >&2
            continue
        fi
        printf '%s\n' "$entry"
    done < "$list_file"
}

build_package_list() {
    local package_type="$1"
    local profile="$2"
    local profile_dir
    profile_dir=$(_profile_directory "$profile") || return 1

    local -a files=()
    local level level_dir list_file
    if [[ "$profile" =~ ^([0-9]+)_.+ ]] && [ -z "${PROFILE_PATH_OVERRIDE:-}" ]; then
        level="${BASH_REMATCH[1]}"
        local i
        for ((i = 1; i <= level; i++)); do
            level_dir=$(_profile_level_directory "$i") || continue
            list_file="$level_dir/$package_type.list"
            [ -f "$list_file" ] && files+=("$list_file")
        done
    else
        list_file="$profile_dir/$package_type.list"
        [ -f "$list_file" ] && files+=("$list_file")
    fi

    [ "${#files[@]}" -gt 0 ] || return 0
    local file
    for file in "${files[@]}"; do
        _read_profile_file "$file"
    done | sort -u
}

_check_network() {
    command -v curl >/dev/null 2>&1 || return 1
    curl --fail --silent --show-error --location \
        --connect-timeout "$NETWORK_TIMEOUT" --max-time "$NETWORK_TIMEOUT" \
        --head "$REPOSITORY_URL" >/dev/null 2>&1
}

pre_flight_checks() {
    local action="${1:---all}"
    print_banner "Performing System Checks"

    if ! command -v pkg >/dev/null 2>&1; then
        print_formatting error "Termux pkg is not available. Run this tool inside Termux."
        return 1
    fi
    print_formatting success "Termux package manager: available"

    if ! _check_network; then
        print_formatting error "Network access to GitHub: unavailable"
        return 1
    fi
    print_formatting success "Network access: available"

    case "$action" in
        --npm)
            command -v npm >/dev/null 2>&1 || print_formatting info "Node.js will be installed before NPM packages."
            ;;
        --pip)
            command -v pip >/dev/null 2>&1 || print_formatting info "Python will be installed before PIP packages."
            ;;
        --all)
            command -v npm >/dev/null 2>&1 || print_formatting info "Node.js will be installed before NPM packages."
            command -v pip >/dev/null 2>&1 || print_formatting info "Python will be installed before PIP packages."
            ;;
    esac
    return 0
}

_execute_logged() {
    local seconds="$1"
    local label="$2"
    shift 2
    ensure_run_log_dir || return 1
    local safe_label
    safe_label=$(printf '%s' "$label" | tr -cd 'A-Za-z0-9_.-')
    [ -n "$safe_label" ] || safe_label='command'
    local log_file="$ASHNO_RUN_LOG_DIR/${safe_label}.log"

    (run_timed "$seconds" "$@") >"$log_file" 2>&1 &
    local pid=$!
    spinner "$pid"
    wait "$pid"
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        print_formatting error "${label} failed (exit ${rc}); log: ${log_file}"
    fi
    return "$rc"
}

update_termux() {
    require_termux || return 1
    print_banner "Updating Termux Base System"
    if _execute_logged "$INSTALL_TIMEOUT_BATCH" termux-update \
        pkg update -y -o Dpkg::Options::=--force-confnew && \
        _execute_logged "$INSTALL_TIMEOUT_BATCH" termux-upgrade \
        pkg upgrade -y -o Dpkg::Options::=--force-confnew; then
        print_formatting success "Base system update complete."
        return 0
    fi
    print_formatting error "Termux base system update failed."
    return 1
}

check_pkg_installed() {
    local package_name="${1%%=*}"
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null \
            | grep -q 'install ok installed'
    else
        pkg list-installed "$package_name" 2>/dev/null | grep -q "$package_name"
    fi
}

check_npm_installed() {
    command -v npm >/dev/null 2>&1 || return 1
    local package_name="$1"
    case "$package_name" in
        @*/*@*) package_name="${package_name%@*}" ;;
        @*) ;;
        *@*) package_name="${package_name%@*}" ;;
    esac
    npm list -g --depth=0 "$package_name" >/dev/null 2>&1
}

check_pip_installed() {
    command -v pip >/dev/null 2>&1 || return 1
    local package_name="${1%%[<>=!~]*}"
    pip show "$package_name" >/dev/null 2>&1
}

_install_batch() {
    local manager="$1"
    local label="$2"
    shift 2
    local -a packages=("$@")
    local -a command_args=()
    case "$manager" in
        pkg) command_args=(pkg install -y) ;;
        npm)
            command_args=(npm install -g)
            [ "$ALLOW_NPM_SCRIPTS" = true ] || command_args+=(--ignore-scripts)
            ;;
        pip) command_args=(pip install --no-cache-dir) ;;
        *) return 2 ;;
    esac
    _execute_logged "$INSTALL_TIMEOUT_BATCH" "$label-batch" \
        "${command_args[@]}" "${packages[@]}"
}

_install_one() {
    local manager="$1"
    local package_name="$2"
    local -a command_args=()
    case "$manager" in
        pkg) command_args=(pkg install -y) ;;
        npm)
            command_args=(npm install -g)
            [ "$ALLOW_NPM_SCRIPTS" = true ] || command_args+=(--ignore-scripts)
            ;;
        pip) command_args=(pip install --no-cache-dir) ;;
        *) return 2 ;;
    esac
    _execute_logged "$INSTALL_TIMEOUT_SINGLE" "$manager-$(printf '%s' "$package_name" | tr -cd 'A-Za-z0-9_.-')" \
        "${command_args[@]}" "$package_name"
}

_install_packages() {
    local manager="$1"
    shift
    local -a package_list=("$@")
    local -a pending=()
    local package_name
    local check_function

    case "$manager" in
        pkg) check_function=check_pkg_installed ;;
        npm) check_function=check_npm_installed ;;
        pip) check_function=check_pip_installed ;;
        *) return 2 ;;
    esac

    for package_name in "${package_list[@]}"; do
        [ -n "$package_name" ] || continue
        if "$check_function" "$package_name"; then
            SKIPPED_LIST+=("$package_name")
            print_formatting info "${package_name} (already installed)"
        else
            pending+=("$package_name")
        fi
    done
    [ "${#pending[@]}" -gt 0 ] || return 0

    local label="$manager"
    print_formatting info "Installing ${#pending[@]} ${manager^^} packages"
    if _install_batch "$manager" "$label" "${pending[@]}"; then
        for package_name in "${pending[@]}"; do
            SUCCESS_LIST+=("$package_name")
        done
        print_formatting success "${#pending[@]} ${manager^^} packages installed"
        return 0
    fi

    print_formatting warn "Batch installation failed; retrying packages individually."
    local rc=0
    for package_name in "${pending[@]}"; do
        if "$check_function" "$package_name"; then
            SKIPPED_LIST+=("$package_name")
            print_formatting info "${package_name} became installed during batch attempt"
        elif _install_one "$manager" "$package_name"; then
            SUCCESS_LIST+=("$package_name")
            print_formatting success "$package_name"
        else
            FAILURE_LIST+=("$package_name")
            rc=1
        fi
    done
    return "$rc"
}

install_pkg() {
    print_banner "Installing PKG Packages"
    require_termux || return 1
    local package_list
    package_list=$(build_package_list pkg "$SELECTED_PROFILE") || return 1
    if [ -z "$package_list" ]; then
        print_formatting warn "No PKG packages found in this profile."
        return 0
    fi
    mapfile -t list_array <<< "$package_list"
    _install_packages pkg "${list_array[@]}"
}

install_npm() {
    print_banner "Installing NPM Packages"
    require_termux || return 1
    if ! command -v npm >/dev/null 2>&1; then
        print_formatting info "NPM not found. Installing Node.js first."
        _execute_logged "$INSTALL_TIMEOUT_SINGLE" install-nodejs pkg install -y nodejs || return 1
    fi
    local package_list
    package_list=$(build_package_list npm "$SELECTED_PROFILE") || return 1
    if [ -z "$package_list" ]; then
        print_formatting warn "No NPM packages found in this profile."
        return 0
    fi
    if [ "$ALLOW_NPM_SCRIPTS" = false ]; then
        print_formatting info "NPM lifecycle scripts are disabled by default; use --allow-npm-scripts to opt in."
    fi
    mapfile -t list_array <<< "$package_list"
    _install_packages npm "${list_array[@]}"
}

install_pip() {
    print_banner "Installing PIP Packages"
    require_termux || return 1
    if ! command -v pip >/dev/null 2>&1; then
        print_formatting info "PIP not found. Installing Python first."
        _execute_logged "$INSTALL_TIMEOUT_SINGLE" install-python pkg install -y python || return 1
    fi

    if ! _execute_logged "$INSTALL_TIMEOUT_SINGLE" pip-core pip install --upgrade pip setuptools wheel; then
        print_formatting warn "PIP core upgrade failed; continuing with the existing version."
    fi

    local package_list
    package_list=$(build_package_list pip "$SELECTED_PROFILE") || return 1
    if [ -z "$package_list" ]; then
        print_formatting warn "No PIP packages found in this profile."
        return 0
    fi
    mapfile -t list_array <<< "$package_list"
    _install_packages pip "${list_array[@]}"
}
