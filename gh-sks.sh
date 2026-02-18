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
# Version (replaced automatically by CI on tagged releases)
# ---------------------------------------------------------------------------
VERSION="dev"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
CONFIG_FILE="/etc/gh-sks/github_authorized_users"
MARKER_BEGIN="# --- BEGIN gh-sks managed keys ---"
MARKER_END="# --- END gh-sks managed keys ---"
GITHUB_API_URL="https://github.com"
GH_REPO="BenDutton/gh-sks"
RELEASE_URL="https://github.com/${GH_REPO}/releases/latest/download"
LOG_PREFIX="[gh-sks]"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
_ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log_info()  { echo "$(_ts) ${LOG_PREFIX} INFO:  $*"; }
log_warn()  { echo "$(_ts) ${LOG_PREFIX} WARN:  $*" >&2; }
log_error() { echo "$(_ts) ${LOG_PREFIX} ERROR: $*" >&2; }

# ---------------------------------------------------------------------------
# --version
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--version" ]]; then
    echo "gh-sks ${VERSION}"
    exit 0
fi

# ---------------------------------------------------------------------------
# --help
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'USAGE'
Usage: gh-sks [OPTION]

Sync GitHub users' public SSH keys into Linux authorized_keys files.

Options:
  --add <linux_user> <github_user>     Add a mapping to the config file
  --remove <linux_user> <github_user>  Remove a mapping from the config file
  --update                             Update gh-sks to the latest release
  --uninstall                          Fully remove gh-sks from this system
  --version                            Print the installed version
  --help, -h                           Show this help message

With no options, syncs keys according to the config file.
USAGE
    exit 0
fi

# ---------------------------------------------------------------------------
# --add <linux_user> <github_user>
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--add" ]]; then
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "--add must be run as root (use sudo)."
        exit 1
    fi
    if [[ -z "${2:-}" || -z "${3:-}" ]]; then
        log_error "Usage: gh-sks --add <linux_user> <github_user>"
        exit 1
    fi
    LINUX_USER="$2"
    GITHUB_USER="$3"

    mkdir -p "$(dirname "${CONFIG_FILE}")"
    touch "${CONFIG_FILE}"

    # Check for duplicate
    if grep -qE "^\s*${LINUX_USER}\s+${GITHUB_USER}\s*$" "${CONFIG_FILE}"; then
        log_warn "Mapping already exists: ${LINUX_USER} ${GITHUB_USER}"
        exit 0
    fi

    echo "${LINUX_USER} ${GITHUB_USER}" >> "${CONFIG_FILE}"
    log_info "Added mapping: ${LINUX_USER} <- github:${GITHUB_USER}"
    exit 0
fi

# ---------------------------------------------------------------------------
# --remove <linux_user> <github_user>
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--remove" ]]; then
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "--remove must be run as root (use sudo)."
        exit 1
    fi
    if [[ -z "${2:-}" || -z "${3:-}" ]]; then
        log_error "Usage: gh-sks --remove <linux_user> <github_user>"
        exit 1
    fi
    LINUX_USER="$2"
    GITHUB_USER="$3"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Config file not found: ${CONFIG_FILE}"
        exit 1
    fi

    if ! grep -qE "^\s*${LINUX_USER}\s+${GITHUB_USER}\s*$" "${CONFIG_FILE}"; then
        log_warn "Mapping not found: ${LINUX_USER} ${GITHUB_USER}"
        exit 1
    fi

    sed -i "/^\s*${LINUX_USER}\s\+${GITHUB_USER}\s*$/d" "${CONFIG_FILE}"
    log_info "Removed mapping: ${LINUX_USER} <- github:${GITHUB_USER}"
    log_info "Run 'sudo gh-sks' to apply changes immediately."
    exit 0
fi

# ---------------------------------------------------------------------------
# Self-update
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--update" ]]; then
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "Update must be run as root (use sudo)."
        exit 1
    fi
    SELF_PATH="$(readlink -f "$0")"
    DOWNLOAD_URL="${RELEASE_URL}/gh-sks.sh"
    log_info "Updating gh-sks from latest release ..."
    log_info "  ${DOWNLOAD_URL}"
    TEMP="$(mktemp)"
    if curl -fsSL --max-time 15 -L "${DOWNLOAD_URL}" -o "${TEMP}"; then
        NEW_VER=$(grep -m1 '^VERSION=' "${TEMP}" | cut -d'"' -f2)
        chmod 755 "${TEMP}"
        mv "${TEMP}" "${SELF_PATH}"
        log_info "Update complete. ${VERSION} -> ${NEW_VER:-unknown}"
    else
        rm -f "${TEMP}"
        log_error "Update failed — could not download from GitHub."
        exit 1
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--uninstall" ]]; then
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "Uninstall must be run as root (use sudo)."
        exit 1
    fi

    log_info "Uninstalling gh-sks..."

    # 1. Stop and remove systemd timer and service
    if systemctl is-active --quiet gh-sks.timer 2>/dev/null; then
        systemctl disable --now gh-sks.timer
        log_info "Disabled and stopped gh-sks.timer."
    fi
    rm -f /etc/systemd/system/gh-sks.service /etc/systemd/system/gh-sks.timer
    systemctl daemon-reload 2>/dev/null || true
    log_info "Removed systemd units."

    # 2. Strip managed key blocks from all users' authorized_keys
    for auth_file in /home/*/.ssh/authorized_keys /root/.ssh/authorized_keys; do
        [[ -f "${auth_file}" ]] || continue
        if grep -qF "${MARKER_BEGIN}" "${auth_file}"; then
            sed -i "/${MARKER_BEGIN}/,/${MARKER_END}/d" "${auth_file}"
            log_info "Removed managed keys from ${auth_file}"
        fi
    done

    # 3. Remove config directory
    if [[ -d /etc/gh-sks ]]; then
        rm -rf /etc/gh-sks
        log_info "Removed /etc/gh-sks/"
    fi

    # 4. Remove self
    SELF_PATH="$(readlink -f "$0")"
    log_info "Removing ${SELF_PATH}..."
    rm -f "${SELF_PATH}"

    log_info "Uninstall complete."
    exit 0
fi

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
