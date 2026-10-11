#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 Antonio Salsi
#
# install-client.sh - installs the client side on the Borg host over SSH
#
# Usage (as a normal user, from this directory):   ./install-client.sh
#
# Copies client/bck_sync_to_borgreplay to /usr/local/bin and .env to
# /etc/borgreplay/borgreplay.env on $CLIENT_USER@$CLIENT_HOST (asks for the sudo password
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
# Files of the versions before /etc/borgreplay/ are removed or moved there
ssh -t "$TARGET" 'sudo install -m 755 /tmp/bck_sync_to_borgreplay /usr/local/bin/bck_sync_to_borgreplay &&
    sudo install -d -m 755 /etc/borgreplay &&
    sudo install -m 644 /tmp/.env /etc/borgreplay/borgreplay.env &&
    sudo rm -f /etc/borgreplay.env &&
    { [ ! -e /etc/borgreplay-stay-awake.request ] ||
      sudo mv /etc/borgreplay-stay-awake.request /etc/borgreplay/stay-awake.request; } &&
    rm -f /tmp/bck_sync_to_borgreplay /tmp/.env'

echo "client installed on $CLIENT_HOST"
