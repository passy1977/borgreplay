#!/bin/sh
#
# install-client.sh - installs the client side on the Borg host over SSH
#
# Usage (as a normal user, from this directory):   ./install-client.sh
#
# Copies client/bck_sync_to_borgreplay to /usr/local/bin and .env to
# /etc/borgreplay.env on $CLIENT_USER@$CLIENT_HOST (asks for the sudo password
# there). The crontab line in client/crontab-root is added by hand.

set -e

cd "$(dirname "$0")"

if [ ! -r .env ]; then
    echo "install-client.sh: .env missing, copy .env.sample to .env and fill it in" >&2
    exit 2
fi
. ./.env

if [ -z "$CLIENT_HOST" ] || [ -z "$CLIENT_USER" ]; then
    echo "install-client.sh: CLIENT_HOST or CLIENT_USER not set in .env" >&2
    exit 2
fi

TARGET="$CLIENT_USER@$CLIENT_HOST"

scp client/bck_sync_to_borgreplay .env "$TARGET:/tmp/"
ssh -t "$TARGET" 'sudo install -m 755 /tmp/bck_sync_to_borgreplay /usr/local/bin/bck_sync_to_borgreplay &&
    sudo install -m 644 /tmp/.env /etc/borgreplay.env &&
    rm -f /tmp/bck_sync_to_borgreplay /tmp/.env'

echo "client installed on $CLIENT_HOST"
