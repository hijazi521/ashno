#!/usr/bin/env bash
set -euo pipefail

readonly REPO_URL='https://github.com/hakinexus/ashno.git'
readonly BRANCH='main'
readonly INSTALL_DIR="${ASHNO_INSTALL_DIR:-$HOME/.ashno}"
readonly BIN_DIR="${PREFIX:-/data/data/com.termux/files/usr}/bin"
readonly EXECUTABLE="$BIN_DIR/ashno"

fail() { printf 'ashno installer: %s\n' "$1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "git is required; install it with 'pkg install git'."
[ -d "$BIN_DIR" ] && [ -w "$BIN_DIR" ] || fail "Termux bin directory is not writable: $BIN_DIR"

if [ -e "$INSTALL_DIR" ]; then
    [ -d "$INSTALL_DIR/.git" ] || fail "$INSTALL_DIR exists but is not an Ashno Git checkout."
    actual_remote=$(git -C "$INSTALL_DIR" remote get-url origin)
    actual_remote="${actual_remote%.git}"
    [ "$actual_remote" = "${REPO_URL%.git}" ] || fail "existing checkout has an unexpected origin: $actual_remote"
    [ -z "$(git -C "$INSTALL_DIR" status --porcelain --untracked-files=all)" ] || fail "local changes are present in $INSTALL_DIR"
    current_branch=$(git -C "$INSTALL_DIR" symbolic-ref --quiet --short HEAD) || fail 'existing checkout is detached'
    [ "$current_branch" = "$BRANCH" ] || fail "existing checkout is on $current_branch, expected $BRANCH"
    git -C "$INSTALL_DIR" fetch --prune --no-tags origin "refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
    local_rev=$(git -C "$INSTALL_DIR" rev-parse HEAD)
    remote_rev=$(git -C "$INSTALL_DIR" rev-parse "refs/remotes/origin/$BRANCH")
    if ! git -C "$INSTALL_DIR" merge-base --is-ancestor "$local_rev" "$remote_rev"; then
        git -C "$INSTALL_DIR" merge-base --is-ancestor "$remote_rev" "$local_rev" && fail 'local checkout is ahead; refusing to overwrite it' || fail 'local and remote histories diverged'
    fi
    git -C "$INSTALL_DIR" pull --ff-only --no-edit origin "$BRANCH"
else
    git clone --depth=1 --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

chmod 755 "$INSTALL_DIR/ashno"
if [ -d "$EXECUTABLE" ] && [ ! -L "$EXECUTABLE" ]; then
    fail "$EXECUTABLE is an existing directory"
fi
ln -sfn "$INSTALL_DIR/ashno" "$EXECUTABLE"
printf 'Ashno %s installed at %s\n' "$(cat "$INSTALL_DIR/VERSION")" "$EXECUTABLE"
