#!/usr/bin/env bash
# shellcheck disable=SC2034
# ==============================================================================
# SECTION: MENUS & REPORTING
# ==============================================================================

print_help_menu() {
    cat <<EOF
Ashno ${ASHNO_VERSION} — Termux toolkit installer and configurator

Usage:
  ashno                                  Launch the interactive menu
  ashno --profile NAME --all             Install all profile packages
  ashno --profile NAME --pkg|--npm|--pip Install one package type

Commands:
  -h, --help                             Show this help
      --version                          Show the installed version
  -u, --update                           Check for and apply a verified update
  -c, --configure                        Configure installed tools
  -b, --backup                           Create a private backup archive
      --restore FILE                     Validate and restore an archive

Installation options:
      --non-interactive                  Do not prompt or wait for keypresses
      --no-update                        Do not self-update before installing
      --allow-npm-scripts                Allow NPM lifecycle scripts during install
      --yes                              Confirm destructive actions in automation
      --restore-packages                 Install packages during noninteractive restore
      --restore-ssh                      Restore SSH files during noninteractive restore

Examples:
  ashno --profile 2_extended --all
  ashno --profile 1_essentials --pkg --no-update
  ashno --backup --non-interactive
EOF
}

print_summary_report() {
    printf '\n'
    print_banner 'Operation Summary'
    printf '  %sSuccessful:%s %s\n' "$GREEN" "$NC" "${#SUCCESS_LIST[@]}"
    printf '  %sFailed:%s     %s\n' "$RED" "$NC" "${#FAILURE_LIST[@]}"
    printf '  %sSkipped:%s    %s\n' "$YELLOW" "$NC" "${#SKIPPED_LIST[@]}"
    if [ "${#FAILURE_LIST[@]}" -gt 0 ]; then
        printf '\n  Failed packages:\n'
        printf '    - %s\n' "${FAILURE_LIST[@]}"
    fi
    printf '\n'
}

main_menu() {
    clear 2>/dev/null || true
    print_banner 'Main Menu'
    printf '  Active profile: %s\n\n' "$SELECTED_PROFILE"

    if command -v gum >/dev/null 2>&1; then
        local choice
        choice=$(gum choose --cursor '➜ ' --cursor.foreground='212' \
            --selected.foreground='212' --selected.bold --header='Select an action:' \
            'Full Installation (PKG, NPM, PIP)' \
            'Install PKG Packages' \
            'Install NPM Packages' \
            'Install PIP Packages' \
            'Configure Installed Tools' \
            'Backup & Restore' \
            'Change Profile' \
            'Exit Ashno') || return 1
        case "$choice" in
            'Full Installation (PKG, NPM, PIP)') main_choice=1 ;;
            'Install PKG Packages') main_choice=2 ;;
            'Install NPM Packages') main_choice=3 ;;
            'Install PIP Packages') main_choice=4 ;;
            'Configure Installed Tools') main_choice=5 ;;
            'Backup & Restore') main_choice=6 ;;
            'Change Profile') main_choice=7 ;;
            'Exit Ashno'|'') main_choice=8 ;;
            *) main_choice=8 ;;
        esac
        return 0
    fi

    printf '  1) Full Installation (PKG, NPM, PIP)\n'
    printf '  2) Install PKG Packages\n'
    printf '  3) Install NPM Packages\n'
    printf '  4) Install PIP Packages\n'
    printf '  5) Configure Installed Tools\n'
    printf '  6) Backup & Restore\n'
    printf '  7) Change Profile\n'
    printf '  8) Exit Ashno\n'
    print_prompt
    IFS= read -r main_choice || return 1
}

_profile_paths() {
    find "$PROFILES_DIR" -mindepth 1 -maxdepth 1 -type d ! -xtype l -print 2>/dev/null | sort
}

profile_selection_menu() {
    local -a profiles=()
    mapfile -t profiles < <(_profile_paths)
    if [ "${#profiles[@]}" -eq 0 ]; then
        print_formatting error "No profiles found in $PROFILES_DIR."
        return 1
    fi

    print_banner 'Choose Installation Profile'
    if command -v gum >/dev/null 2>&1; then
        local -a labels=()
        local profile_path profile_name label
        for profile_path in "${profiles[@]}"; do
            profile_name=$(basename "$profile_path")
            case "$profile_name" in
                1_essentials) label='Essentials' ;;
                2_extended) label='Extended (Recommended)' ;;
                3_complete) label='Complete' ;;
                *) label="$profile_name" ;;
            esac
            labels+=("$label")
        done
        labels+=('Exit Ashno')
        local selected
        selected=$(gum choose --cursor '➜ ' --cursor.foreground='212' \
            --selected.foreground='212' --selected.bold "${labels[@]}") || return 1
        [ -z "$selected" ] || [ "$selected" = 'Exit Ashno' ] && return 1
        local i
        for i in "${!profiles[@]}"; do
            if [ "${labels[$i]}" = "$selected" ]; then
                SELECTED_PROFILE=$(basename "${profiles[$i]}")
                return 0
            fi
        done
        return 1
    fi

    printf '  Available profiles:\n'
    local i=1 profile_name
    for profile_path in "${profiles[@]}"; do
        profile_name=$(basename "$profile_path")
        printf '  %d) %s\n' "$i" "$profile_name"
        i=$((i + 1))
    done
    printf '  %d) Exit Ashno\n' "$i"
    print_prompt
    local choice
    IFS= read -r choice || return 1
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#profiles[@]}" ]; then
        SELECTED_PROFILE=$(basename "${profiles[$((choice - 1))]}")
        return 0
    fi
    return 1
}
