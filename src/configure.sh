#!/usr/bin/env bash
# ==============================================================================
# SECTION: POST-INSTALL CONFIGURATION ENGINE
# ==============================================================================

_backup_existing() {
    local path="$1"
    [ -e "$path" ] || [ -L "$path" ] || return 0
    mkdir -p "$ASHNO_BACKUP_DIR" || return 1
    chmod 700 "$ASHNO_BACKUP_DIR" || return 1

    local name timestamp destination suffix=0
    name=$(basename -- "$path")
    timestamp=$(date +%Y%m%d_%H%M%S)
    destination="$ASHNO_BACKUP_DIR/${name}.${timestamp}"
    while [ -e "$destination" ] || [ -L "$destination" ]; do
        suffix=$((suffix + 1))
        destination="$ASHNO_BACKUP_DIR/${name}.${timestamp}.${suffix}"
    done
    cp -a -- "$path" "$destination" || return 1
    chmod -R go-rwx -- "$destination" 2>/dev/null || true
    print_formatting info "Backed up ${path/#$HOME/~} → ${destination/#$HOME/~}"
}

_atomic_write() {
    local destination="$1"
    local parent temp_file
    parent=$(dirname -- "$destination")
    mkdir -p -- "$parent" || return 1
    temp_file=$(mktemp "$parent/.ashno-write.XXXXXX") || return 1
    if ! cat > "$temp_file"; then
        rm -f -- "$temp_file"
        return 1
    fi
    chmod 600 "$temp_file" || { rm -f -- "$temp_file"; return 1; }
    mv -f -- "$temp_file" "$destination"
}

_ask_update() {
    local prompt_text="$1"
    [ "$NONINTERACTIVE" = true ] && return 1
    if command -v gum >/dev/null 2>&1; then
        gum confirm "$prompt_text"
        return $?
    fi
    local choice
    printf '%s [y/N]: ' "$prompt_text"
    IFS= read -r choice || return 1
    case "$choice" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

_git_remote_matches() {
    local directory="$1" expected="$2" actual
    actual=$(git -C "$directory" remote get-url origin 2>/dev/null || true)
    actual="${actual%.git}"
    [ "$actual" = "${expected%.git}" ]
}

_clone_pinned_repo() {
    local url="$1" commit="$2" destination="$3"
    [ ! -e "$destination" ] || return 1
    git clone --quiet --filter=blob:none "$url" "$destination" >/dev/null 2>&1 || return 1
    if ! git -C "$destination" fetch --quiet --depth=1 origin "$commit" >/dev/null 2>&1 \
        || ! git -C "$destination" checkout --quiet --detach "$commit"; then
        rm -rf -- "$destination"
        return 1
    fi
    _git_remote_matches "$destination" "$url"
}

_update_pinned_repo() {
    local directory="$1" commit="$2" expected_url="$3"
    _git_remote_matches "$directory" "$expected_url" || return 1
    git -C "$directory" fetch --quiet --depth=1 origin "$commit" >/dev/null 2>&1 || return 1
    git -C "$directory" checkout --quiet --detach "$commit"
}

_config_header() {
    local label="$1" title="$2" fg="$3" border="${4:-rounded}"
    if command -v gum >/dev/null 2>&1; then
        gum style --border "$border" --border-foreground "$fg" --foreground "$fg" \
            --bold --padding '0 3' --margin '0 1' --align center "$label · $title"
    else
        printf '\n%s%s%s · %s\n\n' "$BOLD" "$label" "$NC" "$title"
    fi
}

configure_zsh() {
    _config_header SHELL 'ZSH + Oh-My-Zsh Setup' 39 double
    command -v zsh >/dev/null 2>&1 || { CONFIG_SKIPPED_LIST+=(ZSH); return 0; }
    command -v git >/dev/null 2>&1 || { CONFIG_FAILED_LIST+=(ZSH); return 1; }

    local omz_dir="$HOME/.oh-my-zsh"
    local omz_commit='146461f7c6d95f4ba1220559d66eb113418b40a8'
    if [ -d "$omz_dir/.git" ]; then
        _git_remote_matches "$omz_dir" 'https://github.com/ohmyzsh/ohmyzsh.git' || {
            print_formatting error 'Existing Oh-My-Zsh remote is not trusted.'
            CONFIG_FAILED_LIST+=(ZSH)
            return 1
        }
        if _ask_update 'Update Oh-My-Zsh to Ashno pinned revision?'; then
            _update_pinned_repo "$omz_dir" "$omz_commit" 'https://github.com/ohmyzsh/ohmyzsh.git' || {
                CONFIG_FAILED_LIST+=(ZSH)
                return 1
            }
        fi
    elif [ ! -e "$omz_dir" ]; then
        if ! _clone_pinned_repo 'https://github.com/ohmyzsh/ohmyzsh.git' "$omz_commit" "$omz_dir"; then
            print_formatting error 'Pinned Oh-My-Zsh installation failed.'
            CONFIG_FAILED_LIST+=(ZSH)
            return 1
        fi
    else
        print_formatting error "$omz_dir exists but is not a trusted Git checkout."
        CONFIG_FAILED_LIST+=(ZSH)
        return 1
    fi

    local zsh_custom="${ZSH_CUSTOM:-$omz_dir/custom}"
    local -a plugin_names=(zsh-autosuggestions zsh-syntax-highlighting)
    local -a plugin_urls=(
        'https://github.com/zsh-users/zsh-autosuggestions.git'
        'https://github.com/zsh-users/zsh-syntax-highlighting.git'
    )
    local -a plugin_commits=(
        '85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5'
        '2fc57d63067c18b1100ecdbf684fa5baf49459d1'
    )
    local i plugin_dir
    for i in "${!plugin_names[@]}"; do
        plugin_dir="$zsh_custom/plugins/${plugin_names[$i]}"
        mkdir -p -- "$(dirname -- "$plugin_dir")" || { CONFIG_FAILED_LIST+=(ZSH); return 1; }
        if [ -d "$plugin_dir/.git" ]; then
            _update_pinned_repo "$plugin_dir" "${plugin_commits[$i]}" "${plugin_urls[$i]}" || {
                print_formatting error "${plugin_names[$i]} update failed."
                CONFIG_FAILED_LIST+=(ZSH)
                return 1
            }
        elif [ ! -e "$plugin_dir" ]; then
            _clone_pinned_repo "${plugin_urls[$i]}" "${plugin_commits[$i]}" "$plugin_dir" || {
                print_formatting error "${plugin_names[$i]} installation failed."
                CONFIG_FAILED_LIST+=(ZSH)
                return 1
            }
        else
            print_formatting error "${plugin_dir} is not a trusted Git checkout."
            CONFIG_FAILED_LIST+=(ZSH)
            return 1
        fi
    done

    local zshrc="$HOME/.zshrc"
    if [ -e "$zshrc" ] || [ -L "$zshrc" ]; then
        _ask_update 'Apply Ashno .zshrc? Existing configuration will be backed up.' || {
            CONFIG_SKIPPED_LIST+=(ZSH)
            return 0
        }
        _backup_existing "$zshrc" || { CONFIG_FAILED_LIST+=(ZSH); return 1; }
    fi
    if ! _atomic_write "$zshrc" <<'ASHNO_ZSHRC'
# Ashno ZSH configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git zsh-autosuggestions zsh-syntax-highlighting command-not-found colored-man-pages extract z)
source "$ZSH/oh-my-zsh.sh"
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v eza >/dev/null 2>&1 && alias ls='eza --icons --group-directories-first'
command -v eza >/dev/null 2>&1 && alias ll='eza -la --icons --group-directories-first'
command -v eza >/dev/null 2>&1 && alias lt='eza --tree --level=2 --icons'
command -v bat >/dev/null 2>&1 && alias cat='bat --paging=never'
command -v rg >/dev/null 2>&1 && alias grep='rg'
command -v fd >/dev/null 2>&1 && alias find='fd'
command -v htop >/dev/null 2>&1 && alias top='htop'
alias g='git'; alias gs='git status'; alias ga='git add'; alias gc='git commit'; alias gp='git push'; alias gl='git log --oneline --graph --all'; alias gd='git diff'
alias ..='cd ..'; alias ...='cd ../..'; alias ....='cd ../../..'
alias rm='rm -i'; alias cp='cp -i'; alias mv='mv -i'
alias storage='cd ~/storage'; alias sdcard='cd ~/storage/shared'; alias reload='source ~/.zshrc'; alias cls='clear'
export EDITOR='nvim'; export VISUAL='nvim'; export LANG=en_US.UTF-8; export PATH="$HOME/.local/bin:$PATH"
HISTSIZE=50000; SAVEHIST=50000; HISTFILE=~/.zsh_history
setopt HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS SHARE_HISTORY INC_APPEND_HISTORY EXTENDED_HISTORY
[ -f "$PREFIX/share/fzf/key-bindings.zsh" ] && source "$PREFIX/share/fzf/key-bindings.zsh"
[ -f "$PREFIX/share/fzf/completion.zsh" ] && source "$PREFIX/share/fzf/completion.zsh"
bindkey '^[[A' history-search-backward; bindkey '^[[B' history-search-forward
ASHNO_ZSHRC
    then
        CONFIG_FAILED_LIST+=(ZSH)
        return 1
    fi

    if [ "$(basename -- "${SHELL:-}")" != zsh ] && _ask_update 'Set ZSH as the default shell?'; then
        if ! command -v chsh >/dev/null 2>&1 || ! chsh -s "$(command -v zsh)"; then
            CONFIG_FAILED_LIST+=(ZSH)
            return 1
        fi
    fi
    CONFIGURED_LIST+=(ZSH)
}

configure_starship() {
    _config_header PROMPT 'Starship Cross-Shell Prompt' 212 rounded
    command -v starship >/dev/null 2>&1 || { CONFIG_SKIPPED_LIST+=(Starship); return 0; }
    local config_file="$HOME/.config/starship.toml"
    if [ -e "$config_file" ] || [ -L "$config_file" ]; then
        _ask_update 'Apply Ashno Starship theme? Existing configuration will be backed up.' || { CONFIG_SKIPPED_LIST+=(Starship); return 0; }
        _backup_existing "$config_file" || { CONFIG_FAILED_LIST+=(Starship); return 1; }
    fi
    if ! _atomic_write "$config_file" <<'ASHNO_STAR'
format = "$directory$git_branch$git_status$python$nodejs$rust$golang$java$cmd_duration$line_break$character"
[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
[directory]
style = "bold cyan"
truncation_length = 3
truncate_to_repo = true
[git_branch]
format = "on [$symbol$branch]($style) "
style = "bold purple"
symbol = " "
[git_status]
format = '([$all_status$ahead_behind]($style) )'
style = "bold red"
[python]
format = '[${symbol}(${version})]($style) '
symbol = " "
style = "yellow"
[nodejs]
format = "[$symbol($version)]($style) "
symbol = " "
style = "green"
[rust]
format = "[$symbol($version)]($style) "
symbol = " "
style = "bold red"
[golang]
format = "[$symbol($version)]($style) "
symbol = " "
style = "bold cyan"
[java]
format = "[$symbol($version)]($style) "
symbol = " "
style = "bold red"
[cmd_duration]
min_time = 2000
format = "[⏱ $duration]($style) "
style = "bold yellow"
ASHNO_STAR
    then
        CONFIG_FAILED_LIST+=(Starship)
        return 1
    fi
    CONFIGURED_LIST+=(Starship)
}

configure_git() {
    _config_header GIT 'Git Version Control Setup' 208 thick
    command -v git >/dev/null 2>&1 || { CONFIG_SKIPPED_LIST+=(Git); return 0; }
    local current_name current_email name email editor
    current_name=$(git config --global user.name 2>/dev/null || true)
    current_email=$(git config --global user.email 2>/dev/null || true)
    if [ -n "$current_name" ] && [ -n "$current_email" ] && ! _ask_update 'Reconfigure Git identity?'; then
        name="$current_name"; email="$current_email"
    else
        if command -v gum >/dev/null 2>&1 && [ "$NONINTERACTIVE" = false ]; then
            name=$(gum input --placeholder='Your Name' --header='Full name:' --width=40) || return 1
            email=$(gum input --placeholder='you@example.com' --header='Email address:' --width=40) || return 1
            editor=$(gum choose --header='Default editor:' nvim vim nano micro emacs) || return 1
        elif [ "$NONINTERACTIVE" = false ]; then
            printf 'Full name: '; IFS= read -r name || return 1
            printf 'Email: '; IFS= read -r email || return 1
            printf 'Editor (nvim/vim/nano/micro/emacs): '; IFS= read -r editor || return 1
        else
            CONFIG_SKIPPED_LIST+=(Git)
            return 0
        fi
        [[ "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || { print_formatting error 'Invalid email address.'; CONFIG_FAILED_LIST+=(Git); return 1; }
        git config --global user.name "$name" || return 1
        git config --global user.email "$email" || return 1
        [ -n "$editor" ] && git config --global core.editor "$editor"
    fi

    local -a settings=(
        'alias.st=status -sb'
        'alias.lg=log --graph --oneline --all --decorate'
        'alias.co=checkout'
        'alias.br=branch -vv'
        'alias.ci=commit'
        'alias.unstage=reset HEAD --'
        'alias.last=log -1 HEAD --stat'
        'alias.staged=diff --cached'
        'alias.amend=commit --amend --no-edit'
        'init.defaultBranch=main'
        'pull.rebase=true'
        'pull.ff=only'
        'push.autoSetupRemote=true'
        'core.autocrlf=input'
        'color.ui=auto'
    )
    local setting key value
    for setting in "${settings[@]}"; do
        key="${setting%%=*}"; value="${setting#*=}"
        git config --global "$key" "$value" || { CONFIG_FAILED_LIST+=(Git); return 1; }
    done
    CONFIGURED_LIST+=(Git)
}

configure_neovim() {
    _config_header NVIM 'Neovim Editor Setup' 82 normal
    command -v nvim >/dev/null 2>&1 || { CONFIG_SKIPPED_LIST+=(Neovim); return 0; }
    local nvim_dir="$HOME/.config/nvim"
    if [ -e "$nvim_dir" ] || [ -L "$nvim_dir" ]; then
        _ask_update 'Apply Ashno Neovim setup? Existing configuration will be backed up.' || { CONFIG_SKIPPED_LIST+=(Neovim); return 0; }
        _backup_existing "$nvim_dir" || { CONFIG_FAILED_LIST+=(Neovim); return 1; }
        rm -rf -- "$nvim_dir" || { CONFIG_FAILED_LIST+=(Neovim); return 1; }
    fi
    mkdir -p -- "$nvim_dir" || { CONFIG_FAILED_LIST+=(Neovim); return 1; }
    if ! _atomic_write "$nvim_dir/init.lua" <<'ASHNO_NVIM'
vim.g.mapleader = " "
vim.g.maplocalleader = " "
local o = vim.opt
o.number = true; o.relativenumber = true; o.mouse = "a"; o.ignorecase = true; o.smartcase = true
o.hlsearch = false; o.incsearch = true; o.breakindent = true; o.undofile = true; o.signcolumn = "yes"
o.updatetime = 250; o.timeoutlen = 300; o.splitright = true; o.splitbelow = true; o.cursorline = true
o.scrolloff = 10; o.tabstop = 4; o.shiftwidth = 4; o.expandtab = true; o.termguicolors = true; o.clipboard = "unnamedplus"
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local lazy_commit = "0d61488b89a570415177f75a36ef93616aac6c77"
local lazy_url = "https://github.com/folke/lazy.nvim.git"
if vim.loop.fs_stat(lazypath) then
  local remote = vim.fn.system({"git", "-C", lazypath, "config", "--get", "remote.origin.url"}):gsub("%.git%s*$", "")
  local existing_commit = vim.fn.system({"git", "-C", lazypath, "rev-parse", "HEAD"}):gsub("%s+$", "")
  if vim.v.shell_error ~= 0 or remote ~= lazy_url:gsub("%.git%s*$", "") or existing_commit ~= lazy_commit then
    error("Ashno: existing lazy.nvim checkout is not the pinned trusted revision")
  end
else
  vim.fn.mkdir(vim.fn.fnamemodify(lazypath, ":h"), "p")
  vim.fn.system({"git", "clone", "--filter=blob:none", lazy_url, "--branch", "v9.25.1", lazypath})
  if vim.v.shell_error ~= 0 then error("Ashno: failed to install pinned lazy.nvim") end
  vim.fn.system({"git", "-C", lazypath, "checkout", "--detach", lazy_commit})
  if vim.v.shell_error ~= 0 then error("Ashno: failed to verify pinned lazy.nvim") end
end
vim.opt.rtp:prepend(lazypath)
require("lazy").setup({
  {"catppuccin/nvim", commit="edefef779ab08ce1a4a404713e3012b0d202bd35", name="catppuccin", priority=1000, config=function() require("catppuccin").setup({flavour="mocha"}); vim.cmd.colorscheme("catppuccin") end},
  {"nvim-lualine/lualine.nvim", commit="221ce6b2d999187044529f49da6554a92f740a96", opts={options={theme="catppuccin"}}},
  {"nvim-telescope/telescope.nvim", commit="a0bbec21143c7bc5f8bb02e0005fa0b982edc026", dependencies={{"nvim-lua/plenary.nvim", commit="74b06c6c75e4eeb3108ec01852001636d85a932b"}}, keys={{"<leader>ff", "<cmd>Telescope find_files<cr>"}, {"<leader>fg", "<cmd>Telescope live_grep<cr>"}, {"<leader>fb", "<cmd>Telescope buffers<cr>"}}},
  {"nvim-treesitter/nvim-treesitter", commit="cf12346a3414fa1b06af75c79faebe7f76df080a", build=":TSUpdate", config=function() require("nvim-treesitter.configs").setup({ensure_installed={"lua","python","javascript","typescript","bash","json","yaml","markdown","html","css"}, highlight={enable=true}, indent={enable=true}}) end},
  {"lewis6991/gitsigns.nvim", commit="5be654f2232c10ddcad19c1607a67b6b4b78fc29", opts={}},
  {"windwp/nvim-autopairs", commit="430522f95fe4fb7c511ec64f8c1a90cc6a66c05c", event="InsertEnter", opts={}},
  {"numToStr/Comment.nvim", commit="e30b7f2008e52442154b66f7c519bfd2f1e32acb", opts={}},
  {"lukas-reineke/indent-blankline.nvim", commit="d28a3f70721c79e3c5f6693057ae929f3d9c0a03", main="ibl", opts={}},
})
local map = vim.keymap.set
map("n", "<leader>w", "<cmd>w<cr>"); map("n", "<leader>q", "<cmd>q<cr>"); map("n", "<Esc>", "<cmd>nohlsearch<cr>")
map("n", "<C-h>", "<C-w>h"); map("n", "<C-j>", "<C-w>j"); map("n", "<C-k>", "<C-w>k"); map("n", "<C-l>", "<C-w>l")
ASHNO_NVIM
    then
        CONFIG_FAILED_LIST+=(Neovim)
        return 1
    fi
    CONFIGURED_LIST+=(Neovim)
}

configure_termux() {
    _config_header TERMUX 'Terminal Configuration' 44 double
    if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX" ]; then
        CONFIG_SKIPPED_LIST+=(Termux)
        print_formatting warn 'Termux terminal settings are available only inside Termux.'
        return 0
    fi
    local termux_dir="$HOME/.termux" props_file="$HOME/.termux/termux.properties"
    local write_props=true
    local changed=false
    if [ -e "$props_file" ] || [ -L "$props_file" ]; then
        _ask_update 'Apply Ashno terminal properties? Existing properties will be backed up.' || write_props=false
    fi
    if [ "$write_props" = true ]; then
        [ -e "$props_file" ] && { _backup_existing "$props_file" || { CONFIG_FAILED_LIST+=(Termux); return 1; }; }
        if ! _atomic_write "$props_file" <<'ASHNO_TERMUX'
extra-keys = [['ESC','/','-','HOME','UP','END','PGUP'],['TAB','CTRL','ALT','LEFT','DOWN','RIGHT','PGDN']]
bell-character = vibrate
use-black-ui = true
terminal-cursor-style = bar
terminal-cursor-blink-rate = 600
# External command execution remains disabled by default for safety.
ASHNO_TERMUX
        then
            CONFIG_FAILED_LIST+=(Termux)
            return 1
        fi
        changed=true
    fi

    local install_font=false
    if [ "$NONINTERACTIVE" = false ] && _ask_update 'Download and install the pinned JetBrains Mono Nerd Font?'; then install_font=true; fi
    if [ "$install_font" = true ]; then
        if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
            CONFIG_FAILED_LIST+=(Termux)
            return 1
        fi
        local font_url='https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip'
        local font_sha256='76f05ff3ace48a464a6ca57977998784ff7bdbb65a6d915d7e401cd3927c493c'
        local zip_file tmp_dir font_file
        zip_file=$(mktemp "${TMPDIR:-/tmp}/ashno-font.XXXXXX") || { CONFIG_FAILED_LIST+=(Termux); return 1; }
        tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ashno-font-dir.XXXXXX") || { rm -f -- "$zip_file"; CONFIG_FAILED_LIST+=(Termux); return 1; }
        if ! curl --fail --silent --show-error --location --connect-timeout "$NETWORK_TIMEOUT" --max-time "$NETWORK_TIMEOUT" "$font_url" -o "$zip_file"; then
            rm -f -- "$zip_file"; rm -rf -- "$tmp_dir"; CONFIG_FAILED_LIST+=(Termux); return 1
        fi
        if [ "$(sha256sum "$zip_file" | awk '{print $1}')" != "$font_sha256" ]; then
            print_formatting error 'Downloaded font checksum does not match the pinned release.'
            rm -f -- "$zip_file"; rm -rf -- "$tmp_dir"; CONFIG_FAILED_LIST+=(Termux); return 1
        fi
        if ! unzip -oq "$zip_file" -d "$tmp_dir" >/dev/null; then
            rm -f -- "$zip_file"; rm -rf -- "$tmp_dir"; CONFIG_FAILED_LIST+=(Termux); return 1
        fi
        font_file=$(find "$tmp_dir" -type f -name '*Regular*.ttf' ! -name '*Propo*' -print -quit)
        [ -n "$font_file" ] || { rm -f -- "$zip_file"; rm -rf -- "$tmp_dir"; CONFIG_FAILED_LIST+=(Termux); return 1; }
        if [ -e "$termux_dir/font.ttf" ] && ! _backup_existing "$termux_dir/font.ttf"; then
            rm -f -- "$zip_file"; rm -rf -- "$tmp_dir"; CONFIG_FAILED_LIST+=(Termux); return 1
        fi
        if ! mkdir -p -- "$termux_dir" || ! cp -- "$font_file" "$termux_dir/font.ttf"; then
            rm -f -- "$zip_file"; rm -rf -- "$tmp_dir"; CONFIG_FAILED_LIST+=(Termux); return 1
        fi
        if ! chmod 600 "$termux_dir/font.ttf"; then
            rm -f -- "$zip_file"; rm -rf -- "$tmp_dir"; CONFIG_FAILED_LIST+=(Termux); return 1
        fi
        rm -f -- "$zip_file"; rm -rf -- "$tmp_dir"
        changed=true
    fi
    if [ "$write_props" = true ] || [ "$install_font" = true ]; then
        if command -v termux-reload-settings >/dev/null 2>&1; then
            termux-reload-settings || print_formatting warn 'Termux settings were written but could not be reloaded automatically.'
        fi
    fi
    if [ "$changed" = false ]; then
        CONFIG_SKIPPED_LIST+=(Termux)
        return 0
    fi
    CONFIGURED_LIST+=(Termux)
}

configure_ssh() {
    _config_header SSH 'Secure Shell Key Generation' 196 thick
    command -v ssh-keygen >/dev/null 2>&1 || { CONFIG_SKIPPED_LIST+=(SSH); return 0; }
    local ssh_dir="$HOME/.ssh" key_file="$HOME/.ssh/id_ed25519"
    if ! mkdir -p -- "$ssh_dir" || ! chmod 700 "$ssh_dir"; then
        CONFIG_FAILED_LIST+=(SSH)
        return 1
    fi
    if [ -e "$key_file" ] || [ -e "${key_file}.pub" ]; then
        _ask_update 'Generate a new SSH key pair? Existing keys will be backed up.' || { CONFIG_SKIPPED_LIST+=(SSH); return 0; }
        if [ -e "$key_file" ] && ! _backup_existing "$key_file"; then
            CONFIG_FAILED_LIST+=(SSH)
            return 1
        fi
        if [ -e "${key_file}.pub" ] && ! _backup_existing "${key_file}.pub"; then
            CONFIG_FAILED_LIST+=(SSH)
            return 1
        fi
    elif [ "$NONINTERACTIVE" = true ]; then
        CONFIG_SKIPPED_LIST+=(SSH)
        return 0
    fi

    local email comment temp_key
    email=$(git config --global user.email 2>/dev/null || true)
    if [ -z "$email" ] && [ "$NONINTERACTIVE" = false ]; then
        if command -v gum >/dev/null 2>&1; then email=$(gum input --placeholder='you@example.com' --header='Email for SSH key comment:' --width=40); else printf 'Email for SSH key comment: '; IFS= read -r email || return 1; fi
    fi
    comment="${email:-ashno@termux}"
    temp_key=$(mktemp "$ssh_dir/.ashno-key.XXXXXX") || { CONFIG_FAILED_LIST+=(SSH); return 1; }
    rm -f -- "$temp_key"
    if ! ssh-keygen -q -t ed25519 -C "$comment" -N '' -f "$temp_key" >/dev/null 2>&1; then
        rm -f -- "$temp_key" "${temp_key}.pub"
        CONFIG_FAILED_LIST+=(SSH)
        return 1
    fi
    chmod 600 "$temp_key"; chmod 644 "${temp_key}.pub"
    if ! mv -f -- "$temp_key" "$key_file"; then
        rm -f -- "$temp_key" "${temp_key}.pub"; CONFIG_FAILED_LIST+=(SSH); return 1
    fi
    if ! mv -f -- "${temp_key}.pub" "${key_file}.pub"; then
        rm -f -- "$key_file" "${temp_key}.pub"; CONFIG_FAILED_LIST+=(SSH); return 1
    fi
    print_formatting success "SSH key pair generated at ${key_file/#$HOME/~}."
    if [ "$NONINTERACTIVE" = false ]; then cat "${key_file}.pub"; fi
    CONFIGURED_LIST+=(SSH)
}

_config_summary() {
    [ "${#CONFIGURED_LIST[@]}" -gt 0 ] && printf '%sConfigured:%s %s\n' "$GREEN" "$NC" "${CONFIGURED_LIST[*]}"
    [ "${#CONFIG_SKIPPED_LIST[@]}" -gt 0 ] && printf '%sSkipped:%s %s\n' "$YELLOW" "$NC" "${CONFIG_SKIPPED_LIST[*]}"
    [ "${#CONFIG_FAILED_LIST[@]}" -gt 0 ] && printf '%sFailed:%s %s\n' "$RED" "$NC" "${CONFIG_FAILED_LIST[*]}"
}

_run_configurator() {
    case "$1" in
        zsh) configure_zsh ;;
        starship) configure_starship ;;
        git) configure_git ;;
        neovim) configure_neovim ;;
        termux) configure_termux ;;
        ssh) configure_ssh ;;
        *) return 2 ;;
    esac
}

configure_menu() {
    CONFIGURED_LIST=(); CONFIG_SKIPPED_LIST=(); CONFIG_FAILED_LIST=()
    local -a available=() labels=()
    command -v zsh >/dev/null 2>&1 && { available+=(zsh); labels+=('ZSH + Oh-My-Zsh'); }
    command -v starship >/dev/null 2>&1 && { available+=(starship); labels+=('Starship Prompt'); }
    command -v git >/dev/null 2>&1 && { available+=(git); labels+=('Git Configuration'); }
    command -v nvim >/dev/null 2>&1 && { available+=(neovim); labels+=('Neovim'); }
    available+=(termux); labels+=('Termux Terminal')
    command -v ssh-keygen >/dev/null 2>&1 && { available+=(ssh); labels+=('SSH Keys'); }

    if [ "$NONINTERACTIVE" = true ]; then
        print_formatting warn 'Configuration is interactive; use the menu without --non-interactive.'
        return 0
    fi

    if command -v gum >/dev/null 2>&1; then
        local pick i
        while true; do
            pick=$(gum choose --cursor='➜ ' "${labels[@]}" 'Configure ALL' 'Done') || return 1
            [ "$pick" = Done ] || [ -z "$pick" ] && break
            if [ "$pick" = 'Configure ALL' ]; then
                for i in "${available[@]}"; do _run_configurator "$i" || true; done
                break
            fi
            for i in "${!labels[@]}"; do
                if [ "${labels[$i]}" = "$pick" ]; then _run_configurator "${available[$i]}" || true; break; fi
            done
        done
    else
        local i=1 choice
        for pick in "${labels[@]}"; do printf '  %d) %s\n' "$i" "$pick"; i=$((i + 1)); done
        printf '  a) Configure all\n  s) Skip\n'
        printf 'Select choices (for example 1,3): '
        IFS= read -r choice || return 1
        [ "$choice" = s ] || [ -z "$choice" ] && return 0
        if [ "$choice" = a ]; then
            for pick in "${available[@]}"; do _run_configurator "$pick" || true; done
        else
            local -a selected=()
            IFS=',' read -r -a selected <<< "$choice"
            for choice in "${selected[@]}"; do
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#available[@]}" ]; then
                    _run_configurator "${available[$((choice - 1))]}" || true
                fi
            done
        fi
    fi
    _config_summary
    wait_for_key
    [ "${#CONFIG_FAILED_LIST[@]}" -eq 0 ]
}

offer_configuration() {
    [ "$NONINTERACTIVE" = true ] && return 0
    if command -v gum >/dev/null 2>&1; then
        if gum confirm 'Set up your tools now? (ZSH, Starship, Git, Neovim, and SSH)'; then
            configure_menu || true
        fi
    else
        printf 'Set up your tools now? [y/N]: '
        local choice
        IFS= read -r choice || return 0
        case "$choice" in [yY]|[yY][eE][sS]) configure_menu || true ;; esac
    fi
}
