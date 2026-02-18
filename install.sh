#!/usr/bin/env bash
#
# install.sh — One-line installer for gh-sks
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/BenDutton/gh-sks/main/install.sh | sudo bash
#

set -euo pipefail

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: This installer must be run as root (use sudo)." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_RAW_URL="https://raw.githubusercontent.com/BenDutton/gh-sks/main"
INSTALL_DIR="/usr/local/bin"
INSTALL_PATH="${INSTALL_DIR}/gh-sks"
SSH_DIR="${HOME}/.ssh"
USERS_FILE="${SSH_DIR}/github_authorized_users"
CRON_JOB="0 * * * * /usr/local/bin/gh-sks >> /var/log/gh-sks.log 2>&1"
CRON_MARKER="# gh-sks"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "==> $*"; }

# ---------------------------------------------------------------------------
# 1. Download the sync script
# ---------------------------------------------------------------------------
log "Downloading gh-sks.sh to ${INSTALL_PATH}"
curl -fsSL "${REPO_RAW_URL}/gh-sks.sh" -o "${INSTALL_PATH}"
chmod 755 "${INSTALL_PATH}"
log "Installed ${INSTALL_PATH}"

# ---------------------------------------------------------------------------
# 2. Create the authorized users file if it doesn't exist
# ---------------------------------------------------------------------------
if [[ ! -f "${USERS_FILE}" ]]; then
    log "Creating ${USERS_FILE}"
    mkdir -p "${SSH_DIR}"
    chmod 700 "${SSH_DIR}"
    cat > "${USERS_FILE}" <<'EOF'
# github_authorized_users
#
# List GitHub usernames whose public SSH keys should be synced
# into ~/.ssh/authorized_keys on this machine.
#
# One username per line. Blank lines and comments (lines starting
# with #) are ignored.
#
# Example:
# octocat
# defunkt
EOF
    chmod 600 "${USERS_FILE}"
    log "Created ${USERS_FILE} — add GitHub usernames to it."
else
    log "${USERS_FILE} already exists — skipping."
fi

# ---------------------------------------------------------------------------
# 3. Install hourly cron job (idempotent, survives reboots)
# ---------------------------------------------------------------------------
# cron jobs persist across reboots by default since they are stored in the
# crontab file, not in memory.
CURRENT_CRONTAB="$(crontab -l 2>/dev/null || true)"

if echo "${CURRENT_CRONTAB}" | grep -qF "gh-sks"; then
    log "Cron job already exists — skipping."
else
    log "Installing hourly cron job"
    (echo "${CURRENT_CRONTAB}"; echo "${CRON_JOB} ${CRON_MARKER}") | crontab -
    log "Cron job installed (runs every hour on the hour)."
fi

# ---------------------------------------------------------------------------
# 4. Done
# ---------------------------------------------------------------------------
echo ""
log "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Edit ${USERS_FILE} and add GitHub usernames (one per line)"
echo "  2. Run a test sync:  sudo gh-sks"
echo ""
echo "The cron job will sync keys automatically every hour."
echo "Logs are written to /var/log/gh-sks.log"
