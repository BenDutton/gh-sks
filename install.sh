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
CONFIG_DIR="/etc/gh-sks"
CONFIG_FILE="${CONFIG_DIR}/github_authorized_users"
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
# 2. Create the config file if it doesn't exist
# ---------------------------------------------------------------------------
if [[ ! -f "${CONFIG_FILE}" ]]; then
    log "Creating ${CONFIG_FILE}"
    mkdir -p "${CONFIG_DIR}"
    cat > "${CONFIG_FILE}" <<'EOF'
# /etc/gh-sks/github_authorized_users
#
# Maps Linux users to GitHub usernames whose public SSH keys should
# be synced into that user's ~/.ssh/authorized_keys.
#
# Format: <linux_user> <github_username>
# One mapping per line. Blank lines and comments (lines starting
# with #) are ignored. A GitHub user can be mapped to multiple
# Linux users and vice versa.
#
# Examples:
# azureuser octocat
# azureuser defunkt
# deploy torvalds
EOF
    chmod 644 "${CONFIG_FILE}"
    log "Created ${CONFIG_FILE} — add user mappings to it."
else
    log "${CONFIG_FILE} already exists — skipping."
fi

# ---------------------------------------------------------------------------
# 3. Install hourly cron job under root (idempotent, survives reboots)
# ---------------------------------------------------------------------------
# cron jobs persist across reboots by default since they are stored in the
# crontab file, not in memory.
CURRENT_CRONTAB="$(crontab -l 2>/dev/null || true)"

if echo "${CURRENT_CRONTAB}" | grep -qF "gh-sks"; then
    log "Cron job already exists — skipping."
else
    log "Installing hourly cron job"
    (echo "${CURRENT_CRONTAB}"; echo "${CRON_JOB} ${CRON_MARKER}") | crontab -
    log "Cron job installed (runs every hour on the hour as root)."
fi

# ---------------------------------------------------------------------------
# 4. Done
# ---------------------------------------------------------------------------
echo ""
log "Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Edit ${CONFIG_FILE} and add mappings (format: <linux_user> <github_username>)"
echo "  2. Run a test sync:  sudo gh-sks"
echo ""
echo "The cron job will sync keys automatically every hour."
echo "Logs are written to /var/log/gh-sks.log"
