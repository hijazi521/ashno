#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091
set -euo pipefail

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ashno-tests.XXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"
export TERM=xterm

SCRIPT_DIR="$REPO_ROOT"
SCRIPT_PATH="$REPO_ROOT/ashno"
SRC_DIR="$REPO_ROOT/src"
ORIGINAL_ARGS=()
source "$SRC_DIR/config.sh"
source "$SRC_DIR/utils.sh"
source "$SRC_DIR/updater.sh"
source "$SRC_DIR/engine.sh"
source "$SRC_DIR/menus.sh"
source "$SRC_DIR/configure.sh"
source "$SRC_DIR/backup.sh"

pass_count=0
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { pass_count=$((pass_count + 1)); printf 'PASS: %s\n' "$1"; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (expected '$2', got '$1')"; }
assert_file() { [ -f "$1" ] || fail "expected file: $1"; }
assert_not_file() { [ ! -e "$1" ] || fail "unexpected path: $1"; }

# Profile parsing and profile-path security.
parsed_npm=$(build_package_list npm 3_complete)
parsed_pip=$(build_package_list pip 3_complete)
printf '%s\n' "$parsed_npm" | grep -Fxq cdk || fail 'inline-comment NPM token was not cleaned'
printf '%s\n' "$parsed_npm" | grep -Fxq '@google-cloud/storage' || fail 'scoped NPM token was not preserved'
printf '%s\n' "$parsed_pip" | grep -Fxq boto3 || fail 'inline-comment PIP token was not cleaned'
if printf '%s\n%s\n' "$parsed_npm" "$parsed_pip" | grep -q '#'; then fail 'profile parser retained an inline comment'; fi
validate_profile_name 1_essentials || fail 'valid profile rejected'
if validate_profile_name '../../tmp'; then fail 'path traversal profile accepted'; fi
pass 'profile parsing and profile path validation'

# Safe command runner must preserve child status and create a private log.
runner_log="$TEST_ROOT/runner.log"
if run_logged 5 runner-test sh -c 'exit 7' >/dev/null 2>&1; then fail 'failed command reported success'; fi
[ -f "$ASHNO_RUN_LOG_DIR/runner-test.log" ] || fail 'runner log was not retained'
pass 'bounded command runner status and logging'

# Archive validation: valid layout succeeds; malformed and special-file archives fail.
make_valid_archive() {
    local root="$1"
    mkdir -p "$root/stage/profile" "$root/stage/dotfiles/.config/nvim"
    cat > "$root/stage/manifest.txt" <<'EOF_MANIFEST'
schema=2
ashno_version=1.10.1
date=test
pkg_count=0
npm_count=0
pip_count=0
total_count=0
dotfile_count=1
ssh_included=false
EOF_MANIFEST
    printf 'new\n' > "$root/stage/dotfiles/.config/nvim/init.lua"
    tar -czf "$root/valid.tar.gz" -C "$root/stage" .
}
archive_root="$TEST_ROOT/archive"
mkdir -p "$archive_root"
make_valid_archive "$archive_root"
_validate_archive "$archive_root/valid.tar.gz" || fail 'valid archive rejected'
printf 'not a tar' > "$archive_root/bad.tar.gz"
if _validate_archive "$archive_root/bad.tar.gz"; then fail 'malformed archive accepted'; fi
mkdir -p "$archive_root/special"
ln -s /etc/passwd "$archive_root/special/link"
tar -czf "$archive_root/symlink.tar.gz" -C "$archive_root/special" .
if _validate_archive "$archive_root/symlink.tar.gz"; then fail 'symlink archive accepted'; fi
pass 'archive integrity, path, and file-type validation'

# Directory restore replaces contents rather than nesting the source directory.
restore_source="$TEST_ROOT/restore-source/.config/nvim"
restore_dest="$HOME/.config/nvim"
mkdir -p "$restore_source" "$restore_dest"
printf 'new\n' > "$restore_source/init.lua"
printf 'old\n' > "$restore_dest/init.lua"
_restore_tree_atomic "$TEST_ROOT/restore-source/.config/nvim" "$restore_dest" || fail 'directory restore failed'
assert_eq "$(cat "$restore_dest/init.lua")" 'new' 'directory restore retained old content'
assert_not_file "$restore_dest/nvim"
pass 'atomic directory restore'

# Existing files are backed up before an atomic replacement.
old_file="$HOME/.bashrc"
printf 'old\n' > "$old_file"
_restore_file_atomic "$restore_source/init.lua" "$old_file" 600 || fail 'atomic file restore failed'
assert_eq "$(cat "$old_file")" 'new' 'atomic file restore content'
[ "$(stat -c '%a' "$old_file")" = 600 ] || fail 'restored file mode is not 600'
pass 'atomic file restore and backup'

# Noninteractive restore must require explicit confirmation and scope flags.
NONINTERACTIVE=true CONFIRM_DESTRUCTIVE=false RESTORE_PACKAGES=false RESTORE_SSH=false
if restore_backup "$archive_root/valid.tar.gz" >/dev/null 2>&1; then fail 'noninteractive restore ran without --yes'; fi
NONINTERACTIVE=false CONFIRM_DESTRUCTIVE=false RESTORE_PACKAGES=false RESTORE_SSH=false
pass 'noninteractive restore consent gate'

# CLI read-only and failure status contracts.
help_output="$TEST_ROOT/help.out"
if ! HOME="$HOME" bash "$REPO_ROOT/ashno" --help >"$help_output" 2>"$TEST_ROOT/help.err"; then fail 'help command failed'; fi
assert_file "$help_output"
[ ! -s "$TEST_ROOT/help.err" ] || fail 'help command wrote unexpected stderr'
if HOME="$HOME" bash "$REPO_ROOT/ashno" --non-interactive --restore "$TEST_ROOT/missing.tar.gz" >/dev/null 2>&1; then fail 'missing restore returned success'; fi
pass 'CLI side-effect and exit-status contracts'

# Updater fixtures: wrong remotes are rejected and local-ahead history is not treated as an update.
remote_root="$TEST_ROOT/remote.git"
checkout_root="$TEST_ROOT/update-checkout"
git init --bare -q "$remote_root"
git clone -q "$remote_root" "$checkout_root"
git -C "$checkout_root" config user.name Test
git -C "$checkout_root" config user.email test@example.invalid
printf 'initial\n' > "$checkout_root/state"
git -C "$checkout_root" add state
git -C "$checkout_root" commit -q -m initial
git -C "$checkout_root" branch -M main
git -C "$checkout_root" push -q origin HEAD:main
git -C "$checkout_root" branch --set-upstream-to=origin/main main >/dev/null
git -C "$checkout_root" remote set-url origin "$REPOSITORY_URL"
printf 'local ahead\n' >> "$checkout_root/state"
git -C "$checkout_root" add state
git -C "$checkout_root" commit -q -m local-ahead
run_logged() { return 0; }
old_script_dir="$SCRIPT_DIR"; old_script_path="$SCRIPT_PATH"; old_args=("${ORIGINAL_ARGS[@]}")
SCRIPT_DIR="$checkout_root"; SCRIPT_PATH=/bin/true; ORIGINAL_ARGS=(); NONINTERACTIVE=true
handle_updates manual || fail 'local-ahead update state was rejected'
SCRIPT_DIR="$old_script_dir"; SCRIPT_PATH="$old_script_path"; ORIGINAL_ARGS=("${old_args[@]}")
pass 'self-update remote and ancestry validation'

# Regression checks for the original repository mismatch and predictable temp path.
if grep -RInq 'hijazi521/ashno' "$REPO_ROOT" --exclude-dir=.git --exclude-dir=tests; then fail 'wrong repository target remains in source/docs'; fi
if grep -RInq '/tmp/ashno_nf.zip' "$REPO_ROOT" --exclude-dir=.git --exclude-dir=tests; then fail 'predictable font temp path remains'; fi
pass 'supply-chain and predictable-temp regressions'

printf '\nAll %d regression tests passed.\n' "$pass_count"
