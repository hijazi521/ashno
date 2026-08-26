#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2317
# ==============================================================================
# SECTION: BACKUP & RESTORE ENGINE
# ==============================================================================

_backup_existing() {
    local path="$1"
    [ -e "$path" ] || [ -L "$path" ] || return 0
    if ! mkdir -p "$ASHNO_BACKUP_DIR" || ! chmod 700 "$ASHNO_BACKUP_DIR"; then
        print_formatting error "Cannot create the private backup directory."
        return 1
    fi

    local name timestamp destination suffix=0
    name=$(basename -- "$path")
    timestamp=$(date +%Y%m%d_%H%M%S)
    destination="$ASHNO_BACKUP_DIR/${name}.${timestamp}"
    while [ -e "$destination" ] || [ -L "$destination" ]; do
        suffix=$((suffix + 1))
        destination="$ASHNO_BACKUP_DIR/${name}.${timestamp}.${suffix}"
    done

    if ! cp -a -- "$path" "$destination"; then
        print_formatting error "Could not back up $path."
        return 1
    fi
    chmod -R go-rwx -- "$destination" 2>/dev/null || true
    print_formatting info "Backed up ${path/#$HOME/~} → ${destination/#$HOME/~}"
    return 0
}

_scan_pkg_packages() {
    if command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Package}=${Version}\n' 2>/dev/null | sort
    elif command -v apt-mark >/dev/null 2>&1; then
        apt-mark showmanual 2>/dev/null | sort
    fi
}

_scan_npm_packages() {
    command -v npm >/dev/null 2>&1 || return 0
    if command -v jq >/dev/null 2>&1; then
        npm list -g --depth=0 --json 2>/dev/null \
            | jq -r '.dependencies // {} | to_entries[] | select(.value.version != null) | "\(.key)@\(.value.version)"' \
            | sort -u
    else
        local npm_root package_json
        npm_root=$(npm root -g 2>/dev/null) || return 0
        while IFS= read -r -d '' package_json; do
            sed -nE 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/name=\1/p; s/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/version=\1/p' "$package_json" \
                | awk -F= 'BEGIN{name="";version=""} $1=="name"{name=$2} $1=="version"{version=$2} END{if(name!=""&&version!="")print name "@" version}'
        done < <(find "$npm_root" -mindepth 2 -maxdepth 3 -type f -name package.json -print0 2>/dev/null) | sort -u
    fi
}

_scan_pip_packages() {
    command -v pip >/dev/null 2>&1 || return 0
    pip list --format=freeze 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -f
}

_safe_backup_name() {
    local name="$1"
    name=$(printf '%s' "$name" | tr -cd 'A-Za-z0-9_-')
    [ -n "$name" ] || return 1
    printf '%s\n' "$name"
}

_backup_output_directory() {
    if ! mkdir -p "$ASHNO_BACKUP_DIR" || ! chmod 700 "$ASHNO_BACKUP_DIR"; then
        print_formatting error "Cannot create private backup storage: $ASHNO_BACKUP_DIR"
        return 1
    fi
    printf '%s\n' "$ASHNO_BACKUP_DIR"
}

create_backup() {
    local output_dir
    output_dir=$(_backup_output_directory) || return 1

    print_banner 'Backup Your Environment'
    local timestamp default_name backup_name
    timestamp=$(date +%Y%m%d_%H%M%S)
    default_name="ashno_backup_${timestamp}"
    backup_name="$default_name"

    if [ "$NONINTERACTIVE" = false ]; then
        if command -v gum >/dev/null 2>&1; then
            local choice
            choice=$(gum choose --cursor='➜ ' --header='Choose a name for your backup:' \
                "Default ($default_name)" 'Custom name' 'Cancel') || return 1
            case "$choice" in
                'Default '*) backup_name="$default_name" ;;
                'Custom name')
                    backup_name=$(gum input --placeholder='my_setup' --header='Backup name:' --width=40) || return 1
                    backup_name=$(_safe_backup_name "$backup_name") || backup_name="$default_name"
                    ;;
                *) print_formatting info 'Backup cancelled.'; return 0 ;;
            esac
        else
            printf 'Backup name [%s]: ' "$default_name"
            local choice
            IFS= read -r choice || return 1
            if [ -n "$choice" ]; then
                backup_name=$(_safe_backup_name "$choice") || backup_name="$default_name"
            fi
        fi
    fi

    local staging_dir
    staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/ashno-backup.XXXXXX") || {
        print_formatting error 'Cannot create a private staging directory.'
        return 1
    }
    chmod 700 "$staging_dir"
    local cleanup_needed=true
    cleanup_backup() {
        [ "$cleanup_needed" = true ] && rm -rf -- "$staging_dir"
    }
    trap cleanup_backup RETURN

    mkdir -p "$staging_dir/profile" "$staging_dir/dotfiles" || return 1

    local pkg_list npm_list pip_list
    pkg_list=$(_scan_pkg_packages)
    npm_list=$(_scan_npm_packages)
    pip_list=$(_scan_pip_packages)
    [ -n "$pkg_list" ] && printf '%s\n' "$pkg_list" > "$staging_dir/profile/pkg.list"
    [ -n "$npm_list" ] && printf '%s\n' "$npm_list" > "$staging_dir/profile/npm.list"
    [ -n "$pip_list" ] && printf '%s\n' "$pip_list" > "$staging_dir/profile/pip.list"

    local pkg_count=0 npm_count=0 pip_count=0
    [ -n "$pkg_list" ] && pkg_count=$(printf '%s\n' "$pkg_list" | wc -l | tr -d ' ')
    [ -n "$npm_list" ] && npm_count=$(printf '%s\n' "$npm_list" | wc -l | tr -d ' ')
    [ -n "$pip_list" ] && pip_count=$(printf '%s\n' "$pip_list" | wc -l | tr -d ' ')
    local total_count=$((pkg_count + npm_count + pip_count))

    local dotfile_count=0 rel_path source destination
    local -a dotfile_paths=(.zshrc .bashrc .gitconfig .config/starship.toml .config/nvim .termux)
    for rel_path in "${dotfile_paths[@]}"; do
        source="$HOME/$rel_path"
        [ -e "$source" ] || [ -L "$source" ] || continue
        destination="$staging_dir/dotfiles/$rel_path"
        mkdir -p -- "$(dirname -- "$destination")" || return 1
        cp -a -- "$source" "$destination" || {
            print_formatting error "Could not copy $rel_path into the backup."
            return 1
        }
        dotfile_count=$((dotfile_count + 1))
    done

    local ssh_included=false
    if [ -f "$HOME/.ssh/id_ed25519" ] && [ "$NONINTERACTIVE" = false ]; then
        local include_ssh=false
        if command -v gum >/dev/null 2>&1; then
            gum confirm 'Include SSH private keys? The archive will remain in private Termux storage.' && include_ssh=true
        else
            printf 'Include SSH private keys in this archive? [y/N]: '
            local choice
            IFS= read -r choice || choice=''
            case "$choice" in [yY]|[yY][eE][sS]) include_ssh=true ;; esac
        fi
        if [ "$include_ssh" = true ]; then
            mkdir -p "$staging_dir/ssh"
            for rel_path in id_ed25519 id_ed25519.pub config known_hosts; do
                if [ -f "$HOME/.ssh/$rel_path" ]; then
                    cp -a -- "$HOME/.ssh/$rel_path" "$staging_dir/ssh/" || {
                        print_formatting error "Could not include SSH file: $rel_path"
                        return 1
                    }
                fi
            done
            chmod 700 "$staging_dir/ssh"
            find "$staging_dir/ssh" -type f -name 'id_ed25519' -exec chmod 600 {} +
            find "$staging_dir/ssh" -type f ! -name 'id_ed25519' -exec chmod 644 {} +
            ssh_included=true
            print_formatting warn 'Private SSH material is included; keep this archive private.'
        fi
    fi

    cat > "$staging_dir/manifest.txt" <<EOF
schema=2
ashno_version=$ASHNO_VERSION
date=$(date '+%Y-%m-%d %H:%M:%S')
pkg_count=$pkg_count
npm_count=$npm_count
pip_count=$pip_count
total_count=$total_count
dotfile_count=$dotfile_count
ssh_included=$ssh_included
EOF
    chmod 600 "$staging_dir/manifest.txt"

    local output_file temp_output
    temp_output=$(mktemp "$output_dir/.${backup_name}.XXXXXX") || return 1
    output_file="$output_dir/${backup_name}.tar.gz"
    if [ -e "$output_file" ] || [ -L "$output_file" ]; then
        if [ "$NONINTERACTIVE" = true ]; then
            local suffix=1 candidate
            candidate="$output_dir/${backup_name}_$suffix.tar.gz"
            while [ -e "$candidate" ] || [ -L "$candidate" ]; do
                suffix=$((suffix + 1))
                candidate="$output_dir/${backup_name}_$suffix.tar.gz"
            done
            output_file="$candidate"
        elif ! _ask_update "Backup exists. Replace it?"; then
            rm -f -- "$temp_output"
            print_formatting info 'Backup cancelled.'
            return 0
        fi
    fi

    if ! (umask 077; tar -czf "$temp_output" -C "$staging_dir" .); then
        rm -f -- "$temp_output"
        print_formatting error 'Failed to create the backup archive.'
        return 1
    fi
    if ! mv -f -- "$temp_output" "$output_file" || ! chmod 600 "$output_file"; then
        rm -f -- "$temp_output" "$output_file"
        print_formatting error 'Failed to finalize the backup archive.'
        return 1
    fi

    cleanup_needed=false
    rm -rf -- "$staging_dir"
    trap - RETURN
    print_formatting success "Backup created at ${output_file/#$HOME/~}"
    print_formatting info "Captured $total_count package entries and $dotfile_count configuration groups."
    wait_for_key
    return 0
}

_manifest_value() {
    local manifest="$1" key="$2"
    awk -F= -v wanted="$key" '$1 == wanted {sub(/^[^=]*=/, ""); print; exit}' "$manifest"
}

_validate_manifest() {
    local manifest="$1"
    [ -f "$manifest" ] || return 1
    local schema version value key
    schema=$(_manifest_value "$manifest" schema)
    version=$(_manifest_value "$manifest" ashno_version)
    [ "$schema" = 2 ] || return 1
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    for key in pkg_count npm_count pip_count total_count dotfile_count; do
        value=$(_manifest_value "$manifest" "$key")
        [[ "$value" =~ ^[0-9]+$ ]] || return 1
    done
    value=$(_manifest_value "$manifest" ssh_included)
    [ "$value" = true ] || [ "$value" = false ] || return 1
}

_validate_member_name() {
    local member="$1"
    case "$member" in
        .|./|./manifest.txt|./profile|./profile/|./profile/*.list|./dotfiles|./dotfiles/|./dotfiles/.zshrc|./dotfiles/.bashrc|./dotfiles/.gitconfig|./dotfiles/.config|./dotfiles/.config/|./dotfiles/.config/starship.toml|./dotfiles/.config/nvim|./dotfiles/.config/nvim/|./dotfiles/.config/nvim/*|./dotfiles/.termux|./dotfiles/.termux/|./dotfiles/.termux/*|./ssh|./ssh/|./ssh/id_ed25519|./ssh/id_ed25519.pub|./ssh/config|./ssh/known_hosts) ;;
        *) return 1 ;;
    esac
    case "$member" in
        /*|*../*|*//*) return 1 ;;
    esac
    return 0
}

_validate_archive() {
    local archive="$1"
    [ -f "$archive" ] || return 1
    local archive_size member_count expanded_size member
    archive_size=$(stat -c '%s' "$archive" 2>/dev/null) || return 1
    [ "$archive_size" -le "$MAX_BACKUP_ARCHIVE_BYTES" ] || return 1

    local listing long_listing
    listing=$(tar -tzf "$archive" 2>/dev/null) || return 1
    long_listing=$(tar -tvzf "$archive" 2>/dev/null) || return 1
    member_count=$(printf '%s\n' "$listing" | sed '/^$/d' | wc -l | tr -d ' ')
    [ "$member_count" -le "$MAX_BACKUP_MEMBERS" ] || return 1

    declare -A seen_members=()
    while IFS= read -r member; do
        [ -z "$member" ] && continue
        _validate_member_name "$member" || return 1
        [ -z "${seen_members[$member]+x}" ] || return 1
        seen_members[$member]=1
    done <<< "$listing"

    local entry_type
    while IFS= read -r member; do
        [ -z "$member" ] && continue
        entry_type="${member:0:1}"
        case "$entry_type" in
            d|-) ;;
            *) return 1 ;;
        esac
    done <<< "$long_listing"

    expanded_size=$(awk '{if ($3 ~ /^[0-9]+$/) sum += $3} END{print sum + 0}' <<< "$long_listing")
    [[ "$expanded_size" =~ ^[0-9]+$ ]] || return 1
    [ "$expanded_size" -le "$MAX_BACKUP_EXPANDED_BYTES" ] || return 1
}

_restore_file_atomic() {
    local source="$1" destination="$2" mode="$3"
    [ -f "$source" ] || return 1
    local parent temp_file
    parent=$(dirname -- "$destination")
    mkdir -p -- "$parent" || return 1
    temp_file=$(mktemp "$parent/.ashno-restore.XXXXXX") || return 1
    if ! cp -a -- "$source" "$temp_file" || ! chmod "$mode" "$temp_file"; then
        rm -f -- "$temp_file"
        return 1
    fi
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        _backup_existing "$destination" || { rm -f -- "$temp_file"; return 1; }
    fi
    mv -f -- "$temp_file" "$destination"
}

_restore_tree_atomic() {
    local source="$1" destination="$2"
    [ -d "$source" ] || return 1
    if find "$source" \( -type l -o -type b -o -type c -o -type p \) -print -quit | grep -q .; then
        return 1
    fi
    local parent temp_dir
    parent=$(dirname -- "$destination")
    mkdir -p -- "$parent" || return 1
    temp_dir=$(mktemp -d "$parent/.ashno-restore.XXXXXX") || return 1
    if ! cp -a -- "$source/." "$temp_dir/"; then
        rm -rf -- "$temp_dir"
        return 1
    fi
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        _backup_existing "$destination" || { rm -rf -- "$temp_dir"; return 1; }
        rm -rf -- "$destination" || { rm -rf -- "$temp_dir"; return 1; }
    fi
    mv -- "$temp_dir" "$destination"
}

restore_backup() {
    local archive="$1"
    if ! _validate_archive "$archive"; then
        print_formatting error 'Archive failed validation or exceeds safety limits.'
        return 1
    fi

    local extract_dir
    extract_dir=$(mktemp -d "${TMPDIR:-/tmp}/ashno-restore.XXXXXX") || return 1
    chmod 700 "$extract_dir"
    trap 'rm -rf -- "$extract_dir"' RETURN
    if ! tar --no-same-owner --no-same-permissions -xzf "$archive" -C "$extract_dir"; then
        print_formatting error 'Archive extraction failed.'
        return 1
    fi
    if ! _validate_manifest "$extract_dir/manifest.txt"; then
        print_formatting error 'Invalid Ashno backup manifest.'
        return 1
    fi

    local m_version m_total m_ssh
    m_version=$(_manifest_value "$extract_dir/manifest.txt" ashno_version)
    m_total=$(_manifest_value "$extract_dir/manifest.txt" total_count)
    m_ssh=$(_manifest_value "$extract_dir/manifest.txt" ssh_included)
    print_banner 'Restore from Backup'
    print_formatting info "Ashno $m_version archive with $m_total package entries."

    if [ "$NONINTERACTIVE" = true ]; then
        [ "$CONFIRM_DESTRUCTIVE" = true ] || { print_formatting error 'Noninteractive restore requires --yes.'; return 2; }
    elif ! _ask_update 'Proceed with restore?'; then
        print_formatting info 'Restore cancelled.'
        return 0
    fi

    local overall_rc=0
    if [ -d "$extract_dir/profile" ] && { { [ "$NONINTERACTIVE" = true ] && [ "$RESTORE_PACKAGES" = true ]; } || { [ "$NONINTERACTIVE" = false ] && _ask_update "Install packages from backup? ($m_total entries)"; }; }; then
        PROFILE_PATH_OVERRIDE="$extract_dir/profile"
        SELECTED_PROFILE=restored
        SUCCESS_LIST=(); FAILURE_LIST=(); SKIPPED_LIST=()
        if pre_flight_checks --all && update_termux; then
            [ -f "$extract_dir/profile/pkg.list" ] && install_pkg || overall_rc=1
            [ -f "$extract_dir/profile/npm.list" ] && install_npm || overall_rc=1
            [ -f "$extract_dir/profile/pip.list" ] && install_pip || overall_rc=1
        else
            overall_rc=1
        fi
        [ "${#FAILURE_LIST[@]}" -gt 0 ] && overall_rc=1
        print_summary_report
        PROFILE_PATH_OVERRIDE=""
    fi

    if [ -d "$extract_dir/dotfiles" ] && { [ "$NONINTERACTIVE" = true ] || _ask_update 'Apply dotfiles from backup?'; }; then
        local -a dotfile_restore_paths=(.zshrc .bashrc .gitconfig .config/starship.toml .config/nvim .termux)
        local rel_path source destination
        for rel_path in "${dotfile_restore_paths[@]}"; do
            source="$extract_dir/dotfiles/$rel_path"
            destination="$HOME/$rel_path"
            [ -e "$source" ] || [ -L "$source" ] || continue
            if [ -d "$source" ]; then
                _restore_tree_atomic "$source" "$destination" || overall_rc=1
            else
                _restore_file_atomic "$source" "$destination" 600 || overall_rc=1
            fi
        done
    fi

    if [ "$m_ssh" = true ] && [ -d "$extract_dir/ssh" ]; then
        if [ "$NONINTERACTIVE" = true ] && [ "$RESTORE_SSH" = false ]; then
            print_formatting warn 'SSH private keys were not restored; pass --restore-ssh explicitly to opt in.'
        elif [ "$NONINTERACTIVE" = true ] || _ask_update 'Restore SSH keys from this private backup?'; then
            local key_name mode
            for key_name in id_ed25519 id_ed25519.pub config known_hosts; do
                source="$extract_dir/ssh/$key_name"
                [ -f "$source" ] || continue
                case "$key_name" in
                    id_ed25519) mode=600 ;;
                    config) mode=600 ;;
                    *) mode=644 ;;
                esac
                _restore_file_atomic "$source" "$HOME/.ssh/$key_name" "$mode" || overall_rc=1
            done
            chmod 700 "$HOME/.ssh" 2>/dev/null || true
        fi
    fi

    trap - RETURN
    rm -rf -- "$extract_dir"
    if [ "$overall_rc" -eq 0 ]; then
        print_formatting success 'Restore completed successfully.'
    else
        print_formatting error 'Restore completed with one or more failures.'
    fi
    wait_for_key
    return "$overall_rc"
}

_restore_picker() {
    local -a found=()
    local dir file
    for dir in "$ASHNO_BACKUP_DIR" "$HOME/storage/shared/Ashno" "$HOME/storage/shared/Download"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' file; do
            found+=("$file")
        done < <(find "$dir" -maxdepth 1 -type f -name '*.tar.gz' -print0 2>/dev/null | sort -z -r)
    done
    [ "${#found[@]}" -gt 0 ] || { print_formatting warn 'No backup archives found.'; return 0; }

    local selected
    if command -v gum >/dev/null 2>&1; then
        local -a labels=()
        for file in "${found[@]}"; do labels+=("$(basename -- "$file")"); done
        labels+=(Cancel)
        selected=$(gum choose --cursor='➜ ' --header='Select a backup to restore:' "${labels[@]}") || return 1
        [ "$selected" = Cancel ] || [ -z "$selected" ] && return 0
        local i
        for i in "${!found[@]}"; do
            [ "${labels[$i]}" = "$selected" ] && restore_backup "${found[$i]}" && return $?
        done
    else
        local i=1
        for file in "${found[@]}"; do printf '  %d) %s\n' "$i" "$(basename -- "$file")"; i=$((i + 1)); done
        print_prompt
        IFS= read -r selected || return 1
        [[ "$selected" =~ ^[0-9]+$ ]] || return 1
        [ "$selected" -ge 1 ] && [ "$selected" -le "${#found[@]}" ] || return 1
        restore_backup "${found[$((selected - 1))]}"
    fi
}

backup_menu() {
    print_banner 'Backup & Restore'
    if command -v gum >/dev/null 2>&1; then
        local action
        action=$(gum choose --cursor='➜ ' 'Create New Backup' 'Restore from Backup' 'Back') || return 1
        case "$action" in
            'Create New Backup') create_backup ;;
            'Restore from Backup') _restore_picker ;;
            *) return 0 ;;
        esac
    else
        printf '  1) Create New Backup\n  2) Restore from Backup\n  3) Back\n'
        print_prompt
        local choice
        IFS= read -r choice || return 1
        case "$choice" in
            1) create_backup ;;
            2) _restore_picker ;;
            *) return 0 ;;
        esac
    fi
}
