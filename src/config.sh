#!/usr/bin/env bash
# shellcheck disable=SC2034
# ==============================================================================
# SECTION: GLOBALS AND CONFIGURATION
# ==============================================================================

# SCRIPT_DIR is initialized by the entrypoint before this module is sourced.
readonly PROFILES_DIR="$SCRIPT_DIR/profiles"
readonly REPOSITORY_URL="https://github.com/hakinexus/ashno.git"
readonly UPDATE_BRANCH="main"

ASHNO_VERSION="1.10.1"
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    IFS= read -r ASHNO_VERSION < "$SCRIPT_DIR/VERSION"
fi
if [[ ! "$ASHNO_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ASHNO_VERSION='1.10.1'
fi
readonly ASHNO_VERSION

# --- Bounded operation timeouts (seconds) ---
readonly INSTALL_TIMEOUT_SINGLE=300
readonly INSTALL_TIMEOUT_BATCH=600
readonly NETWORK_TIMEOUT=30
readonly UPDATE_TIMEOUT=120
readonly MAX_BACKUP_ARCHIVE_BYTES=$((100 * 1024 * 1024))
readonly MAX_BACKUP_MEMBERS=1000
readonly MAX_BACKUP_EXPANDED_BYTES=$((500 * 1024 * 1024))

# --- ANSI color codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# --- Private application directories ---
readonly ASHNO_BACKUP_DIR="$HOME/.ashno-backup"
readonly ASHNO_LOG_ROOT="$HOME/.ashno/logs"

# --- Runtime state ---
SUCCESS_LIST=()
FAILURE_LIST=()
SKIPPED_LIST=()
CONFIGURED_LIST=()
CONFIG_SKIPPED_LIST=()
CONFIG_FAILED_LIST=()
SELECTED_PROFILE=""
PROFILE_PATH_OVERRIDE=""
PACKAGE_PARSE_ERRORS=()
ASHNO_RUN_LOG_DIR=""
ORIGINAL_ARGS=()
ACTION=""
NONINTERACTIVE=false
ALLOW_NPM_SCRIPTS=false
SKIP_UPDATE=false
CONFIRM_DESTRUCTIVE=false
RESTORE_PACKAGES=false
RESTORE_SSH=false
