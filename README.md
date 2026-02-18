# gh-sks (GitHub SSH Key Sync)

Automatically sync GitHub users' public SSH keys into your Linux server's `~/.ssh/authorized_keys` file. Runs unattended via an **hourly cron job** that persists across reboots.

## How It Works

1. Reads user mappings from `/etc/gh-sks/github_authorized_users` (format: `<linux_user> <github_username>`).
2. Fetches each GitHub user's public keys from `https://github.com/<user>.keys`.
3. Merges them into a **managed block** inside the corresponding Linux user's `~/.ssh/authorized_keys`, preserving any keys added manually outside the block.

Multiple GitHub users can be mapped to the same Linux user, and the same GitHub user can be mapped to multiple Linux users. Adding or removing a line from the config file is all you need to grant or revoke access.

## Install

Run the one-liner as **root** (or with `sudo`):

```bash
curl -fsSL https://raw.githubusercontent.com/BenDutton/gh-sks/main/install.sh | sudo bash
```

This will:

1. Download `gh-sks` to `/usr/local/bin/`.
2. Create `/etc/gh-sks/github_authorized_users` if it doesn't already exist.
3. Register an **hourly cron job** under root's crontab (persists across VM restarts).
4. Install a **logrotate** config to rotate `/var/log/gh-sks.log` weekly (4 weeks retained, compressed).

After running the installer, edit the config file and add your user mappings:

```bash
sudo nano /etc/gh-sks/github_authorized_users
```

Then run a manual sync to verify everything works:

```bash
sudo gh-sks
```

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

## Cron

The installer sets up an hourly cron job automatically. Cron jobs are stored in the system crontab and persist across VM restarts — no additional configuration is needed.

To verify the job is installed:

```bash
crontab -l | grep gh-sks
```

Logs are written to `/var/log/gh-sks.log`. A logrotate config (`/etc/logrotate.d/gh-sks`) is installed automatically to rotate logs weekly and keep 4 compressed copies.

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
- Network access to `github.com`

## Uninstall

```bash
# Remove the cron job
sudo crontab -l | grep -v 'gh-sks' | sudo crontab -

# Remove the script
sudo rm /usr/local/bin/gh-sks

# Remove the config directory
sudo rm -rf /etc/gh-sks

# Remove the logrotate config
sudo rm -f /etc/logrotate.d/gh-sks

# Remove the managed block from each user's authorized_keys
# (between the BEGIN/END markers), or leave them as-is
```
