#!/usr/bin/env bash
#
# install.sh — One-line installer for gh-sks
#
# Usage:
#   curl -fsSL https://github.com/BenDutton/gh-sks/releases/latest/download/install.sh | sudo bash
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
GH_REPO="BenDutton/gh-sks"
RELEASE_URL="https://github.com/${GH_REPO}/releases/latest/download"
INSTALL_DIR="/usr/local/bin"
INSTALL_PATH="${INSTALL_DIR}/gh-sks"
CONFIG_DIR="/etc/gh-sks"
CONFIG_FILE="${CONFIG_DIR}/github_authorized_users"
SYSTEMD_DIR="/etc/systemd/system"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "==> $*"; }

# ---------------------------------------------------------------------------
# 1. Download the sync script
# ---------------------------------------------------------------------------
log "Downloading gh-sks from latest release to ${INSTALL_PATH}"
curl -fsSL -L "${RELEASE_URL}/gh-sks.sh" -o "${INSTALL_PATH}"
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
# 3. Install systemd service and timer
# ---------------------------------------------------------------------------
log "Installing systemd service and timer"

cat > "${SYSTEMD_DIR}/gh-sks.service" <<'EOF'
[Unit]
Description=GitHub SSH Key Sync (gh-sks)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/gh-sks
EOF

cat > "${SYSTEMD_DIR}/gh-sks.timer" <<'EOF'
[Unit]
Description=Run gh-sks hourly

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now gh-sks.timer
log "Systemd timer enabled (runs hourly, catches up after reboot)."

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
echo "The systemd timer will sync keys automatically every hour."
echo "View logs with:  journalctl -u gh-sks"
