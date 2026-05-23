#!/bin/bash
# ==============================================================================
# SECTION: MENUS & REPORTING
# ==============================================================================

print_help_menu() {
    clear; print_banner "Ashno Help Manual"
    if command -v gum &>/dev/null; then
        gum format "## Usage
\`ashno [COMMANDS]\`
Running without commands launches the interactive menu.

## Installation Commands
| Flag | Description |
|---|---|
| \`--profile <NAME>\` | Selects a profile by its directory name |
| \`--all / --pkg / --npm / --pip\` | The action to perform |

## Utility Commands
| Flag | Description |
|---|---|
| \`-c, --configure\` | Configure installed tools (ZSH, Git, Neovim, etc.) |
| \`-b, --backup\` | Create a backup of your environment |
| \`--restore <FILE>\` | Restore from a backup archive |
| \`-u, --update\` | Checks for and applies updates |
| \`-h, --help\` | Display this help manual and exit |

## Examples
\`ashno --profile 2_extended --all\`
\`ashno --configure\`
\`ashno --backup\`
\`ashno --restore ~/backup.tar.gz\`" | gum style --border rounded --border-foreground 212 --padding "1 2" --margin "0 1"
    else
        echo -e "A professional, self-updating tool that installs and configures packages from profiles."
        echo; echo -e "${BOLD}${YELLOW}USAGE:${NC}"; echo -e "  ashno ${PURPLE}[COMMANDS]${NC}"; echo -e "    Running without commands launches the interactive menu."
        echo; echo -e "${BOLD}${YELLOW}INSTALLATION COMMANDS:${NC}"
        printf "  ${PURPLE}%-20s${NC} %s\n" "--profile <NAME>" "Required. Selects a profile by its directory name."
        printf "  ${PURPLE}%-20s${NC} %s\n" "--all | --pkg | ..." "Required. The action to perform (install all, pkg, etc.)."
        echo; echo -e "${BOLD}${YELLOW}UTILITY COMMANDS:${NC}"
        printf "  ${PURPLE}%-20s${NC} %s\n" "-c, --configure" "Configure installed tools (ZSH, Git, Neovim, etc.)."
        printf "  ${PURPLE}%-20s${NC} %s\n" "-b, --backup" "Create a backup of your environment."
        printf "  ${PURPLE}%-20s${NC} %s\n" "--restore <FILE>" "Restore from a backup archive."
        printf "  ${PURPLE}%-20s${NC} %s\n" "-u, --update" "Checks for and applies updates to Ashno itself."
        printf "  ${PURPLE}%-20s${NC} %s\n" "-h, --help" "Display this help manual and exit."
        echo; echo -e "${BOLD}${YELLOW}EXAMPLES:${NC}"; echo -e "  ashno --profile 2_extended --all"; echo -e "  ashno --backup"; echo
    fi
}

print_summary_report() {
    echo ""
    
    if command -v gum &>/dev/null; then
        # Build each styled line separately, then join vertically inside a box
        local header
        header=$(gum style --foreground 212 --bold --align center "━━━ Installation Summary ━━━")
        
        local line_ok line_fail line_skip
        line_ok=$(gum style --foreground 46 "  ✔ Successful:  ${#SUCCESS_LIST[@]}")
        line_fail=$(gum style --foreground 196 "  ✖ Failed:      ${#FAILURE_LIST[@]}")
        line_skip=$(gum style --foreground 214 "  ● Skipped:     ${#SKIPPED_LIST[@]}")
        
        local footer
        footer=$(gum style --foreground 46 --bold --align center "Operation Complete ✔")
        
        # Assemble lines and wrap in a single clean box
        printf "%s\n\n%s\n%s\n%s\n\n%s" \
            "$header" "$line_ok" "$line_fail" "$line_skip" "$footer" \
            | gum style --border rounded --border-foreground 212 --padding "1 2" --margin "0 1"
    else
        echo -e " Summary of all installation operations."; echo
        echo -e " ${GREEN}✔ Successful: ${#SUCCESS_LIST[@]}${NC}"
        echo -e " ${RED}✖ Failed:     ${#FAILURE_LIST[@]}${NC}"
        echo -e " ${YELLOW}● Skipped:    ${#SKIPPED_LIST[@]}${NC}"

        echo -e "\n${GREEN}${BOLD}Operation Complete.${NC}"
    fi
    echo ""
}

main_menu() {
    clear; print_banner "Main Menu"

    if command -v gum &>/dev/null; then
        gum style --foreground 250 --italic "  Profile: ${SELECTED_PROFILE}"
        echo ""
        local choice
        choice=$(gum choose --cursor "➜ " --cursor.foreground="212" --item.foreground="250" --selected.foreground="212" --selected.bold --header="Select an action:" \
            "Full Installation (PKG, NPM, PIP)" \
            "Install PKG Packages" \
            "Install NPM Packages" \
            "Install PIP Packages" \
            "⚙  Configure Installed Tools" \
            "📦  Backup & Restore" \
            "Change Profile" \
            "Exit Ashno")
        case "$choice" in
            "Full Installation (PKG, NPM, PIP)") main_choice=1 ;;
            "Install PKG Packages")              main_choice=2 ;;
            "Install NPM Packages")              main_choice=3 ;;
            "Install PIP Packages")              main_choice=4 ;;
            "⚙  Configure Installed Tools")      main_choice=5 ;;
            "📦  Backup & Restore")              main_choice=6 ;;
            "Change Profile")                    main_choice=7 ;;
            "Exit Ashno")                        main_choice=8 ;;
            *)                                   main_choice=8 ;;
        esac
    else
        echo -e "  ${BOLD}Active Profile:${NC} ${YELLOW}${SELECTED_PROFILE}${NC}\n"
        echo -e "  ${CYAN}1)${NC}  ${BOLD}Full Installation${NC} (PKG, NPM, PIP)"
        echo -e "  ${CYAN}2)${NC}  Install ${BOLD}PKG${NC} Packages"
        echo -e "  ${CYAN}3)${NC}  Install ${BOLD}NPM${NC} Packages"
        echo -e "  ${CYAN}4)${NC}  Install ${BOLD}PIP${NC} Packages"
        echo; echo -e "  ${CYAN}5)${NC}  ⚙  ${BOLD}Configure${NC} Installed Tools"
        echo -e "  ${CYAN}6)${NC}  📦  ${BOLD}Backup${NC} & Restore"
        echo -e "  ${CYAN}7)${NC}  Change Profile"
        echo -e "  ${CYAN}8)${NC}  Exit Ashno"
        print_prompt; read -r main_choice
    fi
}

profile_selection_menu() {
    while true; do
        clear; print_banner "Choose Installation Profile"
        local profiles=(); while IFS= read -r line; do profiles+=("$line"); done < <(find "$PROFILES_DIR" -maxdepth 1 -mindepth 1 -type d | sort)

        if [ ${#profiles[@]} -eq 0 ]; then echo -e "${RED}Error: No profiles found in '${PROFILES_DIR}/'.${NC}"; exit 1; fi

        echo -e "Welcome to Ashno. Please select a profile to begin.\n"
        local count=1

        if command -v gum &>/dev/null; then
            local gum_opts=()
            for profile_path in "${profiles[@]}"; do
                local profile_name; profile_name=$(basename "$profile_path")
                case "$profile_name" in
                    "1_essentials") gum_opts+=("Essentials") ;;
                    "2_extended")   gum_opts+=("Extended (Recommended)") ;;
                    "3_complete")   gum_opts+=("Complete") ;;
                    *)              gum_opts+=("$profile_name") ;;
                esac
            done
            gum_opts+=("Exit Ashno")

            local gum_choice
            gum_choice=$(gum choose --cursor "➜ " --cursor.foreground="212" --item.foreground="250" --selected.foreground="212" --selected.bold "${gum_opts[@]}")

            if [ -z "$gum_choice" ] || [ "$gum_choice" = "Exit Ashno" ]; then
                echo -e "\nExiting Ashno."; exit 0
            fi

            for i in "${!gum_opts[@]}"; do
                if [ "${gum_opts[$i]}" = "$gum_choice" ]; then
                    SELECTED_PROFILE=$(basename "${profiles[$i]}")
                    return 0
                fi
            done
        else
            for profile_path in "${profiles[@]}"; do
                local profile_name; profile_name=$(basename "$profile_path")
                local option_line
                case "$profile_name" in
                    "1_essentials") option_line=$(printf "  ${CYAN}%2d)${NC} ${BOLD}Essentials${NC}" "$count") ;;
                    "2_extended")   option_line=$(printf "  ${CYAN}%2d)${NC} ${BOLD}Extended${NC} ${GREEN}(Recommended)${NC}" "$count") ;;
                    "3_complete")   option_line=$(printf "  ${CYAN}%2d)${NC} ${BOLD}Complete${NC}" "$count") ;;
                    *)              option_line=$(printf "  ${CYAN}%2d)${NC} ${BOLD}%s${NC}" "$count" "$profile_name") ;;
                esac
                echo -e "$option_line"
                count=$((count + 1))
            done
            printf "  ${CYAN}%2d)${NC} ${BOLD}%s${NC}\n" "$count" "Exit Ashno"

            local choice; print_prompt; read -r choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#profiles[@]} ]; then
                SELECTED_PROFILE=$(basename "${profiles[$choice-1]}")
                return 0
            elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -eq "$count" ]; then
                echo -e "\nExiting Ashno."; exit 0
            else
                echo -e "\n${RED}Invalid selection.${NC}"; sleep 1
            fi
        fi
    done
}
