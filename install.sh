#!/usr/bin/env bash
set -euo pipefail
umask 077

INSTALL_DIR="/opt/google-region-monitor"
SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CRON_MARKER="# google-region-monitor"

if [[ "$EUID" -ne 0 ]]; then
    printf '%s\n' 'Run this installer with sudo or as root.' >&2
    exit 1
fi

for dependency in bash curl flock crontab install sed mktemp; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        printf 'Missing dependency: %s\n' "$dependency" >&2
        printf '%s\n' 'On Debian/Ubuntu: apt-get install curl util-linux cron' >&2
        exit 1
    fi
done

if [[ ! -f "$SOURCE_DIR/check.sh" ]]; then
    printf '%s\n' 'Place check.sh in the same directory as install.sh.' >&2
    exit 1
fi
bash -n "$SOURCE_DIR/check.sh"

# Preserve all unrelated entries in root's crontab.
cron_file=$(mktemp)
trap 'rm -f -- "$cron_file"' EXIT
if existing_cron=$(LC_ALL=C crontab -l 2>&1); then
    printf '%s\n' "$existing_cron" | sed '/# google-region-monitor$/d' > "$cron_file"
elif [[ "$existing_cron" == *'no crontab for'* ]]; then
    : > "$cron_file"
else
    printf '%s\n' 'Unable to read root crontab; installation stopped.' >&2
    exit 1
fi

install -d -m 700 "$INSTALL_DIR"
if [[ "$SOURCE_DIR" != "$INSTALL_DIR" ]]; then
    install -m 700 "$SOURCE_DIR/check.sh" "$INSTALL_DIR/check.sh"
fi
chmod 700 "$INSTALL_DIR/check.sh"

# Preserve the installed configuration on subsequent runs.
if [[ ! -e "$INSTALL_DIR/.env" ]]; then
    if [[ -f "$SOURCE_DIR/.env" ]]; then
        install -m 600 "$SOURCE_DIR/.env" "$INSTALL_DIR/.env"
    else
        cat > "$INSTALL_DIR/.env" <<'ENV'
SERVER_NAME="My VPS"
TG_BOT_TOKEN=""
TG_CHAT_ID=""
UA="Mozilla/5.0"
ENV
    fi
fi
chmod 600 "$INSTALL_DIR/.env"

# Daily at 08:00 in the cron daemon timezone; no timezone changes.
printf '0 8 * * * /bin/bash %s/check.sh >> %s/ip_check.log 2>&1 %s\n' \
    "$INSTALL_DIR" "$INSTALL_DIR" "$CRON_MARKER" >> "$cron_file"
crontab "$cron_file"

printf 'Installed: %s/check.sh\n' "$INSTALL_DIR"
printf 'Configuration: %s/.env\n' "$INSTALL_DIR"
printf '%s\n' 'Schedule: daily at 08:00 in the cron daemon timezone.'
printf '%s\n' 'Ensure the cron service is running.'
printf 'After configuring .env, test with: sudo bash %s/check.sh\n' "$INSTALL_DIR"

