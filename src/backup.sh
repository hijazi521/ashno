#!/bin/bash
# ==============================================================================
# SECTION: BACKUP & RESTORE ENGINE
# ==============================================================================

# ─────────────────────────────────────────────────────────────────────
# Package Scanners — enumerate everything installed on this system
# ─────────────────────────────────────────────────────────────────────
_scan_pkg_packages() {
    if command -v apt-mark &>/dev/null; then
        apt-mark showmanual 2>/dev/null | sort
    elif command -v dpkg-query &>/dev/null; then
        dpkg-query -W -f='${Package}\n' 2>/dev/null | sort
    fi
}

_scan_npm_packages() {
    command -v npm &>/dev/null || return
    npm list -g --depth=0 --parseable 2>/dev/null | tail -n +2 | \
        while IFS= read -r line; do
            local pkg parent
            pkg=$(basename "$line")
            parent=$(basename "$(dirname "$line")")
            if [[ "$parent" == @* ]]; then
                echo "${parent}/${pkg}"
            else
                echo "$pkg"
            fi
        done | sort -u
}

_scan_pip_packages() {
    command -v pip &>/dev/null || return
    pip list --format=freeze 2>/dev/null | cut -d= -f1 | sort
}

# ==============================================================================
# BACKUP CREATION
# ==============================================================================
create_backup() {
    # ── Header ───────────────────────────────────────────────────────
    if command -v gum &>/dev/null; then
        echo ""
        gum style --border double --margin "0 1" --padding "0 3" \
            --border-foreground 116 --foreground 116 --bold \
            --align center "📦  Backup Your Environment"
        gum style --foreground 245 --italic --margin "0 2" \
            "Create a portable snapshot of your packages and dotfiles."
        echo ""
    else
        print_banner "📦  Backup Your Environment"
        echo -e "  Create a portable snapshot of your packages and dotfiles.\n"
    fi

    # ── Name Selection ───────────────────────────────────────────────
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local default_name="ashno_backup_${timestamp}"
    local backup_name=""

    if command -v gum &>/dev/null; then
        local name_choice
        name_choice=$(gum choose --cursor="➜ " --cursor.foreground="116" \
            --header="Choose a name for your backup:" \
            --header.foreground="250" \
            --selected.foreground="116" --selected.bold \
            "Default  ($default_name)" \
            "Custom name" \
            "── Cancel ──")

        case "$name_choice" in
            "Default"*) backup_name="$default_name" ;;
            "Custom name")
                backup_name=$(gum input --placeholder="my_setup" \
                    --header="  Backup name:" --width=40 \
                    --header.foreground="116" --cursor.foreground="116")
                backup_name=$(echo "$backup_name" | tr -cd 'a-zA-Z0-9_-')
                [ -z "$backup_name" ] && backup_name="$default_name"
                ;;
            *) print_formatting info "Backup cancelled."; return ;;
        esac
    else
        echo -e "  Choose a name for your backup:\n"
        echo -e "  ${CYAN}1)${NC} Default  (${default_name})"
        echo -e "  ${CYAN}2)${NC} Custom name"
        echo -e "  ${CYAN}3)${NC} Cancel"
        print_prompt; read -r choice
        case "$choice" in
            1) backup_name="$default_name" ;;
            2)
                read -r -p "  Enter backup name: " backup_name
                backup_name=$(echo "$backup_name" | tr -cd 'a-zA-Z0-9_-')
                [ -z "$backup_name" ] && backup_name="$default_name"
                ;;
            *) print_formatting info "Backup cancelled."; return ;;
        esac
    fi

    # ── Output Directory ─────────────────────────────────────────────
    local output_dir="$HOME"
    if [ -d "$HOME/storage/shared" ]; then
        mkdir -p "$HOME/storage/shared/Ashno" 2>/dev/null
        [ -d "$HOME/storage/shared/Ashno" ] && output_dir="$HOME/storage/shared/Ashno"
    fi

    # ── Scan Packages ────────────────────────────────────────────────
    echo ""
    if command -v gum &>/dev/null; then
        gum style --foreground 116 --bold --margin "0 1" "Scanning installed packages..."
        echo ""
    else
        echo -e "  ${BOLD}Scanning installed packages...${NC}\n"
    fi

    local pkg_list npm_list pip_list
    echo -en "  Scanning PKG... "
    pkg_list=$(_scan_pkg_packages)
    printf "\r\033[K"
    echo -en "  Scanning NPM... "
    npm_list=$(_scan_npm_packages)
    printf "\r\033[K"
    echo -en "  Scanning PIP... "
    pip_list=$(_scan_pip_packages)
    printf "\r\033[K"

    local pkg_count=0 npm_count=0 pip_count=0
    [ -n "$pkg_list" ] && pkg_count=$(echo "$pkg_list" | wc -l | tr -d ' ')
    [ -n "$npm_list" ] && npm_count=$(echo "$npm_list" | wc -l | tr -d ' ')
    [ -n "$pip_list" ] && pip_count=$(echo "$pip_list" | wc -l | tr -d ' ')
    local total_count=$((pkg_count + npm_count + pip_count))

    # Display counts
    if command -v gum &>/dev/null; then
        local b_pkg b_npm b_pip
        b_pkg=$(gum style --foreground 255 --background 39 --bold --padding "0 1" " PKG ")
        b_npm=$(gum style --foreground 255 --background 208 --bold --padding "0 1" " NPM ")
        b_pip=$(gum style --foreground 255 --background 82 --bold --padding "0 1" " PIP ")
        echo "$b_pkg $(gum style --foreground 39 "$pkg_count packages")"
        echo "$b_npm $(gum style --foreground 208 "$npm_count packages")"
        echo "$b_pip $(gum style --foreground 82 "$pip_count packages")"
        echo ""
        gum style --foreground 116 --bold --margin "0 1" "  $total_count total packages"
    else
        echo -e "  ${BLUE} PKG ${NC}  $pkg_count packages"
        echo -e "  ${YELLOW} NPM ${NC}  $npm_count packages"
        echo -e "  ${GREEN} PIP ${NC}  $pip_count packages"
        echo -e "\n  ${BOLD}$total_count total packages${NC}"
    fi
    echo ""

    # ── Staging Directory ────────────────────────────────────────────
    local staging_dir
    staging_dir=$(mktemp -d)
    mkdir -p "$staging_dir/profile" "$staging_dir/dotfiles"

    [ -n "$pkg_list" ] && echo "$pkg_list" > "$staging_dir/profile/pkg.list"
    [ -n "$npm_list" ] && echo "$npm_list" > "$staging_dir/profile/npm.list"
    [ -n "$pip_list" ] && echo "$pip_list" > "$staging_dir/profile/pip.list"

    # ── Collect Dotfiles ─────────────────────────────────────────────
    if command -v gum &>/dev/null; then
        gum style --foreground 116 --bold --margin "0 1" "Collecting dotfiles..."
        echo ""
    else
        echo -e "  ${BOLD}Collecting dotfiles...${NC}\n"
    fi

    local dotfile_count=0
    local dotfile_paths=(
        ".zshrc"
        ".bashrc"
        ".gitconfig"
        ".config/starship.toml"
        ".config/nvim"
        ".termux"
    )

    for rel_path in "${dotfile_paths[@]}"; do
        local src="$HOME/$rel_path"
        if [ -e "$src" ]; then
            local dest="$staging_dir/dotfiles/$rel_path"
            mkdir -p "$(dirname "$dest")"
            cp -r "$src" "$dest"
            print_formatting success "$rel_path"
            dotfile_count=$((dotfile_count + 1))
        fi
    done

    # ── Optional: SSH Keys ───────────────────────────────────────────
    local ssh_included=false
    if [ -d "$HOME/.ssh" ] && [ -f "$HOME/.ssh/id_ed25519" ]; then
        echo ""
        if _ask_update "Include SSH keys? (Contains your private key)"; then
            mkdir -p "$staging_dir/ssh"
            cp "$HOME/.ssh/id_ed25519" "$staging_dir/ssh/" 2>/dev/null
            cp "$HOME/.ssh/id_ed25519.pub" "$staging_dir/ssh/" 2>/dev/null
            [ -f "$HOME/.ssh/config" ] && cp "$HOME/.ssh/config" "$staging_dir/ssh/"
            [ -f "$HOME/.ssh/known_hosts" ] && cp "$HOME/.ssh/known_hosts" "$staging_dir/ssh/"
            ssh_included=true
            print_formatting success ".ssh/ included"
            dotfile_count=$((dotfile_count + 1))
        else
            print_formatting info ".ssh/ skipped"
        fi
    fi

    # ── Manifest ─────────────────────────────────────────────────────
    cat > "$staging_dir/manifest.txt" << MANIFEST_EOF
ashno_version=1.10.0
date=$(date '+%Y-%m-%d %H:%M:%S')
pkg_count=$pkg_count
npm_count=$npm_count
pip_count=$pip_count
total_count=$total_count
dotfile_count=$dotfile_count
ssh_included=$ssh_included
MANIFEST_EOF

    # ── Create Archive ───────────────────────────────────────────────
    echo ""
    local output_file="$output_dir/${backup_name}.tar.gz"
    echo -en "  Creating archive... "
    (cd "$staging_dir" && tar czf "$output_file" .) &>/dev/null &
    spinner $!; wait $!
    local tar_exit=$?
    printf "\r\033[K"

    rm -rf "$staging_dir"

    if [ "$tar_exit" -ne 0 ] || [ ! -f "$output_file" ]; then
        print_formatting error "Failed to create backup archive."
        return 1
    fi

    local file_size
    file_size=$(du -h "$output_file" | cut -f1)

    # ── Success Summary ──────────────────────────────────────────────
    echo ""
    if command -v gum &>/dev/null; then
        local header
        header=$(gum style --foreground 116 --bold --align center "━━━  Backup Complete  ━━━")

        local body=""
        body+="$(gum style --foreground 250 "  📄  ${output_file/#$HOME/'~'}")\n"
        body+="$(gum style --foreground 250 "  💾  $file_size")\n"
        body+="$(gum style --foreground 250 "  📦  $total_count packages  ($pkg_count pkg · $npm_count npm · $pip_count pip)")\n"
        body+="$(gum style --foreground 250 "  📂  $dotfile_count dotfile groups included")\n"

        printf "%s\n\n%b" "$header" "$body" \
            | gum style --border rounded --border-foreground 116 --padding "1 2" --margin "0 1"
    else
        echo -e " ${BOLD}━━━  Backup Complete  ━━━${NC}\n"
        echo -e "  File:     ${output_file/#$HOME/'~'}"
        echo -e "  Size:     $file_size"
        echo -e "  Packages: $total_count ($pkg_count pkg, $npm_count npm, $pip_count pip)"
        echo -e "  Dotfiles: $dotfile_count groups included"
    fi
    echo ""

    if command -v gum &>/dev/null; then
        gum style --foreground 245 --italic --margin "0 2" "Press any key to continue..."
    else
        echo -e "  Press any key to continue..."
    fi
    read -n 1 -s -r
}

# ==============================================================================
# RESTORE FROM BACKUP
# ==============================================================================
restore_backup() {
    local archive="$1"

    if [ ! -f "$archive" ]; then
        print_formatting error "File not found: $archive"
        return 1
    fi

    # ── Header ───────────────────────────────────────────────────────
    if command -v gum &>/dev/null; then
        echo ""
        gum style --border double --margin "0 1" --padding "0 3" \
            --border-foreground 116 --foreground 116 --bold \
            --align center "📦  Restore from Backup"
        echo ""
    else
        print_banner "📦  Restore from Backup"
        echo ""
    fi

    # ── Extract ──────────────────────────────────────────────────────
    local extract_dir
    extract_dir=$(mktemp -d)
    echo -en "  Extracting archive... "
    (tar xzf "$archive" -C "$extract_dir") &>/dev/null &
    spinner $!; wait $!
    printf "\r\033[K"
    print_formatting success "Archive extracted."

    if [ ! -f "$extract_dir/manifest.txt" ]; then
        print_formatting error "Invalid backup — manifest.txt not found."
        rm -rf "$extract_dir"
        return 1
    fi

    # ── Read Manifest ────────────────────────────────────────────────
    local m_version m_date m_pkg m_npm m_pip m_total m_dotfiles m_ssh
    m_version=$(grep '^ashno_version=' "$extract_dir/manifest.txt" | cut -d= -f2)
    m_date=$(grep '^date=' "$extract_dir/manifest.txt" | cut -d= -f2-)
    m_pkg=$(grep '^pkg_count=' "$extract_dir/manifest.txt" | cut -d= -f2)
    m_npm=$(grep '^npm_count=' "$extract_dir/manifest.txt" | cut -d= -f2)
    m_pip=$(grep '^pip_count=' "$extract_dir/manifest.txt" | cut -d= -f2)
    m_total=$(grep '^total_count=' "$extract_dir/manifest.txt" | cut -d= -f2)
    m_dotfiles=$(grep '^dotfile_count=' "$extract_dir/manifest.txt" | cut -d= -f2)
    m_ssh=$(grep '^ssh_included=' "$extract_dir/manifest.txt" | cut -d= -f2)

    # ── Show Backup Details ──────────────────────────────────────────
    echo ""
    if command -v gum &>/dev/null; then
        local info=""
        info+="$(gum style --foreground 250 "  Created:    $m_date")\n"
        info+="$(gum style --foreground 250 "  Version:    Ashno $m_version")\n"
        info+="$(gum style --foreground 250 "  Packages:   $m_total  ($m_pkg pkg · $m_npm npm · $m_pip pip)")\n"
        info+="$(gum style --foreground 250 "  Dotfiles:   $m_dotfiles groups")\n"
        [ "$m_ssh" = "true" ] && info+="$(gum style --foreground 250 "  SSH Keys:   included")\n"

        printf "%b" "$info" \
            | gum style --border rounded --border-foreground 116 --padding "1 2" --margin "0 1"
    else
        echo -e "  Created:   $m_date"
        echo -e "  Version:   Ashno $m_version"
        echo -e "  Packages:  $m_total ($m_pkg pkg, $m_npm npm, $m_pip pip)"
        echo -e "  Dotfiles:  $m_dotfiles groups"
        [ "$m_ssh" = "true" ] && echo -e "  SSH Keys:  included"
    fi
    echo ""

    if ! _ask_update "Proceed with restore?"; then
        print_formatting info "Restore cancelled."
        rm -rf "$extract_dir"
        return
    fi

    # ── Restore Packages ─────────────────────────────────────────────
    if [ -d "$extract_dir/profile" ]; then
        echo ""
        if _ask_update "Install packages from backup? ($m_total packages)"; then
            local restore_profile_dir="$PROFILES_DIR/restored"
            rm -rf "$restore_profile_dir"
            mkdir -p "$restore_profile_dir"
            cp "$extract_dir/profile/"*.list "$restore_profile_dir/" 2>/dev/null

            SELECTED_PROFILE="restored"
            SUCCESS_LIST=(); FAILURE_LIST=(); SKIPPED_LIST=()
            pre_flight_checks
            update_termux
            [ -f "$restore_profile_dir/pkg.list" ] && install_pkg
            [ -f "$restore_profile_dir/npm.list" ] && install_npm
            [ -f "$restore_profile_dir/pip.list" ] && install_pip
            print_summary_report
        fi
    fi

    # ── Restore Dotfiles ─────────────────────────────────────────────
    if [ -d "$extract_dir/dotfiles" ]; then
        echo ""
        if _ask_update "Apply dotfiles from backup?"; then
            if command -v gum &>/dev/null; then
                gum style --foreground 116 --bold --margin "0 1" "Restoring dotfiles..."
                echo ""
            else
                echo -e "\n  ${BOLD}Restoring dotfiles...${NC}\n"
            fi

            local dotfile_restore_paths=(
                ".zshrc"
                ".bashrc"
                ".gitconfig"
                ".config/starship.toml"
                ".config/nvim"
                ".termux"
            )

            for rel_path in "${dotfile_restore_paths[@]}"; do
                local src="$extract_dir/dotfiles/$rel_path"
                if [ -e "$src" ]; then
                    local dest="$HOME/$rel_path"
                    mkdir -p "$(dirname "$dest")"
                    [ -e "$dest" ] && _backup_existing "$dest"
                    cp -r "$src" "$dest"
                    print_formatting success "$rel_path"
                fi
            done
        fi
    fi

    # ── Restore SSH Keys ─────────────────────────────────────────────
    if [ "$m_ssh" = "true" ] && [ -d "$extract_dir/ssh" ]; then
        echo ""
        if _ask_update "Restore SSH keys from backup?"; then
            mkdir -p "$HOME/.ssh"
            chmod 700 "$HOME/.ssh"
            for keyfile in "$extract_dir/ssh/"*; do
                [ ! -f "$keyfile" ] && continue
                local kname
                kname=$(basename "$keyfile")
                [ -f "$HOME/.ssh/$kname" ] && _backup_existing "$HOME/.ssh/$kname"
                cp "$keyfile" "$HOME/.ssh/$kname"
            done
            chmod 600 "$HOME/.ssh/id_"* 2>/dev/null
            chmod 644 "$HOME/.ssh/"*.pub 2>/dev/null
            print_formatting success "SSH keys restored."
        fi
    fi

    # ── Cleanup & Summary ────────────────────────────────────────────
    rm -rf "$extract_dir"

    echo ""
    if command -v gum &>/dev/null; then
        gum style --border rounded --border-foreground 116 --padding "1 2" --margin "0 1" \
            --foreground 116 --bold --align center "Restore Complete ✔"
    else
        echo -e "\n  ${GREEN}${BOLD}Restore Complete.${NC}"
    fi
    echo ""

    if command -v gum &>/dev/null; then
        gum style --foreground 245 --italic --margin "0 2" "Press any key to continue..."
    else
        echo -e "  Press any key to continue..."
    fi
    read -n 1 -s -r
}

# ==============================================================================
# BACKUP MENU — Accessible from main menu
# ==============================================================================
backup_menu() {
    if command -v gum &>/dev/null; then
        echo ""
        gum style --border double --margin "0 1" --padding "0 3" \
            --border-foreground 116 --foreground 116 --bold \
            --align center "📦  Backup & Restore"
        gum style --foreground 245 --italic --margin "0 2" \
            "Manage your Termux environment snapshots."
        echo ""

        local action
        action=$(gum choose --cursor="➜ " --cursor.foreground="116" \
            --header="Select an action:" \
            --header.foreground="250" \
            --selected.foreground="116" --selected.bold \
            "Create New Backup" \
            "Restore from Backup" \
            "── Back ──")

        case "$action" in
            "Create New Backup")    create_backup ;;
            "Restore from Backup")  _restore_picker ;;
            *) return ;;
        esac
    else
        print_banner "📦  Backup & Restore"
        echo -e "  Manage your Termux environment snapshots.\n"
        echo -e "  ${CYAN}1)${NC} Create New Backup"
        echo -e "  ${CYAN}2)${NC} Restore from Backup"
        echo -e "  ${CYAN}3)${NC} Back"
        print_prompt; read -r choice
        case "$choice" in
            1) create_backup ;;
            2) _restore_picker ;;
            *) return ;;
        esac
    fi
}

# ─────────────────────────────────────────────────────────────────────
# Restore Picker — find and select backup files
# ─────────────────────────────────────────────────────────────────────
_restore_picker() {
    local found=()
    for dir in "$HOME/storage/shared/Ashno" "$HOME/storage/shared/Download" "$HOME"; do
        if [ -d "$dir" ]; then
            while IFS= read -r f; do
                [ -n "$f" ] && found+=("$f")
            done < <(find "$dir" -maxdepth 1 -name "ashno_backup_*.tar.gz" -type f 2>/dev/null | sort -r)
        fi
    done

    if [ ${#found[@]} -eq 0 ]; then
        echo ""
        print_formatting warn "No backup files found in common locations."
        print_formatting info "Use 'ashno --restore <path>' to restore from a specific file."
        echo ""
        if command -v gum &>/dev/null; then
            gum style --foreground 245 --italic --margin "0 2" "Press any key to continue..."
        else
            echo -e "  Press any key to continue..."
        fi
        read -n 1 -s -r
        return
    fi

    local labels=()
    for f in "${found[@]}"; do
        local name fsize
        name=$(basename "$f")
        fsize=$(du -h "$f" | cut -f1)
        labels+=("$name  ($fsize)")
    done
    labels+=("── Cancel ──")

    echo ""
    if command -v gum &>/dev/null; then
        local pick
        pick=$(gum choose --cursor="➜ " --cursor.foreground="116" \
            --header="Select a backup to restore:" \
            --header.foreground="250" \
            --selected.foreground="116" --selected.bold \
            "${labels[@]}")

        [ -z "$pick" ] || [ "$pick" = "── Cancel ──" ] && return

        for i in "${!labels[@]}"; do
            if [ "${labels[$i]}" = "$pick" ]; then
                restore_backup "${found[$i]}"
                return
            fi
        done
    else
        echo -e "  Found backups:\n"
        local i=1
        for label in "${labels[@]}"; do
            echo -e "  ${CYAN}${i})${NC} $label"
            i=$((i + 1))
        done
        print_prompt; read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#found[@]} ]; then
            restore_backup "${found[$((choice-1))]}"
        fi
    fi
}
