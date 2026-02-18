#!/usr/bin/env bash
#
# gh-sks.sh
#
# Retrieves public SSH keys from GitHub for each user listed in
# ~/.ssh/github_authorized_users and syncs them into ~/.ssh/authorized_keys.
#
# Designed to be run periodically via cron.
#
# Usage:
#   ./gh-sks.sh
#
# Configuration:
#   ~/.ssh/github_authorized_users  — one GitHub username per line
#                                      blank lines and lines starting with # are ignored
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SSH_DIR="${HOME}/.ssh"
AUTHORIZED_USERS_FILE="${SSH_DIR}/github_authorized_users"
AUTHORIZED_KEYS_FILE="${SSH_DIR}/authorized_keys"
MARKER_BEGIN="# --- BEGIN gh-sks managed keys ---"
MARKER_END="# --- END gh-sks managed keys ---"
GITHUB_API_URL="https://github.com"
LOG_PREFIX="[gh-sks]"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info()  { echo "${LOG_PREFIX} INFO:  $*"; }
log_warn()  { echo "${LOG_PREFIX} WARN:  $*" >&2; }
log_error() { echo "${LOG_PREFIX} ERROR: $*" >&2; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [[ ! -f "${AUTHORIZED_USERS_FILE}" ]]; then
    log_error "Users file not found: ${AUTHORIZED_USERS_FILE}"
    log_error "Create it with one GitHub username per line."
    exit 1
fi

# Ensure the .ssh directory and authorized_keys file exist with correct perms
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
touch "${AUTHORIZED_KEYS_FILE}"
chmod 600 "${AUTHORIZED_KEYS_FILE}"

# Check for curl
if ! command -v curl &>/dev/null; then
    log_error "curl is required but not installed."
    exit 1
fi

# ---------------------------------------------------------------------------
# Read GitHub usernames (skip blanks and comments)
# ---------------------------------------------------------------------------
mapfile -t USERS < <(grep -vE '^\s*(#|$)' "${AUTHORIZED_USERS_FILE}")

if [[ ${#USERS[@]} -eq 0 ]]; then
    log_warn "No users found in ${AUTHORIZED_USERS_FILE}. Nothing to sync."
    exit 0
fi

log_info "Found ${#USERS[@]} user(s) to sync: ${USERS[*]}"

# ---------------------------------------------------------------------------
# Fetch keys from GitHub
# ---------------------------------------------------------------------------
MANAGED_KEYS=""

for user in "${USERS[@]}"; do
    # Trim whitespace
    user="$(echo "${user}" | xargs)"
    [[ -z "${user}" ]] && continue

    url="${GITHUB_API_URL}/${user}.keys"
    log_info "Fetching keys for '${user}' from ${url}"

    keys="$(curl -fsSL --max-time 10 "${url}" 2>/dev/null || true)"

    if [[ -z "${keys}" ]]; then
        log_warn "No keys returned for user '${user}' — skipping."
        continue
    fi

    # Count keys retrieved
    key_count="$(echo "${keys}" | wc -l | xargs)"
    log_info "  -> Retrieved ${key_count} key(s) for '${user}'"

    # Annotate each key with the GitHub username
    while IFS= read -r key; do
        [[ -z "${key}" ]] && continue
        MANAGED_KEYS+="${key} github:${user}"$'\n'
    done <<< "${keys}"
done

if [[ -z "${MANAGED_KEYS}" ]]; then
    log_warn "No keys were retrieved from GitHub. authorized_keys will not be modified."
    exit 0
fi

# ---------------------------------------------------------------------------
# Rebuild authorized_keys
# ---------------------------------------------------------------------------
# Strategy:
#   1. Preserve any keys OUTSIDE the managed block (user's own keys).
#   2. Replace the managed block with freshly-fetched keys.

TEMP_FILE="$(mktemp)"
trap 'rm -f "${TEMP_FILE}"' EXIT

# Extract non-managed keys (everything outside the markers)
if grep -qF "${MARKER_BEGIN}" "${AUTHORIZED_KEYS_FILE}"; then
    # File has an existing managed block — strip it
    sed "/${MARKER_BEGIN}/,/${MARKER_END}/d" "${AUTHORIZED_KEYS_FILE}" > "${TEMP_FILE}"
else
    # No managed block yet — keep everything
    cp "${AUTHORIZED_KEYS_FILE}" "${TEMP_FILE}"
fi

# Remove trailing blank lines from preserved content
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "${TEMP_FILE}" 2>/dev/null || true

# Append managed block
{
    # Add a blank line separator if the file is not empty
    [[ -s "${TEMP_FILE}" ]] && echo ""
    echo "${MARKER_BEGIN}"
    echo "# Auto-generated — do not edit this section manually."
    echo "# Last updated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "#"
    printf '%s' "${MANAGED_KEYS}"
    echo "${MARKER_END}"
} >> "${TEMP_FILE}"

# Atomic replace
mv "${TEMP_FILE}" "${AUTHORIZED_KEYS_FILE}"
chmod 600 "${AUTHORIZED_KEYS_FILE}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
total="$(echo -n "${MANAGED_KEYS}" | grep -c '^' || true)"
log_info "Sync complete. ${total} managed key(s) written to ${AUTHORIZED_KEYS_FILE}"
