# gh-sks (GitHub SSH Key Sync)

Automatically sync GitHub users' public SSH keys into your Linux server's `~/.ssh/authorized_keys` file. Runs unattended via an **hourly cron job** that persists across reboots.

## How It Works

1. Reads GitHub usernames from `~/.ssh/github_authorized_users` (one per line).
2. Fetches each user's public keys from `https://github.com/<user>.keys`.
3. Merges them into a **managed block** inside `~/.ssh/authorized_keys`, preserving any keys you've added manually outside the block.

Keys inside the managed block are replaced on every run, so adding or removing a username from the config file is all you need to grant or revoke access.

## Install

Run the one-liner as **root** (or with `sudo`), passing the target Linux username as an argument:

```bash
curl -fsSL https://raw.githubusercontent.com/BenDutton/gh-sks/main/install.sh | sudo bash -s -- <username>
```

For example, to set up key syncing for `azureuser`:

```bash
curl -fsSL https://raw.githubusercontent.com/BenDutton/gh-sks/main/install.sh | sudo bash -s -- azureuser
```

This will:

1. Download `gh-sks` to `/usr/local/bin/`.
2. Create `~<username>/.ssh/github_authorized_users` if it doesn't already exist.
3. Register an **hourly cron job** under the target user's crontab (persists across VM restarts).

After running the installer, edit the users file and add the GitHub usernames you want to authorize:

```bash
nano ~/.ssh/github_authorized_users
```

Then run a manual sync to verify everything works:

```bash
sudo -u <username> gh-sks
```

## Configuration

### `~/.ssh/github_authorized_users`

A plain-text file with one GitHub username per line. Blank lines and lines starting with `#` are ignored.

```
# Team leads
octocat
defunkt

# Contractors
torvalds
```

## Cron

The installer sets up an hourly cron job automatically. Cron jobs are stored in the system crontab and persist across VM restarts — no additional configuration is needed.

To verify the job is installed:

```bash
crontab -l | grep gh-sks
```

Logs are written to `/var/log/gh-sks.log`.

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
crontab -l | grep -v 'gh-sks' | crontab -

# Remove the script
sudo rm /usr/local/bin/gh-sks

# Remove the managed block from authorized_keys (between BEGIN/END markers),
nano ~/.ssh/authorized_keys

# Optionally remove the users file
rm ~/.ssh/github_authorized_users
```
