# gh-sks (GitHub SSH Key Sync)

Automatically sync GitHub users' public SSH keys into your Linux server's `~/.ssh/authorized_keys` file. Runs unattended via a **systemd timer** that fires hourly and catches up after reboots.

## How It Works

1. Reads user mappings from `/etc/gh-sks/github_authorized_users` (format: `<linux_user> <github_username>`).
2. Fetches each GitHub user's public keys from `https://github.com/<user>.keys`.
3. Merges them into a **managed block** inside the corresponding Linux user's `~/.ssh/authorized_keys`, preserving any keys added manually outside the block.

Multiple GitHub users can be mapped to the same Linux user, and the same GitHub user can be mapped to multiple Linux users. Adding or removing a line from the config file is all you need to grant or revoke access.

## Install

Run the one-liner as **root** (or with `sudo`):

```bash
curl -fsSL https://github.com/BenDutton/gh-sks/releases/latest/download/install.sh | sudo bash
```

This will:

1. Download `gh-sks` to `/usr/local/bin/`.
2. Create `/etc/gh-sks/github_authorized_users` if it doesn't already exist.
3. Install and enable a **systemd timer** that runs hourly.

After running the installer, edit the config file and add your user mappings:

```bash
sudo nano /etc/gh-sks/github_authorized_users
```

Then run a manual sync to verify everything works:

```bash
sudo gh-sks
```

## Managing Mappings

You can edit the config file directly, or use the built-in CLI helpers:

```bash
# Add a mapping
sudo gh-sks --add azureuser octocat

# Remove a mapping
sudo gh-sks --remove azureuser octocat
```

After adding or removing mappings, run `sudo gh-sks` to apply changes immediately (or wait for the next hourly sync).

## Configuration

### `/etc/gh-sks/github_authorized_users`

A plain-text file with one mapping per line in the format `<linux_user> <github_username>`. Blank lines and lines starting with `#` are ignored.

```
# Grant azureuser access via two GitHub accounts
azureuser octocat
azureuser defunkt

# Separate deploy user
deploy torvalds
```

## Scheduling

The installer sets up a **systemd timer** that runs `gh-sks` every hour. If the VM is off when a run is due, it fires immediately on boot (`Persistent=true`).

Check the timer status:

```bash
systemctl status gh-sks.timer
```

View logs:

```bash
journalctl -u gh-sks
```

Manually trigger a sync:

```bash
sudo systemctl start gh-sks.service
```

## How `authorized_keys` Is Managed

The script inserts keys between two marker comments:

```
# --- BEGIN gh-sks managed keys ---
# Auto-generated — do not edit this section manually.
ssh-rsa AAAA... github:octocat
ssh-ed25519 AAAA... github:defunkt
# --- END gh-sks managed keys ---
```

- **Keys outside the markers** are never touched — your manually-added keys are safe.
- **Keys inside the markers** are fully replaced on every run.
- Each key is annotated with `github:<username>` so you can identify who it belongs to.

## Requirements

- **bash** (4.0+)
- **curl**
- **systemd**
- Network access to `github.com`

## CLI Reference

| Command | Description |
|---------|-------------|
| `sudo gh-sks` | Run a key sync now |
| `sudo gh-sks --add <linux_user> <github_user>` | Add a mapping to the config file |
| `sudo gh-sks --remove <linux_user> <github_user>` | Remove a mapping from the config file |
| `gh-sks --list` | List all configured mappings |
| `sudo gh-sks --update` | Update gh-sks to the latest release |
| `sudo gh-sks --uninstall` | Fully remove gh-sks from this system |
| `gh-sks --version` | Print the installed version |
| `gh-sks --help` | Show help message |
