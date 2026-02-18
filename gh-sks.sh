#!/usr/bin/env bash
#
# gh-sks.sh
#
# Retrieves public SSH keys from GitHub for each entry in the config file
# and syncs them into the corresponding Linux user's ~/.ssh/authorized_keys.
#
# Designed to be run periodically via cron (as root).
#
# Usage:
#   gh-sks
#
# Configuration:
#   /etc/gh-sks/github_authorized_users  — one mapping per line:
#       <linux_user> <github_username>
#   Blank lines and lines starting with # are ignored.
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CONFIG_FILE="/etc/gh-sks/github_authorized_users"
MARKER_BEGIN="# --- BEGIN gh-sks managed keys ---"
MARKER_END="# --- END gh-sks managed keys ---"
GITHUB_API_URL="https://github.com"
LOG_PREFIX="[gh-sks]"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
_ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log_info()  { echo "$(_ts) ${LOG_PREFIX} INFO:  $*"; }
log_warn()  { echo "$(_ts) ${LOG_PREFIX} WARN:  $*" >&2; }
log_error() { echo "$(_ts) ${LOG_PREFIX} ERROR: $*" >&2; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    log_error "gh-sks must be run as root."
    exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
    log_error "Config file not found: ${CONFIG_FILE}"
    log_error "Create it with lines in the format: <linux_user> <github_username>"
    exit 1
fi

if ! command -v curl &>/dev/null; then
    log_error "curl is required but not installed."
    exit 1
fi

# ---------------------------------------------------------------------------
# Read config (skip blanks and comments)
# ---------------------------------------------------------------------------
mapfile -t LINES < <(grep -vE '^\s*(#|$)' "${CONFIG_FILE}")

if [[ ${#LINES[@]} -eq 0 ]]; then
    log_warn "No entries found in ${CONFIG_FILE}. Nothing to sync."
    exit 0
fi

log_info "Found ${#LINES[@]} mapping(s) to sync."

# ---------------------------------------------------------------------------
# Fetch keys from GitHub and group by Linux user
# ---------------------------------------------------------------------------
declare -A USER_KEYS

for line in "${LINES[@]}"; do
    # Parse: <linux_user> <github_username>
    read -r linux_user github_user <<< "${line}"

    if [[ -z "${linux_user}" || -z "${github_user}" ]]; then
        log_warn "Skipping malformed line: '${line}'"
        continue
    fi

    # Verify the Linux user exists
    if ! id "${linux_user}" &>/dev/null; then
        log_warn "Linux user '${linux_user}' does not exist — skipping."
        continue
    fi

    url="${GITHUB_API_URL}/${github_user}.keys"
    log_info "Fetching keys for github:${github_user} -> ${linux_user} from ${url}"

    keys="$(curl -fsSL --max-time 10 "${url}" 2>/dev/null || true)"

    if [[ -z "${keys}" ]]; then
        log_warn "No keys returned for github user '${github_user}' — skipping."
        continue
    fi

    key_count="$(echo "${keys}" | wc -l | xargs)"
    log_info "  -> Retrieved ${key_count} key(s) for github:${github_user}"

    # Annotate and accumulate keys per linux user
    while IFS= read -r key; do
        [[ -z "${key}" ]] && continue
        USER_KEYS["${linux_user}"]+="${key} github:${github_user}"$'\n'
    done <<< "${keys}"
done

if [[ ${#USER_KEYS[@]} -eq 0 ]]; then
    log_warn "No keys were retrieved from GitHub. No authorized_keys files will be modified."
    exit 0
fi

# ---------------------------------------------------------------------------
# Update each Linux user's authorized_keys
# ---------------------------------------------------------------------------
for linux_user in "${!USER_KEYS[@]}"; do
    managed_keys="${USER_KEYS[${linux_user}]}"
    user_home="$(eval echo "~${linux_user}")"
    ssh_dir="${user_home}/.ssh"
    auth_keys="${ssh_dir}/authorized_keys"

    # Ensure .ssh dir and authorized_keys exist with correct perms
    mkdir -p "${ssh_dir}"
    chmod 700 "${ssh_dir}"
    chown "${linux_user}:${linux_user}" "${ssh_dir}"
    touch "${auth_keys}"
    chmod 600 "${auth_keys}"
    chown "${linux_user}:${linux_user}" "${auth_keys}"

    TEMP_FILE="$(mktemp)"
    trap 'rm -f "${TEMP_FILE}"' EXIT

    # Strip existing managed block if present
    if grep -qF "${MARKER_BEGIN}" "${auth_keys}"; then
        sed "/${MARKER_BEGIN}/,/${MARKER_END}/d" "${auth_keys}" > "${TEMP_FILE}"
    else
        cp "${auth_keys}" "${TEMP_FILE}"
    fi

    # Remove trailing blank lines
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "${TEMP_FILE}" 2>/dev/null || true

    # Append managed block
    {
        [[ -s "${TEMP_FILE}" ]] && echo ""
        echo "${MARKER_BEGIN}"
        echo "# Auto-generated — do not edit this section manually."
        echo "# Last updated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "#"
        printf '%s' "${managed_keys}"
        echo "${MARKER_END}"
    } >> "${TEMP_FILE}"

    # Atomic replace
    mv "${TEMP_FILE}" "${auth_keys}"
    chmod 600 "${auth_keys}"
    chown "${linux_user}:${linux_user}" "${auth_keys}"

    total="$(echo -n "${managed_keys}" | grep -c '^' || true)"
    log_info "Wrote ${total} managed key(s) to ${auth_keys}"
done

log_info "Sync complete."
