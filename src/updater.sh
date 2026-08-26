#!/usr/bin/env bash
# ==============================================================================
# SECTION: SELF-UPDATE MECHANISM
# ==============================================================================

_normalize_remote_url() {
    local url="$1"
    url="${url%.git}"
    url="${url%/}"
    case "$url" in
        git@github.com:hakinexus/ashno) printf '%s\n' "$REPOSITORY_URL" ;;
        https://github.com/hakinexus/ashno) printf '%s\n' "$REPOSITORY_URL" ;;
        *) printf '%s\n' "$url" ;;
    esac
}

_verify_update_signature() {
    local commit="$1"
    if [ -z "${ASHNO_TRUSTED_SIGNING_KEY:-}" ]; then
        print_formatting warn "No trusted signing key configured; update is authenticated by the canonical HTTPS remote only."
        return 0
    fi
    command -v git >/dev/null 2>&1 || return 1
    local signature
    signature=$(git show --show-signature --format='%GK' -s "$commit" 2>/dev/null) || return 1
    [ "$signature" = "$ASHNO_TRUSTED_SIGNING_KEY" ]
}

_update_prompt() {
    local mode="$1"
    if [ "$NONINTERACTIVE" = true ]; then
        return 0
    fi
    if command -v gum >/dev/null 2>&1; then
        gum confirm 'Apply the verified Ashno update now?'
        return $?
    fi
    local choice
    if [ "$mode" = auto ]; then
        printf 'Update available. Apply it now? [Y/n]: '
    else
        printf 'Apply the verified update now? [y/N]: '
    fi
    IFS= read -r choice || return 1
    if [ "$mode" = auto ]; then
        case "$choice" in
            [nN]|[nN][oO]) return 1 ;;
            *) return 0 ;;
        esac
    fi
    case "$choice" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

handle_updates() {
    local mode="${1:-manual}"
    [ -d "$SCRIPT_DIR/.git" ] || return 0
    command -v git >/dev/null 2>&1 || return 0

    local original_dir="$PWD"
    CDPATH='' cd -- "$SCRIPT_DIR" || return 1

    local configured_remote normalized_remote current_branch
    configured_remote=$(git remote get-url origin 2>/dev/null || true)
    normalized_remote=$(_normalize_remote_url "$configured_remote")
    if [ "$normalized_remote" != "$REPOSITORY_URL" ]; then
        print_formatting error "Refusing update: origin is not the canonical Ashno repository."
        CDPATH='' cd -- "$original_dir" || true
        return 1
    fi

    current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    if [ "$current_branch" != "$UPDATE_BRANCH" ]; then
        print_formatting warn "Skipping update because the current branch is not $UPDATE_BRANCH."
        CDPATH='' cd -- "$original_dir" || true
        return 0
    fi

    printf '  Checking for Ashno updates...\n'
    if ! run_logged "$UPDATE_TIMEOUT" update-fetch \
        git fetch --prune --no-tags origin "refs/heads/$UPDATE_BRANCH:refs/remotes/origin/$UPDATE_BRANCH"; then
        CDPATH='' cd -- "$original_dir" || true
        return 1
    fi

    local local_rev remote_rev
    local_rev=$(git rev-parse HEAD 2>/dev/null) || { CDPATH='' cd -- "$original_dir" || true; return 1; }
    remote_rev=$(git rev-parse "refs/remotes/origin/$UPDATE_BRANCH" 2>/dev/null) || {
        print_formatting error "Remote update branch is unavailable."
        CDPATH='' cd -- "$original_dir" || true
        return 1
    }

    if [ "$local_rev" = "$remote_rev" ]; then
        [ "$mode" = manual ] && print_formatting success "Ashno is already up to date."
        CDPATH='' cd -- "$original_dir" || true
        return 0
    fi

    if git merge-base --is-ancestor "$remote_rev" "$local_rev"; then
        print_formatting info "Local Ashno is ahead of origin/$UPDATE_BRANCH; no update is required."
        CDPATH='' cd -- "$original_dir" || true
        return 0
    fi

    if ! git merge-base --is-ancestor "$local_rev" "$remote_rev"; then
        print_formatting error "Refusing update: local and remote histories have diverged."
        CDPATH='' cd -- "$original_dir" || true
        return 1
    fi

    if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
        print_formatting error "Refusing update: local changes or untracked files are present."
        CDPATH='' cd -- "$original_dir" || true
        return 1
    fi

    if ! _verify_update_signature "$remote_rev"; then
        print_formatting error "Refusing update: remote commit signature is not trusted."
        CDPATH='' cd -- "$original_dir" || true
        return 1
    fi

    print_formatting info "A fast-forward update is available."
    if ! _update_prompt "$mode"; then
        print_formatting info "Update cancelled; continuing with the current revision."
        CDPATH='' cd -- "$original_dir" || true
        return 0
    fi

    if ! run_logged "$UPDATE_TIMEOUT" update-pull \
        git pull --ff-only --no-edit origin "$UPDATE_BRANCH"; then
        CDPATH='' cd -- "$original_dir" || true
        return 1
    fi

    local updated_rev
    updated_rev=$(git rev-parse HEAD 2>/dev/null) || { CDPATH='' cd -- "$original_dir" || true; return 1; }
    if [ "$updated_rev" != "$remote_rev" ]; then
        print_formatting error "Update verification failed: local revision differs from fetched revision."
        CDPATH='' cd -- "$original_dir" || true
        return 1
    fi

    print_formatting success "Ashno updated to ${updated_rev:0:12}. Restarting..."
    exec "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
}
